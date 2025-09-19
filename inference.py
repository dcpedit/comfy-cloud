import os
import time
import uuid
import json
import logging
import traceback
from typing import Dict, Any, Optional
from flask import Flask, request, jsonify
import requests
import boto3
from botocore.exceptions import ClientError, NoCredentialsError

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration
COMFY_URL = "http://127.0.0.1:8188"
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

# Initialize S3 client with error handling
try:
    s3_client = boto3.client("s3", region_name=AWS_REGION)
    logger.info("S3 client initialized successfully")
except Exception as e:
    logger.warning(f"S3 client initialization failed: {e}")
    s3_client = None

def resolve_input_path(uri: str, local_dir: str = "/app/inputs") -> str:
    """Resolve input file path from S3 URI or local path."""
    try:
        if uri.startswith("s3://") and s3_client:
            # Parse S3 URI
            uri_parts = uri.replace("s3://", "").split("/", 1)
            if len(uri_parts) != 2:
                raise ValueError(f"Invalid S3 URI format: {uri}")
            
            bucket, key = uri_parts
            local_path = os.path.join(local_dir, os.path.basename(key))
            os.makedirs(local_dir, exist_ok=True)
            
            logger.info(f"Downloading {uri} to {local_path}")
            s3_client.download_file(bucket, key, local_path)
            return local_path
            
        else:
            # Local file path
            if not os.path.exists(uri):
                raise FileNotFoundError(f"Input file not found: {uri}")
            return uri
            
    except Exception as e:
        logger.error(f"Error resolving input path {uri}: {e}")
        raise

def upload_output(local_path: str, target: str) -> str:
    """Upload output file to S3 or local directory."""
    try:
        if target.startswith("s3://") and s3_client:
            # Parse S3 URI
            uri_parts = target.replace("s3://", "").split("/", 1)
            bucket = uri_parts[0]
            prefix = uri_parts[1] if len(uri_parts) > 1 else ""
            
            key = f"{prefix}/{os.path.basename(local_path)}" if prefix else os.path.basename(local_path)
            
            logger.info(f"Uploading {local_path} to s3://{bucket}/{key}")
            s3_client.upload_file(local_path, bucket, key)
            
            # Generate presigned URL
            url = s3_client.generate_presigned_url(
                "get_object",
                Params={"Bucket": bucket, "Key": key},
                ExpiresIn=3600
            )
            return url
            
        else:
            # Local directory
            os.makedirs(target, exist_ok=True)
            out_path = os.path.join(target, os.path.basename(local_path))
            os.rename(local_path, out_path)
            return out_path
            
    except Exception as e:
        logger.error(f"Error uploading output {local_path} to {target}: {e}")
        raise

def submit_workflow(workflow_json: Dict[str, Any]) -> str:
    """Submit workflow to ComfyUI and return prompt ID."""
    try:
        response = requests.post(
            f"{COMFY_URL}/prompt",
            json={"prompt": workflow_json},
            timeout=30
        )
        response.raise_for_status()
        result = response.json()
        prompt_id = result.get("prompt_id")
        
        if not prompt_id:
            raise ValueError("No prompt_id in ComfyUI response")
            
        logger.info(f"Workflow submitted with prompt_id: {prompt_id}")
        return prompt_id
        
    except Exception as e:
        logger.error(f"Error submitting workflow: {e}")
        raise

def wait_for_completion(prompt_id: str, poll_interval: float = 2.0, max_wait: int = 300) -> Dict[str, Any]:
    """Wait for workflow completion and return results."""
    start_time = time.time()
    
    while time.time() - start_time < max_wait:
        try:
            response = requests.get(f"{COMFY_URL}/history/{prompt_id}", timeout=10)
            response.raise_for_status()
            data = response.json()
            
            if prompt_id in data and "outputs" in data[prompt_id]:
                logger.info(f"Workflow {prompt_id} completed successfully")
                return data[prompt_id]
                
            time.sleep(poll_interval)
            
        except Exception as e:
            logger.warning(f"Error checking workflow status: {e}")
            time.sleep(poll_interval)
    
    raise TimeoutError(f"Workflow {prompt_id} did not complete within {max_wait} seconds")

@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint."""
    try:
        # Check ComfyUI connection
        response = requests.get(f"{COMFY_URL}/system_stats", timeout=5)
        response.raise_for_status()
        
        return jsonify({
            "status": "healthy",
            "comfyui": "connected",
            "timestamp": time.time()
        })
    except Exception as e:
        return jsonify({
            "status": "unhealthy",
            "error": str(e),
            "timestamp": time.time()
        }), 503

@app.route("/invocations", methods=["POST"])
def predict():
    """Main inference endpoint compatible with SageMaker."""
    job_id = None
    try:
        # Parse request
        data = request.get_json()
        if not data:
            return jsonify({"error": "No JSON data provided"}), 400
            
        job_id = data.get("job_id", str(uuid.uuid4()))
        logger.info(f"Processing job {job_id}")
        
        # Validate required fields
        required_fields = ["audio_s3", "transcript_s3", "image_s3", "output_s3_bucket"]
        for field in required_fields:
            if field not in data:
                return jsonify({"error": f"Missing required field: {field}"}), 400
        
        # Resolve input paths
        audio_path = resolve_input_path(data["audio_s3"])
        transcript_path = resolve_input_path(data["transcript_s3"])
        image_path = resolve_input_path(data["image_s3"])
        
        # Load workflow template
        workflow_path = "/app/ComfyUI/workflows/vibe_infinite.json"
        if not os.path.exists(workflow_path):
            # Use any available workflow as fallback
            workflow_files = [f for f in os.listdir("/app/ComfyUI/workflows") if f.endswith(".json")]
            if not workflow_files:
                return jsonify({"error": "No workflow files found"}), 500
            workflow_path = os.path.join("/app/ComfyUI/workflows", workflow_files[0])
            logger.warning(f"Using fallback workflow: {workflow_path}")
        
        with open(workflow_path, "r") as f:
            workflow = json.load(f)
        
        # Update workflow with input paths (this may need adjustment based on your workflow)
        # This is a generic approach - you'll need to adjust based on your specific workflow
        for node_id, node in workflow.items():
            inputs = node.get("inputs", {})
            if "audio" in inputs:
                inputs["audio"] = audio_path
            if "text_file" in inputs:
                inputs["text_file"] = transcript_path
            if "image" in inputs:
                inputs["image"] = image_path
        
        # Submit workflow
        prompt_id = submit_workflow(workflow)
        
        # Wait for completion
        result = wait_for_completion(prompt_id)
        
        # Process outputs
        outputs = []
        output_dir = "/app/ComfyUI/output"
        
        for node_id, node_outputs in result.get("outputs", {}).items():
            # Handle different output types
            for output_type in ["images", "videos", "audio"]:
                for output_item in node_outputs.get(output_type, []):
                    filename = output_item.get("filename")
                    if filename:
                        local_path = os.path.join(output_dir, filename)
                        if os.path.exists(local_path):
                            url = upload_output(local_path, data["output_s3_bucket"])
                            outputs.append({
                                "type": output_type,
                                "filename": filename,
                                "url": url
                            })
        
        return jsonify({
            "job_id": job_id,
            "status": "COMPLETED",
            "prompt_id": prompt_id,
            "outputs": outputs,
            "timestamp": time.time()
        })
        
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error processing job {job_id}: {error_msg}")
        logger.error(traceback.format_exc())
        
        return jsonify({
            "job_id": job_id,
            "status": "FAILED",
            "error": error_msg,
            "timestamp": time.time()
        }), 500

if __name__ == "__main__":
    logger.info("Starting ComfyUI Inference Service")
    logger.info(f"ComfyUI URL: {COMFY_URL}")
    logger.info(f"AWS Region: {AWS_REGION}")
    
    # Run with Flask development server (gunicorn is preferred for production)
    app.run(host="0.0.0.0", port=8080, debug=False)

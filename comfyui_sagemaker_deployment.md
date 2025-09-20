# 🚀 ComfyUI + VibeVoice + InfiniteTalk on AWS SageMaker (Async API)

This document explains how to deploy **ComfyUI workflows** (with VibeVoice, InfiniteTalk, WAN wrapper, and custom nodes) as a **serverless asynchronous API** on AWS using SageMaker.  

The final flow looks like this:

```
Client Request (audio + transcript + image)
                ↓
         API Gateway
                ↓
    SageMaker Async Endpoint
                ↓
    Docker Container (ComfyUI headless)
                ↓
    [VibeVoice Workflow]
                ↓
    [InfiniteTalk Workflow]
                ↓
         S3 (output video)
                ↓
    Callback to client (with S3 URL)
```

---

## 1. Docker Image Setup

We build a GPU-enabled Docker image with ComfyUI, custom nodes, and dependencies.

**Dockerfile**:

```dockerfile
FROM nvidia/cuda:12.1.1-runtime-ubuntu22.04

# Install Python and deps
RUN apt-get update && apt-get install -y     python3 python3-pip git wget ffmpeg libgl1 awscli     && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

WORKDIR /app/ComfyUI
RUN pip install --upgrade pip
RUN pip install -r requirements.txt

# Add custom nodes
WORKDIR /app/ComfyUI/custom_nodes
RUN git clone https://github.com/your-org/vibevoice-node.git
RUN git clone https://github.com/your-org/infinitetalk-node.git
RUN git clone https://github.com/your-org/wan-video-wrapper.git

# Extra modules
WORKDIR /app
RUN pip install bitsandbytes sageattention boto3 requests

# Copy workflows + inference code
WORKDIR /app
COPY workflows/ /app/workflows/
COPY inference.py /app/
COPY entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
```

---

## 2. Entrypoint Script

**entrypoint.sh**:

The entrypoint script now includes automatic S3 model synchronization. Set the `S3_MODELS_BUCKET` environment variable to enable automatic model syncing on container startup.

```bash
#!/bin/bash
set -e

# Automatic S3 sync (when S3_MODELS_BUCKET is set)
# This happens automatically - no manual intervention needed
if [ -n "$S3_MODELS_BUCKET" ]; then
    aws s3 sync s3://$S3_MODELS_BUCKET /app/ComfyUI/models
fi

# Start ComfyUI server in background
python3 /app/ComfyUI/main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch --verbose &
sleep 5

# Start SageMaker inference handler
python3 /app/inference.py
```

---

## 3. Inference Script

This script is the **SageMaker entrypoint**. It handles inputs, runs workflows, and uploads outputs.

**inference.py**:

```python
import os, time, uuid, json, requests, subprocess
import boto3

s3 = boto3.client("s3", region_name=os.environ.get("AWS_REGION", "us-east-1"))
COMFY_PORT = 8188
COMFY_URL = f"http://127.0.0.1:{COMFY_PORT}"

def resolve_input_path(uri: str, local_dir: str = "/app/inputs") -> str:
    if uri.startswith("s3://"):
        bucket, key = uri.replace("s3://", "").split("/", 1)
        local_path = os.path.join(local_dir, os.path.basename(key))
        os.makedirs(local_dir, exist_ok=True)
        s3.download_file(bucket, key, local_path)
        return local_path
    else:
        if not os.path.exists(uri):
            raise FileNotFoundError(f"Input file not found: {uri}")
        return uri

def upload_output(local_path: str, target: str) -> str:
    if target.startswith("s3://"):
        bucket, prefix = target.replace("s3://", "").split("/", 1)
        key = f"{prefix}/{os.path.basename(local_path)}"
        s3.upload_file(local_path, bucket, key)
        return s3.generate_presigned_url("get_object",
            Params={"Bucket": bucket, "Key": key}, ExpiresIn=3600)
    else:
        os.makedirs(target, exist_ok=True)
        out_path = os.path.join(target, os.path.basename(local_path))
        os.replace(local_path, out_path)
        return out_path

def submit_workflow(workflow_json: dict) -> str:
    resp = requests.post(f"{COMFY_URL}/prompt", json={"prompt": workflow_json})
    resp.raise_for_status()
    return resp.json()["prompt_id"]

def wait_for_completion(prompt_id: str, poll_interval: float = 2.0):
    while True:
        resp = requests.get(f"{COMFY_URL}/history/{prompt_id}")
        resp.raise_for_status()
        data = resp.json()
        if prompt_id in data and "outputs" in data[prompt_id]:
            return data[prompt_id]
        time.sleep(poll_interval)

# SageMaker handlers

def model_fn(model_dir): return None

def input_fn(request_body, request_content_type="application/json"):
    return json.loads(request_body)

def predict_fn(request, model):
    job_id = request.get("job_id", str(uuid.uuid4()))

    audio_path = resolve_input_path(request["audio_s3"])
    transcript_path = resolve_input_path(request["transcript_s3"])
    image_path = resolve_input_path(request["image_s3"])

    with open("/app/workflows/vibe_infinite.json") as f:
        workflow = json.load(f)

    workflow["5"]["inputs"]["audio"] = audio_path
    workflow["6"]["inputs"]["text_file"] = transcript_path
    workflow["7"]["inputs"]["image"] = image_path

    prompt_id = submit_workflow(workflow)
    result = wait_for_completion(prompt_id)

    outputs = []
    for node, node_outputs in result["outputs"].items():
        for out in node_outputs.get("images", []) + node_outputs.get("videos", []):
            local_path = os.path.join("/app/ComfyUI/output", out["filename"])
            url = upload_output(local_path, request["output_s3_bucket"])
            outputs.append(url)

    return {"job_id": job_id, "status": "COMPLETED", "outputs": outputs}

def output_fn(prediction, content_type="application/json"):
    return json.dumps(prediction)
```

---

## 4. Workflow JSON

Export your ComfyUI workflow locally and place it in `workflows/vibe_infinite.json`.  
Example snippet (simplified):

```json
{
  "5": { "class_type": "AudioLoader", "inputs": { "audio": "" } },
  "6": { "class_type": "TextFileLoader", "inputs": { "text_file": "" } },
  "7": { "class_type": "ImageLoader", "inputs": { "image": "" } },
  "10": { "class_type": "VibeVoiceNode", "inputs": { ... } },
  "11": { "class_type": "InfiniteTalkNode", "inputs": { ... } }
}
```

Your `inference.py` will inject actual file paths at runtime.

---

## 5. Automatic S3 Model Synchronization

The Docker container now supports automatic model synchronization from S3 on startup. This eliminates the need to manually copy models and ensures your container always has the latest models.

### Environment Variable Configuration

Set the `S3_MODELS_BUCKET` environment variable to enable automatic S3 sync:

```bash
# For Docker run
docker run --gpus all \
  -e S3_MODELS_BUCKET=comfyui-models-dp \
  -e AWS_ACCESS_KEY_ID=your_access_key \
  -e AWS_SECRET_ACCESS_KEY=your_secret_key \
  -e AWS_DEFAULT_REGION=us-east-1 \
  -p 8080:8080 -p 8188:8188 \
  comfyui-inference:latest
```

### Docker Compose Example

```yaml
version: '3.8'
services:
  comfyui:
    image: comfyui-inference:latest
    environment:
      - S3_MODELS_BUCKET=comfyui-models-dp
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      - AWS_DEFAULT_REGION=us-east-1
    ports:
      - "8080:8080"
      - "8188:8188"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

### Features

- **Automatic Sync**: Models are automatically synced from S3 on container startup
- **Error Handling**: If S3 sync fails, the container continues with existing models
- **Optional**: If `S3_MODELS_BUCKET` is not set, the container works normally without S3 sync
- **Progress Tracking**: Sync progress is logged to container output
- **Incremental**: Only new/changed files are downloaded (S3 sync behavior)

### AWS Permissions Required

Your AWS credentials need the following S3 permissions:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::comfyui-models-dp",
                "arn:aws:s3:::comfyui-models-dp/*"
            ]
        }
    ]
}
```

---

## 6. Local Testing

### Mount local inputs
```bash
docker run --gpus all -it --rm   -v $(pwd)/test_inputs:/app/inputs   -v $(pwd)/test_outputs:/app/outputs   comfyui-inference:latest   python3 /app/inference.py
```

### Test payload (local)
```json
{
  "job_id": "local-test",
  "audio_s3": "/app/inputs/audio.mp3",
  "transcript_s3": "/app/inputs/transcript.txt",
  "image_s3": "/app/inputs/image.png",
  "output_s3_bucket": "/app/outputs"
}
```

### Test payload (S3)
```json
{
  "job_id": "cloud-test",
  "audio_s3": "s3://my-bucket/audio.mp3",
  "transcript_s3": "s3://my-bucket/transcript.txt",
  "image_s3": "s3://my-bucket/image.png",
  "output_s3_bucket": "s3://my-output-bucket/results"
}
```

---

## 7. Deployment to SageMaker

1. Push image to ECR:
   ```bash
   docker build -t comfyui-inference .
   docker tag comfyui-inference:latest <account>.dkr.ecr.<region>.amazonaws.com/comfyui-inference:latest
   docker push <account>.dkr.ecr.<region>.amazonaws.com/comfyui-inference:latest
   ```

2. Configure SageMaker environment variables for S3 model sync:
   ```json
   {
     "Environment": {
       "S3_MODELS_BUCKET": "comfyui-models-dp"
     }
   }
   ```

   Make sure your SageMaker execution role has S3 read permissions for the models bucket.

3. Create async endpoint in SageMaker (via boto3 or console).

4. Hook API Gateway → SageMaker Async → Client.
   SageMaker will drop outputs in S3, then your Lambda can call back client with result.

### SageMaker IAM Role Requirements

Your SageMaker execution role needs these additional permissions for S3 model sync:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::comfyui-models-dp",
                "arn:aws:s3:::comfyui-models-dp/*"
            ]
        }
    ]
}
```

---

## ✅ Summary

- **Dockerfile**: defines environment + ComfyUI + nodes.  
- **entrypoint.sh**: syncs models + launches ComfyUI + inference.  
- **inference.py**: SageMaker entry script (downloads inputs, runs workflow, uploads outputs).  
- **workflows/**: exported JSON workflow templates.  
- **S3**: stores inputs, models, and outputs.  

This setup gives you a **scalable async API** around ComfyUI pipelines with **warm/cold start tradeoffs** managed by AWS.  


---

## 🔧 Entrypoint Scripts

### Two versions are provided:

#### **entrypoint.sh** (Development/EC2)
- Used for local Docker testing and EC2 deployments
- Keeps container running with `tail -f` for web UI access
- S3 sync enabled but inference service commented out
- Access ComfyUI at http://localhost:8188

#### **entrypoint-aws.sh** (SageMaker/Production)
- Used for SageMaker and API-only deployments
- Starts the inference service (`inference.py`)
- Includes verbose logging and model verification
- Designed for headless/API operation

**To deploy to SageMaker:** Replace `entrypoint.sh` with `entrypoint-aws.sh` in your Dockerfile:
```dockerfile
COPY entrypoint-aws.sh /app/entrypoint.sh
```

---

## 📦 Included Files

This package includes all the core components you’ll need:

- **Dockerfile** → Defines the container environment (CUDA, Python, ComfyUI, custom nodes, dependencies).  
- **entrypoint.sh** → Startup script that syncs models from S3, launches ComfyUI server, then runs inference.  
- **inference.py** → SageMaker-compatible script that:  
  - Downloads input files from S3 (or local)  
  - Injects them into the workflow  
  - Submits the workflow to ComfyUI  
  - Waits for results  
  - Uploads outputs back to S3  
- **workflows/vibe_infinite.json** → Example ComfyUI workflow with placeholders for audio, transcript, and image inputs.  

These files are bundled in the archive so you can build, test, and deploy your SageMaker container quickly.


---

## 🧪 Local Testing with `test_request.py`

You can test your container locally before deploying to AWS by running the included **test_request.py** script.

### 1. Build and run the container with mounted inputs/outputs
```bash
docker build -t comfyui-inference .

docker run --gpus all -it --rm   -p 8080:8080   -v $(pwd)/test_inputs:/app/inputs   -v $(pwd)/test_outputs:/app/outputs   comfyui-inference:latest
```

### 2. Add some test input files
Place these in `./test_inputs/` on your host machine:
- `audio.mp3` (sample audio file)  
- `transcript.txt` (text transcript)  
- `image.png` (input image)  

### 3. Run the test script
In another terminal:
```bash
python3 test_request.py
```

This will send a JSON request to your container’s `/invocations` endpoint.  
If everything works, you’ll see a JSON response with either local output file paths or pre-signed S3 URLs (depending on your config).

---

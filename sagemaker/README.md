Based on your ComfyUI workflows, here's a high-level architecture for converting this into a SageMaker API:

## Architecture Overview

### 1. **API Gateway + Lambda**
- Accept incoming requests with:
  - Source audio file (for voice cloning)
  - Text transcript
  - Person image
  - Optional: width, height, max_frames (with defaults: 640x640, 1000 frames)
- Upload input files to S3
- Trigger SageMaker endpoint

### 2. **SageMaker Endpoint**
- **Container Setup**: Extend your existing Docker container with:
  - Flask/FastAPI server to handle requests
  - ComfyUI API backend (not the web UI)
  - Workflow orchestration logic

### 3. **Workflow Orchestration**

The process would flow as:

```
Input → VibeVoice → InfiniteTalk → S3 → Response
```

**Step 1: VibeVoice Processing**
- Load source audio from S3
- Generate TTS audio using the text transcript
- Save output audio to temporary storage

**Step 2: InfiniteTalk Processing**
- Use VibeVoice output audio as input
- Load person image from S3
- Apply dimensions (width/height/max_frames)
- Generate animated video
- Upload final video to S3

**Step 3: Response**
- Return S3 public URL of the video

## Key Implementation Considerations

### Container Modifications
Your Docker container needs:
```python
# API server (app.py)
from flask import Flask, request
import comfyui_api_client  # You'll need to implement this

app = Flask(__name__)

@app.route('/process', methods=['POST'])
def process_request():
    # 1. Download inputs from S3
    # 2. Execute VibeVoice workflow via ComfyUI API
    # 3. Execute InfiniteTalk workflow with VibeVoice output
    # 4. Upload video to S3
    # 5. Return S3 URL
```

### ComfyUI API Integration
Instead of the web UI, you'll use ComfyUI's API mode:
- Start ComfyUI with `--listen 0.0.0.0 --port 8188`
- Programmatically submit workflows using the WebSocket API
- Modify workflow JSON to inject input file paths dynamically

### Workflow Modifications
You'll need to:
1. Convert workflows to use API-friendly nodes (file paths instead of UI uploads)
2. Chain workflows programmatically:
   - VibeVoice output path → InfiniteTalk input path
3. Add S3 upload logic after video generation

### SageMaker Configuration
- **Instance type**: Keep using GPU instances (ml.g4dn.xlarge or similar)
- **Model artifacts**: Package your models into model.tar.gz
- **Endpoint configuration**: Set appropriate timeout (these workflows can take minutes)

### S3 Structure
```
input/
  └── request-id/
      ├── source_audio.mp3
      ├── person_image.jpg
      └── transcript.txt
output/
  └── request-id/
      ├── vibevoice_audio.mp3
      └── final_video.mp4
```

## Challenges to Address

1. **Cold starts**: Model loading can be slow - consider keeping endpoint warm
2. **Timeouts**: Video generation can take several minutes - use async processing or step functions
3. **File handling**: ComfyUI expects local files - implement S3 ↔ local sync
4. **Error handling**: Workflows can fail at multiple points - add robust error handling

Would you like me to elaborate on any specific part of this architecture, such as the API server implementation or the workflow modification process?

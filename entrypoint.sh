#!/bin/bash
set -e

echo "=== Starting Optimized ComfyUI Deployment ==="
echo "GPU Support: $CUDA_VISIBLE_DEVICES"
echo "Timestamp: $(date)"

# Function to check if ComfyUI is ready
wait_for_comfyui() {
    echo "Waiting for ComfyUI to start..."
    for i in {1..30}; do
        if curl -s http://localhost:8188/system_stats >/dev/null 2>&1; then
            echo "✓ ComfyUI is ready!"
            return 0
        fi
        echo "  Attempt $i/30: Waiting for ComfyUI..."
        sleep 2
    done
    echo "✗ ComfyUI failed to start within 60 seconds"
    return 1
}

# Models are mounted from EBS volume at /app/ComfyUI/models
echo "Using EBS-mounted models directory"
model_count=$(find /app/ComfyUI/models -type f 2>/dev/null | wc -l)
echo "✓ Found $model_count model files on EBS volume."

# Create model directories if they don't exist
mkdir -p /app/ComfyUI/models/{checkpoints,vae,loras,upscale_models,embeddings,clip,tts/VibeVoice}

# Start ComfyUI server in background
echo "Starting ComfyUI server..."
cd /app/ComfyUI

# Configure ComfyUI for optimal GPU usage
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
export CUDA_LAUNCH_BLOCKING=0

# Verify GPU access before starting
echo "=== GPU Verification ==="
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi
    echo "✓ GPU access verified"
else
    echo "⚠ nvidia-smi not found - GPU may not be accessible"
fi

# Start ComfyUI with optimal settings
python3 main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --disable-auto-launch \
    --preview-method auto \
    --use-pytorch-cross-attention &

COMFYUI_PID=$!
echo "ComfyUI started with PID: $COMFYUI_PID"

# Wait for ComfyUI to be ready
if ! wait_for_comfyui; then
    echo "ComfyUI startup failed. Checking logs..."
    kill $COMFYUI_PID 2>/dev/null || true
    exit 1
fi

# Display GPU info
echo "=== GPU Information ==="
python3 -c "
import torch
print(f'CUDA Available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'CUDA Version: {torch.version.cuda}')
    print(f'GPU Count: {torch.cuda.device_count()}')
    print(f'GPU Name: {torch.cuda.get_device_name(0)}')
    print(f'GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB')
else:
    print('CUDA not available - running in CPU mode')
" || echo "GPU information check failed"

# Start inference service
echo "Starting inference service..."
cd /app

# Start with gunicorn for better performance
if command -v gunicorn >/dev/null 2>&1; then
    echo "Using gunicorn for production server..."
    exec gunicorn -w 1 -b 0.0.0.0:8080 --timeout 300 --preload inference:app
else
    echo "Using Python built-in server..."
    exec python3 inference.py
fi
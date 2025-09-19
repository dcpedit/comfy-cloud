FROM nvidia/cuda:12.1.1-runtime-ubuntu22.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV CUDA_VISIBLE_DEVICES=0

# Install system dependencies including AWS CLI with retry logic
RUN for i in 1 2 3; do \
        apt-get update && \
        apt-get install -y \
            python3 \
            python3-pip \
            python3-dev \
            git \
            wget \
            curl \
            unzip \
            ffmpeg \
            libgl1-mesa-glx \
            libglib2.0-0 \
            libsm6 \
            libxext6 \
            libxrender-dev \
            libgomp1 \
            tzdata && \
        rm -rf /var/lib/apt/lists/* && \
        apt-get clean && \
        break || \
        (echo "Attempt $i failed, retrying..." && sleep 10); \
    done

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

# Set timezone
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

WORKDIR /app

# Install ComfyUI first (stable version)
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

WORKDIR /app/ComfyUI

# Upgrade pip and install Python packages with optimizations
RUN python3 -m pip install --no-cache-dir --upgrade pip setuptools wheel

# Install PyTorch with CUDA support first
RUN pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# Install ComfyUI requirements with latest versions
RUN pip install --no-cache-dir --upgrade -r requirements.txt

# Install additional optimizations (with error handling)
RUN pip install --no-cache-dir \
    accelerate \
    bitsandbytes \
    transformers \
    diffusers \
    sageattention || echo "Some packages failed to install, continuing..."

# Install xformers separately with fallback
RUN pip install --no-cache-dir xformers || echo "xformers installation failed, will work without it"

# Install custom nodes
WORKDIR /app/ComfyUI/custom_nodes

# Updated custom nodes list
RUN git clone https://github.com/city96/ComfyUI-GGUF.git
RUN git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git
RUN git clone https://github.com/kijai/ComfyUI-KJNodes.git
RUN git clone https://github.com/Enemyx-net/VibeVoice-ComfyUI.git
RUN git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git
RUN git clone https://github.com/kijai/ComfyUI-MelBandRoFormer.git
RUN git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git

# Install requirements for all custom nodes
RUN find . -name "requirements.txt" -exec pip install --no-cache-dir -r {} \;

# Back to app directory and reinstall ComfyUI requirements to ensure latest versions
WORKDIR /app
RUN cd ComfyUI && pip install --no-cache-dir --upgrade -r requirements.txt

# Install server dependencies
RUN pip install --no-cache-dir \
    boto3 \
    requests \
    flask \
    gunicorn \
    sagemaker-inference

# Copy application files
COPY workflows/ /app/ComfyUI/workflows/
COPY inference.py /app/
COPY entrypoint.sh /app/entrypoint.sh

# Make entrypoint executable
RUN chmod +x /app/entrypoint.sh

# Create necessary directories (models directory will be EBS mounted)
RUN mkdir -p /app/ComfyUI/input \
    /app/ComfyUI/output

# Expose ports
EXPOSE 8188 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8188/system_stats || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]

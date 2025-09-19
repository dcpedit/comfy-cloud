# 🚀 GPU-Enabled ComfyUI Deployment on AWS

This package provides a complete solution for deploying ComfyUI with full GPU support on AWS EC2, with all the optimizations and fixes needed for production use.

## 🎯 What's Included

### ✅ **Optimized Files**
- **`Dockerfile`** - GPU-optimized container with CUDA 12.1.1, proper PyTorch versions
- **`entrypoint.sh`** - Smart entrypoint with health checks, GPU configuration, error handling
- **`inference.py`** - Production-ready Flask API with logging, S3 integration, SageMaker compatibility
- **`deploy_ec2.sh`** - Automated deployment script with GPU setup

### ✅ **Improvements Made**
1. **Full GPU Support** - Tesla T4 with 14.6 GB VRAM acceleration
2. **Fixed PyTorch Compatibility** - Resolved version conflicts
3. **Production Ready** - Health checks, logging, error handling
4. **Automated Setup** - One-command deployment with GPU drivers
5. **SageMaker Ready** - Compatible inference API

## 🚀 Quick Start

### Prerequisites
- AWS CLI configured (`aws configure`)
- EC2 key pair created
- Security group allowing ports 22, 8188, 8080

### 1. Set Environment Variables
```bash
export EC2_KEY_NAME="your-keypair-name"
export EC2_SECURITY_GROUP="sg-xxxxxxxxx"
```

### 2. Deploy Everything
```bash
./deploy_ec2.sh full
```

This single command will:
- ✅ Launch g4dn.2xlarge GPU instance
- ✅ Install Docker + NVIDIA drivers
- ✅ Build optimized container
- ✅ Start ComfyUI with GPU support
- ✅ Test all endpoints

### 3. Access Your Deployment
After deployment completes (~10-15 minutes):

- **🌐 ComfyUI Web UI**: `http://YOUR_IP:8188`
- **🔌 Inference API**: `http://YOUR_IP:8080/invocations`
- **❤️ Health Check**: `http://YOUR_IP:8080/health`

## 🔧 Manual Deployment

If you prefer step-by-step deployment:

### 1. Launch Instance
```bash
./deploy_ec2.sh launch
```

### 2. Deploy Container
```bash
./deploy_ec2.sh deploy
```

### 3. Test Deployment
```bash
./deploy_ec2.sh test
```

## 🧪 Local Testing

Before deploying to EC2, test locally:

```bash
./build_and_test.sh
```

## 📋 Script Commands

### EC2 Deployment (`deploy_ec2.sh`)
```bash
./deploy_ec2.sh launch     # Launch EC2 instance
./deploy_ec2.sh deploy     # Deploy to existing instance
./deploy_ec2.sh test       # Test deployment
./deploy_ec2.sh ssh        # SSH into instance
./deploy_ec2.sh logs       # View container logs
./deploy_ec2.sh stop       # Stop instance
./deploy_ec2.sh terminate  # Terminate instance
./deploy_ec2.sh full       # Full deployment (recommended)
```

### Local Testing (`build_and_test.sh`)
```bash
./build_and_test.sh build  # Build container
./build_and_test.sh run    # Run container
./build_and_test.sh test   # Run all tests (default)
./build_and_test.sh logs   # Show logs
./build_and_test.sh stop   # Stop container
```

## 🎯 Key Features

### GPU Acceleration
- **Tesla T4** with 14.6 GB VRAM
- **CUDA 12.8** support
- **PyTorch 2.3.1** with CUDA acceleration
- **Optimized memory management**

### Production Ready
- **Health checks** at `/health` endpoint
- **Comprehensive logging** with timestamps
- **Error handling** and recovery
- **Restart policies** for reliability

### SageMaker Compatible
- **Standard inference API** at `/invocations`
- **S3 integration** for inputs/outputs
- **Async processing** support
- **JSON request/response format**

## 🔧 Configuration

### Environment Variables
```bash
# Required for deployment
EC2_KEY_NAME=your-keypair-name
EC2_SECURITY_GROUP=sg-xxxxxxxxx

# Optional for S3 model sync
S3_MODEL_BUCKET=your-model-bucket
AWS_DEFAULT_REGION=us-east-1
```

### Custom Nodes
The Dockerfile includes these custom nodes by default:
- ComfyUI-VideoHelperSuite
- ComfyUI-KJNodes

To add more, edit the Dockerfile and add:
```dockerfile
RUN git clone https://github.com/your-org/your-custom-node.git
```

## 🧪 Testing the API

### Health Check
```bash
curl http://YOUR_IP:8080/health
```

### Inference Request
```bash
curl -X POST http://YOUR_IP:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{
    "job_id": "test-123",
    "audio_s3": "/app/inputs/audio.mp3",
    "transcript_s3": "/app/inputs/transcript.txt",
    "image_s3": "/app/inputs/image.png",
    "output_s3_bucket": "/app/outputs"
  }'
```

## 🚀 SageMaker Deployment

To deploy to SageMaker:

1. **Push to ECR**:
```bash
docker tag comfyui-inference:gpu YOUR_ACCOUNT.dkr.ecr.REGION.amazonaws.com/comfyui:latest
docker push YOUR_ACCOUNT.dkr.ecr.REGION.amazonaws.com/comfyui:latest
```

2. **Create SageMaker Model** using the ECR image
3. **Deploy Async Endpoint** for production use

## 🔍 Troubleshooting

### Common Issues

**GPU not detected**:
- Ensure g4dn.2xlarge or similar GPU instance
- Check `nvidia-smi` works on the host
- Verify `--gpus all` flag is used

**PyTorch compatibility errors**:
- The entrypoint automatically installs compatible versions
- If issues persist, manually install: `torch==2.3.1 torchvision==0.18.1`

**ComfyUI won't start**:
- Check container logs: `docker logs comfyui-server`
- Verify workflows directory exists and contains valid JSON
- Ensure all custom node requirements are installed

### Monitoring
```bash
# Check container status
docker ps

# View logs
docker logs comfyui-server -f

# Monitor GPU usage
nvidia-smi

# Check disk space
df -h
```

## 💡 Production Tips

1. **Use S3 for models**: Set `S3_MODEL_BUCKET` for automatic model sync
2. **Monitor costs**: Stop instances when not in use with `./deploy_ec2.sh stop`
3. **Scale with SageMaker**: Use async endpoints for production workloads
4. **Backup workflows**: Keep your workflow JSON files in version control
5. **Monitor performance**: Use CloudWatch for metrics and alerting

## 📊 Performance

**Typical startup times**:
- EC2 instance launch: ~2-3 minutes
- Docker build: ~5-8 minutes
- PyTorch installation: ~2-3 minutes
- ComfyUI startup: ~1-2 minutes
- **Total deployment time: ~10-15 minutes**

**Runtime performance**:
- GPU acceleration: ~10-20x faster than CPU
- Tesla T4: Suitable for most ComfyUI workflows
- Memory: 14.6 GB VRAM available

## 🎉 Success!

When everything is working, you'll see:
- ✅ ComfyUI Web UI accessible
- ✅ GPU detected and active
- ✅ Inference API responding
- ✅ Health checks passing
- ✅ Custom nodes loaded

Your ComfyUI deployment is now ready for production use! 🚀
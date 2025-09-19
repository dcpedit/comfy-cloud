# 🎬 ComfyUI Cloud Deployment Kit

*Because running AI workflows should be as comfy as it sounds* ☁️

Deploy ComfyUI with custom nodes (VibeVoice, InfiniteTalk, and friends) to AWS in style. Whether you want a quick EC2 instance or a fancy SageMaker async API, we've got you covered.

## 🚀 What's This?

This repo packages ComfyUI into production-ready containers that can:
- Generate videos from audio + text + images
- Scale automatically on AWS
- Handle GPU workloads without breaking a sweat
- Make your workflows accessible via REST APIs

Perfect for when you want to turn your ComfyUI experiments into something your friends (or customers) can actually use.

## ⚡ Quick Start

**The "I Just Want It Working" Path:**

1. Set your AWS credentials and key pair:
   ```bash
   export EC2_KEY_NAME=your-keypair
   export EC2_SECURITY_GROUP=sg-your-security-group
   ```

2. Deploy to EC2 (easiest option):
   ```bash
   ./deploy_ec2.sh full
   ```

3. Wait a few minutes, then visit the URL it gives you 🎉

**The "I Want to Test Locally First" Path:**

```bash
docker build -t comfyui-inference .
docker run --gpus all -p 8188:8188 -p 8080:8080 comfyui-inference
```

This builds the container and runs it locally so you can poke around before deploying.

## 📁 What's In The Box?

- **`deploy_ec2.sh`** - One-click EC2 deployment with all the GPU goodness
- **`Dockerfile`** - The recipe for your ComfyUI container
- **`inference.py`** - SageMaker-compatible API wrapper
- **`workflows/`** - Sample ComfyUI workflows ready to go
- **`entrypoint.sh`** - Container startup script

## 🎯 Deployment Options

### Option 1: EC2 (Recommended for Getting Started)
Perfect for development, demos, or when you want that classic "server you can SSH into" experience.

```bash
./deploy_ec2.sh full
```

Gets you a GPU-enabled EC2 instance with ComfyUI running on port 8188. Simple and reliable.

### Option 2: SageMaker Async (For Production APIs)
When you need to scale, handle lots of requests, or integrate with other AWS services.

See [`comfyui_sagemaker_deployment.md`](comfyui_sagemaker_deployment.md) for the full SageMaker setup guide.

## 🛠️ Customization

### Adding Your Own Workflows
1. Export your workflow from ComfyUI as JSON
2. Drop it in the `workflows/` folder
3. Update the workflow path in `inference.py`
4. Rebuild and deploy

### Adding Custom Nodes
Edit the `Dockerfile` to clone your custom node repos:
```dockerfile
RUN git clone https://github.com/your-org/your-awesome-node.git
```

### Different Models
Models are synced from S3 on startup. Just upload your models to the S3 bucket and they'll be available.

## 🧪 Testing

Before deploying to the cloud, test everything locally:

```bash
# Build and test the container
docker build -t comfyui-inference .
docker run --gpus all -p 8188:8188 -p 8080:8080 comfyui-inference
```

This builds the container and lets you test it locally. Much better than debugging in the cloud!

## 📚 Detailed Docs

- **[SageMaker Deployment Guide](comfyui_sagemaker_deployment.md)** - Full production setup
- **[EFS Setup Guide](EFS_SETUP_GUIDE.md)** - Shared storage configuration

## 💡 Tips & Tricks

- **First time?** Start with EC2 deployment - it's more straightforward
- **Testing locally?** Use the build_and_test.sh script - it catches issues early
- **Need help?** Check the validation script output - it's pretty good at telling you what's wrong
- **Going to production?** SageMaker async endpoints are your friend

## 🤔 Common Issues

**"My deployment failed"** - Check your AWS credentials and security group settings

**"Container won't start"** - Check if you have the right AWS permissions and your security group allows the ports

**"No GPU detected"** - Make sure you're using a GPU instance type (g4dn.2xlarge recommended)

**"Models not loading"** - Verify your S3 bucket exists and the container has access to it

## 🎉 What You Get

After deployment, you'll have:
- A ComfyUI web interface for testing workflows
- A REST API endpoint for programmatic access
- GPU-accelerated inference
- Automatic model syncing from S3
- Scalable infrastructure that won't break the bank

## 🤝 Contributing

Found a bug? Want to add support for more custom nodes? PRs welcome! This is meant to be a community resource for making ComfyUI deployments less painful.

---

*Built with ❤️ for the ComfyUI community. Now go make some awesome AI content!*
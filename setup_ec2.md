# EC2 Setup Guide for ComfyUI Deployment

## Prerequisites

1. **AWS Account with 8 vCPUs quota** for g4dn.2xlarge instances
2. **AWS CLI** installed and configured (`aws configure`) ✅
3. **EC2 Key Pair** created in your target region
4. **Security Group** with the following inbound rules:
   - Port 22 (SSH) from your IP
   - Port 8188 (ComfyUI Web UI) from your IP
   - Port 8080 (Inference API) from your IP
5. **S3 Bucket**: `comfyui-models-dp` (already hardcoded)

## Quick Start

### 1. Set Required Environment Variables

Since your AWS CLI is already configured, you only need:

```bash
export EC2_KEY_NAME="your-key-pair-name"
export EC2_SECURITY_GROUP="sg-xxxxxxxxx"
```

### 2. Launch and Deploy

```bash
# Full deployment (launch instance + deploy container + test)
./deploy_ec2.sh full
```

## Step-by-Step Deployment

### 1. Test Locally First

```bash
# Build and test the container locally
./build_and_test.sh test
```

### 2. Launch EC2 Instance

```bash
# Launch a new g4dn.2xlarge instance
./deploy_ec2.sh launch
```

This will:
- Launch a g4dn.2xlarge instance with Ubuntu 22.04
- Install Docker and NVIDIA drivers
- Set up 100GB root volume
- Output the public IP address

### 3. Deploy Container

```bash
# Deploy ComfyUI container to the instance
./deploy_ec2.sh deploy
```

### 4. Test Deployment

```bash
# Run tests against the deployed instance
./deploy_ec2.sh test
```

### 5. Access ComfyUI

After successful deployment:
- **Web UI**: `http://<instance-ip>:8188`
- **API**: `http://<instance-ip>:8080/invocations`

## Management Commands

```bash
# SSH into the instance
./deploy_ec2.sh ssh

# View container logs
./deploy_ec2.sh logs

# Stop instance (preserves data)
./deploy_ec2.sh stop

# Terminate instance (destroys everything)
./deploy_ec2.sh terminate
```

## Cost Optimization

### g4dn.2xlarge Pricing (US East 1)
- **On-Demand**: ~$0.75/hour
- **Spot**: ~$0.22/hour (up to 70% savings)

### To use Spot Instances

Modify the `deploy_ec2.sh` script's launch command:

```bash
--instance-market-options "MarketType=spot,SpotOptions={MaxPrice=0.30,SpotInstanceType=one-time}"
```

### Auto-stop after inactivity

Add this cron job on the EC2 instance:

```bash
# Auto-stop after 30 minutes of no Docker activity
*/5 * * * * if [ $(docker ps -q | wc -l) -eq 0 ]; then sudo shutdown -h +30; fi
```

## Troubleshooting

### Container won't start
```bash
# Check logs
./deploy_ec2.sh logs

# SSH and inspect
./deploy_ec2.sh ssh
docker ps -a
docker logs comfyui-server
```

### GPU not detected
```bash
# SSH and check NVIDIA drivers
./deploy_ec2.sh ssh
nvidia-smi
docker run --rm --gpus all nvidia/cuda:12.1.1-base-ubuntu22.04 nvidia-smi
```

### Out of memory errors
The g4dn.2xlarge has:
- 8 vCPUs
- 32 GB RAM
- 16 GB GPU memory (NVIDIA T4)

For larger models, consider:
- g4dn.4xlarge (64 GB RAM)
- g4dn.8xlarge (128 GB RAM)

## Security Best Practices

1. **Restrict Security Group** to your IP only
2. **Use IAM roles** instead of AWS keys in production
3. **Enable CloudWatch** monitoring
4. **Set up backups** for the models volume
5. **Use Systems Manager** for patching

## Model Storage

Models can be stored in:
1. **S3 Bucket** (recommended) - Sync on container start
2. **EBS Volume** - Persistent across restarts
3. **Instance Store** - Fastest but ephemeral

To pre-load models to S3:
```bash
aws s3 sync ./models s3://comfyui-models-dp/comfyui/models/
```

## Monitoring

View instance metrics:
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=$(cat .ec2_instance_id) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```
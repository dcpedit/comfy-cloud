#!/bin/bash
set -e

# EC2 Optimized Deployment Script for ComfyUI on g4dn.2xlarge
# NVIDIA Driver fixes and Ubuntu 24.04 compatibility included

# Configuration defaults (will be overridden by .env file)
DEFAULT_INSTANCE_TYPE="g4dn.2xlarge"
DEFAULT_VOLUME_SIZE=150  # Increased from 100GB to accommodate large AI models
AMI_ID="ami-0e2c8caa4b6378d8c"  # Ubuntu 24.04 LTS in us-east-1 (update for your region)
INSTANCE_NAME="ComfyUI-Server-Optimized"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load environment variables from .env file
load_env() {
    if [[ -f ".env" ]]; then
        echo -e "${YELLOW}Loading configuration from .env file...${NC}"
        export $(grep -v '^#' .env | xargs)
    fi

    # Set configuration variables after loading .env
    INSTANCE_TYPE="${EC2_INSTANCE_TYPE:-$DEFAULT_INSTANCE_TYPE}"
    VOLUME_SIZE="${EC2_VOLUME_SIZE:-$DEFAULT_VOLUME_SIZE}"
    KEY_NAME="${EC2_KEY_NAME}"
    SECURITY_GROUP="${EC2_SECURITY_GROUP}"
    S3_MODELS_BUCKET="${S3_MODELS_BUCKET:-comfyui-models-dp}"
}

# Display deployment header
show_header() {
    echo "===================================="
    echo "ComfyUI EC2 Optimized Deployment"
    echo "Instance Type: ${INSTANCE_TYPE}"
    echo "Volume Size: ${VOLUME_SIZE}GB"
    echo "NVIDIA Drivers: Fixed for Ubuntu 24.04"
    echo "===================================="
}

# Function to check prerequisites
check_prerequisites() {
    load_env
    show_header
    echo -e "${YELLOW}Checking prerequisites...${NC}"

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}AWS CLI not found. Please install it first.${NC}"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}AWS credentials not configured. Run 'aws configure' first.${NC}"
        exit 1
    fi

    # Check required environment variables
    if [[ -z "$KEY_NAME" ]]; then
        echo -e "${RED}Please set EC2_KEY_NAME environment variable with your EC2 key pair name${NC}"
        echo -e "${YELLOW}Example: export EC2_KEY_NAME=my-keypair${NC}"
        exit 1
    fi

    if [[ -z "$SECURITY_GROUP" ]]; then
        echo -e "${RED}Please set EC2_SECURITY_GROUP environment variable with your security group ID${NC}"
        echo -e "${YELLOW}Example: export EC2_SECURITY_GROUP=sg-0123456789abcdef${NC}"
        exit 1
    fi

    # Validate instance type (basic check for GPU instances)
    if [[ ! "$INSTANCE_TYPE" =~ ^(g[4-6]|p[2-5]|gr) ]]; then
        echo -e "${YELLOW}Warning: Instance type '$INSTANCE_TYPE' may not have GPU support${NC}"
        echo -e "${YELLOW}Recommended GPU instance types: g6.xlarge, g4dn.2xlarge, g5.2xlarge, p3.2xlarge${NC}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Verify key pair exists
    if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" &> /dev/null; then
        echo -e "${RED}Key pair '$KEY_NAME' not found in current region${NC}"
        exit 1
    fi

    echo -e "${GREEN}Prerequisites check passed!${NC}"
}

# Function to launch EC2 instance with NVIDIA driver fixes
launch_instance() {
    echo -e "${YELLOW}Launching EC2 instance with NVIDIA driver fixes...${NC}"

    # Create OPTIMIZED user data script for Ubuntu 24.04
    cat > /tmp/user_data_optimized.sh << 'EOF'
#!/bin/bash
set -e

echo "=== Optimized ComfyUI Instance Setup ==="
echo "Starting at: $(date)"

# Update system with proper frontend handling
export DEBIAN_FRONTEND=noninteractive
apt-get update

# Install NVIDIA driver FIRST (critical for GPU instances)
echo "Installing NVIDIA driver..."
apt-get install -y nvidia-driver-535
echo "✓ NVIDIA driver installed"

# Install Docker and dependencies with correct package names for Ubuntu 24.04
echo "Installing Docker and dependencies..."
apt-get install -y \
    docker.io \
    docker-compose-v2 \
    git \
    curl \
    unzip

# Enable and start Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu
echo "✓ Docker installed and configured"

# Install NVIDIA Container Toolkit (Ubuntu 24.04 compatible method)
echo "Installing NVIDIA Container Toolkit..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update
apt-get install -y nvidia-container-toolkit

# Configure NVIDIA Container Toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
echo "✓ NVIDIA Container Toolkit configured"

# Wait for NVIDIA driver and Docker to be fully ready
echo "Waiting for NVIDIA driver initialization..."
sleep 60

# Test NVIDIA driver
if nvidia-smi; then
    echo "✓ NVIDIA driver working correctly"
else
    echo "⚠ NVIDIA driver may need more time"
fi

# Test Docker with GPU
if docker run --rm --gpus all nvidia/cuda:12.1.1-runtime-ubuntu22.04 nvidia-smi; then
    echo "✓ Docker GPU access confirmed"
else
    echo "⚠ Docker GPU access may need configuration"
fi

# Create working directory
mkdir -p /home/ubuntu/comfyui
chown ubuntu:ubuntu /home/ubuntu/comfyui

# Create working directory for models (using local storage)
echo "Setting up local model storage..."
mkdir -p /home/ubuntu/models
chown ubuntu:ubuntu /home/ubuntu/models
echo "✓ Local model storage ready at /home/ubuntu/models"

# Mark completion
touch /home/ubuntu/user-data-complete
echo "=== Setup completed at: $(date) ==="
EOF

    # Create IAM role for S3 access if it doesn't exist
    ROLE_NAME="ComfyUI-S3-Access-Role"
    INSTANCE_PROFILE_NAME="ComfyUI-S3-Access-Profile"

    # Check if IAM role exists
    if ! aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        echo -e "${YELLOW}Creating IAM role for S3 access...${NC}"

        # Create trust policy
        cat > /tmp/trust-policy.json << 'TRUST_POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
TRUST_POLICY

        # Create S3 access policy
        cat > /tmp/s3-policy.json << 'S3_POLICY'
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
S3_POLICY

        # Create role
        aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document file:///tmp/trust-policy.json

        # Create and attach policy
        aws iam put-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-name "ComfyUI-S3-Access" \
            --policy-document file:///tmp/s3-policy.json

        # Create instance profile
        aws iam create-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME"

        # Add role to instance profile
        aws iam add-role-to-instance-profile \
            --instance-profile-name "$INSTANCE_PROFILE_NAME" \
            --role-name "$ROLE_NAME"

        echo -e "${GREEN}IAM role created successfully${NC}"
        sleep 10  # Wait for role propagation
    fi

    # Launch instance
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SECURITY_GROUP" \
        --iam-instance-profile Name="$INSTANCE_PROFILE_NAME" \
        --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3}" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
        --user-data file:///tmp/user_data_optimized.sh \
        --output text \
        --query 'Instances[0].InstanceId')

    echo -e "${GREEN}Instance launched: $INSTANCE_ID${NC}"

    # Wait for instance to be running
    echo -e "${YELLOW}Waiting for instance to be running...${NC}"
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

    # Get public IP
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    echo -e "${GREEN}Instance is running!${NC}"
    echo -e "${GREEN}Public IP: $PUBLIC_IP${NC}"

    # Save instance info
    echo "$INSTANCE_ID" > .ec2_instance_id
    echo "$PUBLIC_IP" > .ec2_public_ip

    echo -e "${GREEN}Instance launched successfully without EBS volumes${NC}"

    # Wait for SSH to be available
    echo -e "${YELLOW}Waiting for SSH to be available...${NC}"
    while ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/"$KEY_NAME".pem ubuntu@"$PUBLIC_IP" "echo 'SSH is ready'" 2>/dev/null; do
        echo -n "."
        sleep 10
    done
    echo ""
    echo -e "${GREEN}SSH is ready!${NC}"

    # Show real-time progress of user-data script
    echo -e "${YELLOW}Monitoring system initialization progress...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to skip monitoring (deployment will continue)${NC}"
    ssh -i ~/.ssh/"$KEY_NAME".pem ubuntu@"$PUBLIC_IP" "
        echo '=== Following cloud-init progress ==='
        # Wait a moment for cloud-init to start
        sleep 5
        # Follow cloud-init output with timeout
        timeout 300 tail -f /var/log/cloud-init-output.log 2>/dev/null || echo 'Cloud-init log monitoring timed out or completed'
        echo '=== Cloud-init monitoring finished ==='
    " || echo "Cloud-init monitoring ended"
}

# Function to deploy container with NVIDIA driver verification
deploy_container() {
    load_env
    if [ ! -f .ec2_public_ip ]; then
        echo -e "${RED}No EC2 instance found. Run with 'launch' first.${NC}"
        exit 1
    fi

    PUBLIC_IP=$(cat .ec2_public_ip)
    echo -e "${YELLOW}Deploying optimized container to $PUBLIC_IP...${NC}"

    # Create optimized deployment script
    cat > /tmp/deploy_optimized.sh << 'DEPLOY_SCRIPT'
#!/bin/bash
set -e

# Wait for user-data script to complete
echo "=== Waiting for optimized system initialization ==="
timeout=300
elapsed=0
while [ ! -f /home/ubuntu/user-data-complete ] && [ $elapsed -lt $timeout ]; do
    echo "  System still initializing... ($elapsed/$timeout seconds)"
    # Show what processes are running
    if [ $((elapsed % 30)) -eq 0 ]; then
        echo "    Current activity:"
        ps aux | grep -E "(apt|docker|nvidia)" | grep -v grep | head -3 || echo "    No major installation processes detected"
    fi
    sleep 10
    elapsed=$((elapsed + 10))
done

if [ ! -f /home/ubuntu/user-data-complete ]; then
    echo "❌ System initialization timed out"
    exit 1
fi
echo "✓ System initialization complete!"

# Verify all components are ready
echo "=== Verifying system components ==="

# Check Docker
if docker info >/dev/null 2>&1; then
    echo "✓ Docker is ready"
else
    echo "❌ Docker is not ready"
    exit 1
fi

# Check NVIDIA driver
if nvidia-smi >/dev/null 2>&1; then
    echo "✓ NVIDIA driver is working"
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
else
    echo "❌ NVIDIA driver is not working"
    exit 1
fi

# Test Docker GPU access
if docker run --rm --gpus all nvidia/cuda:12.1.1-runtime-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
    echo "✓ Docker GPU access confirmed"
else
    echo "❌ Docker GPU access failed"
    exit 1
fi

cd /home/ubuntu/comfyui

# Create necessary directories
mkdir -p outputs

echo "=== Building optimized ComfyUI container ==="
echo "This may take 5-10 minutes for first build..."
docker build -t comfyui-inference:gpu-optimized . | while read line; do
    echo "BUILD: $line"
done

# Stop any existing containers
docker stop comfyui-server 2>/dev/null || true
docker rm comfyui-server 2>/dev/null || true

echo "=== Starting optimized ComfyUI container ==="
docker run -d \
    --name comfyui-server \
    --gpus all \
    --restart unless-stopped \
    -p 8188:8188 \
    -p 8080:8080 \
    -v $(pwd)/inputs:/app/inputs \
    -v $(pwd)/outputs:/app/outputs \
    -v /home/ubuntu/models:/app/ComfyUI/models \
    -e AWS_DEFAULT_REGION=${AWS_REGION:-us-east-1} \
    -e S3_MODELS_BUCKET=${S3_MODELS_BUCKET} \
    -e CUDA_VISIBLE_DEVICES=0 \
    -e PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512 \
    --health-cmd='curl -f http://localhost:8188/system_stats || exit 1' \
    --health-interval=30s \
    --health-timeout=10s \
    --health-retries=3 \
    comfyui-inference:gpu-optimized

echo "=== Container startup verification ==="
echo "Waiting 30 seconds for container to initialize..."
for i in {1..30}; do
    echo -n "."
    sleep 1
done
echo ""

# Check container status
if docker ps | grep -q comfyui-server; then
    echo "✓ Container is running"
else
    echo "❌ Container failed to start"
    docker logs comfyui-server
    exit 1
fi

# Wait for services to initialize
echo "=== Waiting for services to initialize ==="
echo "Waiting 60 seconds for ComfyUI and inference service to start..."
for i in {1..12}; do
    echo "  $((i*5))/60 seconds..."
    sleep 5
done

# Test endpoints
echo "=== Testing endpoints ==="
for i in {1..10}; do
    if curl -s http://localhost:8188/system_stats >/dev/null 2>&1; then
        echo "✓ ComfyUI API is responding"
        break
    fi
    echo "  Attempt $i/10: ComfyUI still starting..."
    sleep 30
done

for i in {1..5}; do
    if curl -s http://localhost:8080/health >/dev/null 2>&1; then
        echo "✓ Inference API is responding"
        break
    fi
    echo "  Attempt $i/5: Inference service still starting..."
    sleep 30
done

# Final verification
echo "=== Final verification ==="
docker exec comfyui-server nvidia-smi && echo "✓ GPU accessible in container"
docker exec comfyui-server ls /app/ComfyUI/models/ | wc -l | xargs echo "Model directories found:"

echo ""
echo "🎉 Optimized deployment completed successfully!"
echo "🌐 ComfyUI Web UI: http://$(curl -s http://checkip.amazonaws.com):8188"
echo "🔌 Inference API: http://$(curl -s http://checkip.amazonaws.com):8080/invocations"
echo "❤️ Health Check: http://$(curl -s http://checkip.amazonaws.com):8080/health"
DEPLOY_SCRIPT

    # Copy files to EC2
    echo -e "${YELLOW}Copying optimized files to EC2...${NC}"
    scp -i ~/.ssh/"$KEY_NAME".pem -r \
        Dockerfile \
        entrypoint.sh \
        inference.py \
        workflows \
        ubuntu@"$PUBLIC_IP":/home/ubuntu/comfyui/

    # Execute deployment
    ssh -i ~/.ssh/"$KEY_NAME".pem ubuntu@"$PUBLIC_IP" "bash -s" < /tmp/deploy_optimized.sh
}

# Main execution
case "${1:-help}" in
    launch)
        check_prerequisites
        launch_instance
        ;;
    deploy)
        deploy_container
        ;;
    full)
        check_prerequisites
        launch_instance
        sleep 30  # Give instance time to fully initialize
        deploy_container
        echo -e "${GREEN}✅ Optimized deployment complete!${NC}"
        echo -e "${GREEN}ComfyUI URL: http://$(cat .ec2_public_ip):8188${NC}"
        ;;
    *)
        echo "Usage: $0 {launch|deploy|full}"
        echo ""
        echo "🚀 Optimized ComfyUI EC2 Deployment"
        echo "✅ NVIDIA driver fixes included"
        echo "✅ Ubuntu 24.04 compatibility"
        echo "✅ Comprehensive error handling"
        echo "✅ GPU verification built-in"
        ;;
esac
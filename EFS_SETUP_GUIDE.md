# 🚀 ComfyUI EFS Setup Guide

Complete guide to set up Amazon EFS (Elastic File System) for shared model storage across multiple ComfyUI instances.

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Step 1: Create EFS File System](#step-1-create-efs-file-system)
3. [Step 2: Configure Security Groups](#step-2-configure-security-groups)
4. [Step 3: Mount EFS on EC2](#step-3-mount-efs-on-ec2)
5. [Step 4: Migrate Models to EFS](#step-4-migrate-models-to-efs)
6. [Step 5: Update Docker Configuration](#step-5-update-docker-configuration)
7. [Step 6: Test and Validate](#step-6-test-and-validate)
8. [Troubleshooting](#troubleshooting)
9. [Cost Optimization](#cost-optimization)

---

## Prerequisites

Before starting, ensure you have:

- ✅ AWS CLI configured with appropriate permissions
- ✅ EC2 instance running Ubuntu with Docker installed
- ✅ Existing ComfyUI Docker setup
- ✅ Model files currently stored on EBS volumes
- ✅ Basic understanding of AWS networking (VPC, Security Groups)

**Required AWS Permissions:**
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "elasticfilesystem:*",
                "ec2:DescribeInstances",
                "ec2:DescribeSecurityGroups",
                "ec2:CreateSecurityGroup",
                "ec2:AuthorizeSecurityGroupIngress"
            ],
            "Resource": "*"
        }
    ]
}
```

---

## Step 1: Create EFS File System

### 1.1 Create the EFS File System

```bash
# Create EFS file system
aws efs create-file-system \
    --creation-token comfyui-models-$(date +%s) \
    --performance-mode generalPurpose \
    --throughput-mode provisioned \
    --provisioned-throughput-in-mibps 100 \
    --encrypted \
    --tags Key=Name,Value="ComfyUI-Models" Key=Purpose,Value="SharedModelStorage"
```

**Expected Output:**
```json
{
    "FileSystemId": "fs-xxxxxxxxx",
    "LifeCycleState": "creating",
    "CreationTime": "2024-01-15T10:30:00Z",
    "ThroughputMode": "provisioned",
    "ProvisionedThroughputInMibps": 100.0,
    "Encrypted": true
}
```

### 1.2 Wait for EFS Creation

```bash
# Get your EFS ID (replace with output from above)
EFS_ID="fs-xxxxxxxxx"

# Wait for EFS to be available
aws efs describe-file-systems --file-system-id $EFS_ID --query 'FileSystems[0].LifeCycleState'
```

Wait until the state shows `"available"`.

---

## Step 2: Configure Security Groups

### 2.1 Get Your VPC and Instance Details

```bash
# Get your EC2 instance details
INSTANCE_ID="i-xxxxxxxxx"  # Replace with your instance ID
VPC_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].VpcId' --output text)
SUBNET_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].SubnetId' --output text)

echo "VPC ID: $VPC_ID"
echo "Subnet ID: $SUBNET_ID"
```

### 2.2 Create EFS Security Group

```bash
# Create security group for EFS
EFS_SG_ID=$(aws ec2 create-security-group \
    --group-name ComfyUI-EFS-Access \
    --description "Security group for ComfyUI EFS access" \
    --vpc-id $VPC_ID \
    --query 'GroupId' --output text)

echo "EFS Security Group ID: $EFS_SG_ID"
```

### 2.3 Configure Security Group Rules

```bash
# Get your EC2 instance's security group
EC2_SG_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

# Allow NFS traffic from EC2 to EFS
aws ec2 authorize-security-group-ingress \
    --group-id $EFS_SG_ID \
    --protocol tcp \
    --port 2049 \
    --source-group $EC2_SG_ID

echo "✅ Security group configured for NFS access"
```

---

## Step 3: Mount EFS on EC2

### 3.1 Create Mount Targets

```bash
# Get availability zone of your instance
AZ=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text)

# Create mount target in the same AZ
MOUNT_TARGET_ID=$(aws efs create-mount-target \
    --file-system-id $EFS_ID \
    --subnet-id $SUBNET_ID \
    --security-groups $EFS_SG_ID \
    --query 'MountTargetId' --output text)

echo "Mount Target ID: $MOUNT_TARGET_ID"
```

### 3.2 Wait for Mount Target

```bash
# Wait for mount target to be available
echo "Waiting for mount target to be available..."
while true; do
    STATE=$(aws efs describe-mount-targets --mount-target-id $MOUNT_TARGET_ID --query 'MountTargets[0].LifeCycleState' --output text)
    if [ "$STATE" = "available" ]; then
        echo "✅ Mount target is available"
        break
    fi
    echo "Mount target state: $STATE (waiting...)"
    sleep 10
done
```

### 3.3 Install NFS Utilities

```bash
# SSH to your EC2 instance and install NFS utils
ssh ubuntu@YOUR_EC2_IP "sudo apt-get update && sudo apt-get install -y nfs-common"
```

### 3.4 Get Mount Target IP

```bash
# Get the IP address of the mount target
MOUNT_TARGET_IP=$(aws efs describe-mount-targets --mount-target-id $MOUNT_TARGET_ID --query 'MountTargets[0].IpAddress' --output text)
echo "Mount Target IP: $MOUNT_TARGET_IP"
```

### 3.5 Mount EFS on EC2

```bash
# SSH to your EC2 instance and create mount point
ssh ubuntu@YOUR_EC2_IP "
    # Create mount directory
    mkdir -p /home/ubuntu/efs_models

    # Mount EFS
    sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr $MOUNT_TARGET_IP:/ /home/ubuntu/efs_models

    # Set permissions
    sudo chown ubuntu:ubuntu /home/ubuntu/efs_models

    # Verify mount
    df -h /home/ubuntu/efs_models
"
```

### 3.6 Configure Automatic Mounting

```bash
# Add to fstab for automatic mounting on boot
ssh ubuntu@YOUR_EC2_IP "
    echo '$MOUNT_TARGET_IP:/ /home/ubuntu/efs_models nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr 0 0' | sudo tee -a /etc/fstab

    # Test fstab entry
    sudo umount /home/ubuntu/efs_models
    sudo mount -a
    df -h /home/ubuntu/efs_models
"
```

---

## Step 4: Migrate Models to EFS

### 4.1 Copy Models from EBS to EFS

If you have existing models on EBS volumes:

```bash
# SSH to your EC2 instance
ssh ubuntu@YOUR_EC2_IP

# If models are on an EBS volume (replace /mnt/ebs-models with your EBS mount)
sudo rsync -av --info=progress2 /mnt/ebs-models/ /home/ubuntu/efs_models/

# Alternative: Copy from local directory
# rsync -av /path/to/your/models/ /home/ubuntu/efs_models/
```

### 4.2 Verify Model Transfer

```bash
# Check models are copied correctly
ssh ubuntu@YOUR_EC2_IP "
    echo 'EFS Models Directory:'
    ls -la /home/ubuntu/efs_models/

    echo 'Model file count:'
    find /home/ubuntu/efs_models -type f \( -name '*.safetensors' -o -name '*.gguf' -o -name '*.bin' -o -name '*.pt' \) | wc -l

    echo 'Total size:'
    du -sh /home/ubuntu/efs_models
"
```

---

## Step 5: Update Docker Configuration

### 5.1 Download EFS-Optimized Scripts

The ComfyUI project should include these files. If not, create them:

```bash
# SSH to your EC2 instance
ssh ubuntu@YOUR_EC2_IP

# Navigate to your ComfyUI directory
cd /home/ubuntu/comfyui

# Verify EFS scripts exist
ls -la *efs*
```

**Required files:**
- `entrypoint-efs.sh` - EFS-optimized container startup
- `run-comfyui-efs.sh` - Automated Docker runner
- `test-efs.sh` - EFS validation script
- `Dockerfile-efs` - EFS-optimized Dockerfile

### 5.2 Test EFS Integration

```bash
# Run the EFS test
cd /home/ubuntu/comfyui
./test-efs.sh
```

**Expected output:**
```
=== ComfyUI EFS Test ===
1. Testing EFS mount...
✅ EFS directory exists

2. Counting model files...
Found X model files

3. EFS disk usage:
Filesystem      Size  Used Avail Use% Mounted on
XXX.XXX.XXX.XXX:/  8.0E     0  8.0E   0% /home/ubuntu/efs_models

4. Testing Docker volume mount...
✅ Models accessible in container

✅ EFS test completed!
```

### 5.3 Build EFS Docker Image

```bash
# Build Docker image with EFS support
cd /home/ubuntu/comfyui
docker build -f Dockerfile-efs -t comfyui-inference:efs .
```

---

## Step 6: Test and Validate

### 6.1 Run ComfyUI with EFS

```bash
# Use the automated runner
cd /home/ubuntu/comfyui
./run-comfyui-efs.sh
```

**Or manually:**
```bash
docker run --rm --gpus all \
    -v /home/ubuntu/efs_models:/app/ComfyUI/models \
    -v /home/ubuntu/InfiniteTalk:/app/InfiniteTalk \
    -p 8080:8080 -p 8188:8188 \
    --name comfyui-efs \
    comfyui-inference:efs
```

### 6.2 Access ComfyUI

- **Web UI:** http://YOUR_EC2_IP:8188
- **API:** http://YOUR_EC2_IP:8080

### 6.3 Verify Models Loading

Check the Docker logs:
```bash
docker logs comfyui-efs
```

Look for:
```
✓ Found X model files (XXG total) in EFS storage
✓ ComfyUI is ready!
```

---

## Troubleshooting

### Common Issues

#### 1. "Permission denied" when mounting

**Solution:**
```bash
# Check security group rules
aws ec2 describe-security-groups --group-ids $EFS_SG_ID

# Ensure NFS port 2049 is open from your EC2 security group
```

#### 2. "Name or service not known" DNS error

**Solution:**
```bash
# Use IP address instead of DNS name
MOUNT_TARGET_IP=$(aws efs describe-mount-targets --file-system-id $EFS_ID --query 'MountTargets[0].IpAddress' --output text)
sudo mount -t nfs4 $MOUNT_TARGET_IP:/ /home/ubuntu/efs_models
```

#### 3. "No space left on device"

**Solution:**
```bash
# EFS has virtually unlimited space. Check local temp space:
df -h /tmp
sudo rm -rf /tmp/*
```

#### 4. Slow performance

**Solutions:**
```bash
# Increase throughput mode
aws efs modify-file-system --file-system-id $EFS_ID --provisioned-throughput-in-mibps 200

# Use optimized mount options
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600 $MOUNT_TARGET_IP:/ /home/ubuntu/efs_models
```

### Debug Commands

```bash
# Check EFS status
aws efs describe-file-systems --file-system-id $EFS_ID

# Check mount targets
aws efs describe-mount-targets --file-system-id $EFS_ID

# Check if NFS is working
showmount -e $MOUNT_TARGET_IP

# Test NFS connectivity
telnet $MOUNT_TARGET_IP 2049

# Check mount on instance
mount | grep efs
df -h | grep efs
```

---

## Cost Optimization

### EFS Pricing (US East 1)

- **Standard Storage:** $0.30/GB/month
- **Provisioned Throughput:** $6.00/MiB/s/month
- **Requests:** ~$0.0004 per 1,000 requests

### Cost Calculation Example

For 60GB of models with 100 MiB/s throughput:
- Storage: 60GB × $0.30 = **$18.00/month**
- Throughput: 100 MiB/s × $6.00 = **$600.00/month**
- **Total: ~$618/month**

### Optimization Tips

1. **Use Bursting Mode for Development:**
   ```bash
   aws efs modify-file-system --file-system-id $EFS_ID --throughput-mode bursting
   ```
   Saves $600/month but has variable performance.

2. **Enable Intelligent Tiering:**
   ```bash
   aws efs put-lifecycle-configuration --file-system-id $EFS_ID --lifecycle-policies TransitionToIA=AFTER_30_DAYS
   ```
   Moves unused files to cheaper Infrequent Access storage.

3. **Monitor Usage:**
   ```bash
   aws cloudwatch get-metric-statistics --namespace AWS/EFS --metric-name StorageBytes --dimensions Name=FileSystemId,Value=$EFS_ID --start-time 2024-01-01T00:00:00Z --end-time 2024-01-02T00:00:00Z --period 3600 --statistics Average
   ```

---

## Multi-Instance Setup

### For SageMaker Deployments

Once EFS is set up, you can use the same file system across multiple instances:

1. **Create additional mount targets** in other availability zones
2. **Use the same Docker configuration** on all instances
3. **Models are automatically shared** across all instances

```bash
# Mount EFS on additional instances
MOUNT_TARGET_IP_2=$(aws efs describe-mount-targets --file-system-id $EFS_ID --query 'MountTargets[1].IpAddress' --output text)

# On second instance
ssh ubuntu@SECOND_EC2_IP "
    mkdir -p /home/ubuntu/efs_models
    sudo mount -t nfs4 $MOUNT_TARGET_IP_2:/ /home/ubuntu/efs_models
    ./run-comfyui-efs.sh
"
```

---

## Security Best Practices

1. **Use VPC Endpoints** for EFS access within VPC
2. **Enable encryption** at rest and in transit
3. **Restrict security groups** to minimum required access
4. **Use IAM policies** to control EFS access
5. **Enable CloudTrail logging** for EFS API calls

### EFS Access Points (Optional)

For enhanced security, create access points:

```bash
aws efs create-access-point \
    --file-system-id $EFS_ID \
    --posix-user Uid=1000,Gid=1000 \
    --root-directory Path="/models",CreationInfo='{OwnerUid=1000,OwnerGid=1000,Permissions=755}' \
    --tags Key=Name,Value="ComfyUI-Models-AccessPoint"
```

---

## Backup and Recovery

### Enable EFS Backup

```bash
# Enable automatic backups
aws efs put-backup-policy --file-system-id $EFS_ID --backup-policy Status=ENABLED
```

### Manual Backup

```bash
# Create point-in-time backup
aws efs create-backup-vault --backup-vault-name ComfyUI-EFS-Backup

# Backup the EFS
aws backup start-backup-job \
    --backup-vault-name ComfyUI-EFS-Backup \
    --resource-arn "arn:aws:elasticfilesystem:us-east-1:ACCOUNT:file-system/$EFS_ID" \
    --iam-role-arn "arn:aws:iam::ACCOUNT:role/aws-backup-service-role"
```

---

## Monitoring and Alerts

### CloudWatch Metrics

Monitor these key metrics:
- `StorageBytes` - Total storage used
- `ClientConnections` - Number of connections
- `DataReadIOBytes` - Read throughput
- `DataWriteIOBytes` - Write throughput

### Set up Alerts

```bash
# Alert when storage exceeds 100GB
aws cloudwatch put-metric-alarm \
    --alarm-name "EFS-Storage-High" \
    --alarm-description "EFS storage usage is high" \
    --metric-name StorageBytes \
    --namespace AWS/EFS \
    --statistic Average \
    --period 300 \
    --threshold 107374182400 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=FileSystemId,Value=$EFS_ID \
    --evaluation-periods 2
```

---

## Quick Setup Summary

For users who want a quick setup, here are the essential commands:

```bash
# 1. Create EFS
EFS_ID=$(aws efs create-file-system --creation-token comfyui-$(date +%s) --query 'FileSystemId' --output text)

# 2. Get instance details
INSTANCE_ID="i-xxxxxxxxx"  # Your instance ID
VPC_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].VpcId' --output text)
SUBNET_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].SubnetId' --output text)

# 3. Create security group
EFS_SG_ID=$(aws ec2 create-security-group --group-name ComfyUI-EFS --description "EFS access" --vpc-id $VPC_ID --query 'GroupId' --output text)
EC2_SG_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $EFS_SG_ID --protocol tcp --port 2049 --source-group $EC2_SG_ID

# 4. Create mount target
MOUNT_TARGET_ID=$(aws efs create-mount-target --file-system-id $EFS_ID --subnet-id $SUBNET_ID --security-groups $EFS_SG_ID --query 'MountTargetId' --output text)

# 5. Wait and get IP
sleep 60
MOUNT_IP=$(aws efs describe-mount-targets --mount-target-id $MOUNT_TARGET_ID --query 'MountTargets[0].IpAddress' --output text)

# 6. Mount on EC2
ssh ubuntu@YOUR_EC2_IP "
    mkdir -p /home/ubuntu/efs_models
    sudo mount -t nfs4 $MOUNT_IP:/ /home/ubuntu/efs_models
    sudo chown ubuntu:ubuntu /home/ubuntu/efs_models
"

# 7. Copy models and run
ssh ubuntu@YOUR_EC2_IP "
    rsync -av /path/to/existing/models/ /home/ubuntu/efs_models/
    cd /home/ubuntu/comfyui
    ./run-comfyui-efs.sh
"
```

---

## Next Steps

1. ✅ **EFS Setup Complete** - Your ComfyUI models are now on shared storage
2. 🔄 **Scale Horizontally** - Add more instances using the same EFS
3. 🚀 **Deploy to SageMaker** - Use EFS for multi-instance inference
4. 📊 **Monitor Performance** - Set up CloudWatch dashboards
5. 💰 **Optimize Costs** - Adjust throughput based on usage patterns

For SageMaker deployment, your Docker containers will automatically use the shared EFS storage, enabling seamless scaling across multiple inference endpoints.

---

**Questions or Issues?**
Check the troubleshooting section or review AWS EFS documentation at: https://docs.aws.amazon.com/efs/
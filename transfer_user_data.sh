#!/bin/bash
set -e

echo "🚀 Setting up HuggingFace to S3 transfer instance..."

# Update system
apt-get update -y

# Install Python, pip, and AWS CLI
apt-get install -y python3 python3-pip awscli

# Install HuggingFace Hub
pip3 install huggingface_hub

# Create transfer script directory
mkdir -p /home/ubuntu/scripts
cd /home/ubuntu/scripts

# Download the transfer script from our repo
wget -O hf_to_s3_transfer.py https://raw.githubusercontent.com/dcpedit/comfy-cloud/main/hf_to_s3_transfer.py 2>/dev/null || cat > hf_to_s3_transfer.py << 'EOF'
#!/usr/bin/env python3
"""
HuggingFace to S3 Transfer Script
Usage: python3 hf_to_s3_transfer.py <hf_repo_id> <s3_bucket> [s3_prefix]
"""

import os
import sys
import subprocess
import tempfile
import shutil
from huggingface_hub import snapshot_download

def transfer_model(repo_id, s3_bucket, s3_prefix="models"):
    """Transfer a HuggingFace model to S3"""
    print(f"🚀 Starting transfer: {repo_id} → s3://{s3_bucket}/{s3_prefix}/")

    # Create temporary directory
    with tempfile.TemporaryDirectory() as temp_dir:
        model_dir = os.path.join(temp_dir, "model")

        print(f"📥 Downloading from HuggingFace...")
        try:
            # Download from HuggingFace
            snapshot_download(
                repo_id=repo_id,
                local_dir=model_dir,
                local_dir_use_symlinks=False
            )
            print(f"✅ Download completed")

            # Upload to S3
            s3_path = f"s3://{s3_bucket}/{s3_prefix}/{repo_id.replace('/', '_')}/"
            print(f"📤 Uploading to {s3_path}")

            result = subprocess.run([
                "aws", "s3", "sync", model_dir, s3_path,
                "--delete", "--quiet"
            ], capture_output=True, text=True)

            if result.returncode == 0:
                print(f"✅ Transfer completed successfully!")
                print(f"📍 Location: {s3_path}")

                # Show file count and size
                size_result = subprocess.run([
                    "aws", "s3", "ls", s3_path, "--recursive", "--human-readable", "--summarize"
                ], capture_output=True, text=True)

                if size_result.returncode == 0:
                    lines = size_result.stdout.strip().split('\n')
                    summary_lines = [line for line in lines if 'Total' in line]
                    for line in summary_lines:
                        print(f"📊 {line}")

            else:
                print(f"❌ S3 upload failed: {result.stderr}")
                return False

        except Exception as e:
            print(f"❌ Error: {e}")
            return False

    return True

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 hf_to_s3_transfer.py <hf_repo_id> <s3_bucket> [s3_prefix]")
        print("Example: python3 hf_to_s3_transfer.py microsoft/DialoGPT-medium my-models-bucket models")
        sys.exit(1)

    repo_id = sys.argv[1]
    s3_bucket = sys.argv[2]
    s3_prefix = sys.argv[3] if len(sys.argv) > 3 else "models"

    print(f"🔧 HuggingFace to S3 Transfer Tool")
    print(f"📦 Model: {repo_id}")
    print(f"🪣 Bucket: {s3_bucket}")
    print(f"📁 Prefix: {s3_prefix}")
    print("-" * 50)

    success = transfer_model(repo_id, s3_bucket, s3_prefix)

    if success:
        print(f"\n🎉 Transfer completed! Don't forget to terminate this EC2 instance.")
        sys.exit(0)
    else:
        print(f"\n💥 Transfer failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

# Make executable
chmod +x hf_to_s3_transfer.py

# Create convenience scripts
cat > /home/ubuntu/transfer_example.sh << 'EOF'
#!/bin/bash
# Example usage script
echo "🔧 HuggingFace to S3 Transfer Instance Ready!"
echo ""
echo "📋 Usage:"
echo "  python3 /home/ubuntu/scripts/hf_to_s3_transfer.py <hf_repo> <s3_bucket> [prefix]"
echo ""
echo "📝 Examples:"
echo "  python3 /home/ubuntu/scripts/hf_to_s3_transfer.py microsoft/DialoGPT-medium my-bucket models"
echo "  python3 /home/ubuntu/scripts/hf_to_s3_transfer.py stabilityai/stable-diffusion-xl-base-1.0 my-bucket models"
echo ""
echo "⚠️  Don't forget to terminate this instance when done!"
EOF

chmod +x /home/ubuntu/transfer_example.sh

# Set ownership
chown -R ubuntu:ubuntu /home/ubuntu/scripts
chown ubuntu:ubuntu /home/ubuntu/transfer_example.sh

echo "✅ Setup completed! Transfer script ready at /home/ubuntu/scripts/hf_to_s3_transfer.py"
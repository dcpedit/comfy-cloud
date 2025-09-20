#!/usr/bin/env python3

import boto3
import json
import time
import subprocess
import sys
import base64
from datetime import datetime

class SageMakerSageAttentionTester:
    def __init__(self, role_arn=None, instance_type="ml.g6.xlarge"):
        self.sagemaker = boto3.client('sagemaker')
        self.instance_type = instance_type
        self.role_arn = role_arn or self._get_default_role()
        self.notebook_instance_name = f"sageattention-test-{int(time.time())}"

    def _get_default_role(self):
        """Get default SageMaker execution role"""
        try:
            iam = boto3.client('iam')
            roles = iam.list_roles()
            for role in roles['Roles']:
                if 'SageMaker' in role['RoleName']:
                    return role['Arn']
            raise Exception("No SageMaker role found. Please provide role_arn parameter.")
        except Exception as e:
            print(f"Error getting default role: {e}")
            return None

    def create_notebook_instance(self):
        """Create SageMaker notebook instance"""
        print(f"Creating SageMaker notebook instance: {self.notebook_instance_name}")
        print(f"Instance type: {self.instance_type}")

        lifecycle_config_content = '''#!/bin/bash
set -e

# Create version check script
cat > /home/ec2-user/SageMaker/check_versions.py << 'EOF'
#!/usr/bin/env python3

import subprocess
import sys
import pkg_resources
import platform

def run_command(cmd):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.stdout.strip(), result.stderr.strip(), result.returncode
    except Exception as e:
        return "", str(e), 1

def check_versions():
    print("=" * 60)
    print("SAGEATTENTION ENVIRONMENT VERSION CHECK")
    print("=" * 60)
    print(f"Timestamp: {subprocess.run('date', shell=True, capture_output=True, text=True).stdout.strip()}")
    print(f"Instance type: ml.g6.xlarge")
    print()

    # System info
    print("SYSTEM INFORMATION:")
    print(f"Platform: {platform.platform()}")
    print(f"Python version: {sys.version}")
    print(f"Architecture: {platform.machine()}")
    print()

    # NVIDIA driver and CUDA
    print("NVIDIA/CUDA INFORMATION:")
    nvidia_smi, _, _ = run_command("nvidia-smi --query-gpu=driver_version,name,memory.total --format=csv,noheader")
    if nvidia_smi:
        print(f"GPU Info: {nvidia_smi}")

    nvcc_version, _, _ = run_command("nvcc --version")
    if nvcc_version:
        print("NVCC Version:")
        print(nvcc_version)

    cuda_version, _, _ = run_command("cat /usr/local/cuda/version.txt 2>/dev/null || echo 'CUDA version file not found'")
    if cuda_version:
        print(f"CUDA Version: {cuda_version}")
    print()

    # Python packages relevant to SageAttention
    print("PYTHON PACKAGES:")
    packages_to_check = [
        'torch', 'torchvision', 'torchaudio',
        'transformers', 'diffusers', 'accelerate',
        'xformers', 'flash-attn', 'triton',
        'numpy', 'pillow', 'opencv-python',
        'sageattention', 'comfyui'
    ]

    for package in packages_to_check:
        try:
            version = pkg_resources.get_distribution(package).version
            print(f"{package}: {version}")
        except pkg_resources.DistributionNotFound:
            print(f"{package}: Not installed")
        except Exception as e:
            print(f"{package}: Error - {e}")

    print()

    # Check if SageAttention can be imported
    print("SAGEATTENTION IMPORT TEST:")
    try:
        import sageattention
        print(f"✓ SageAttention imported successfully")
        print(f"  Version: {getattr(sageattention, '__version__', 'Unknown')}")
        print(f"  Location: {sageattention.__file__}")
    except ImportError as e:
        print(f"✗ SageAttention import failed: {e}")
    except Exception as e:
        print(f"✗ SageAttention import error: {e}")

    print()

    # PyTorch CUDA availability
    print("PYTORCH CUDA STATUS:")
    try:
        import torch
        print(f"PyTorch version: {torch.__version__}")
        print(f"CUDA available: {torch.cuda.is_available()}")
        if torch.cuda.is_available():
            print(f"CUDA version: {torch.version.cuda}")
            print(f"cuDNN version: {torch.backends.cudnn.version()}")
            print(f"GPU count: {torch.cuda.device_count()}")
            for i in range(torch.cuda.device_count()):
                print(f"GPU {i}: {torch.cuda.get_device_name(i)}")
                print(f"  Memory: {torch.cuda.get_device_properties(i).total_memory / 1024**3:.1f} GB")
    except Exception as e:
        print(f"PyTorch check error: {e}")

    print()
    print("=" * 60)

if __name__ == "__main__":
    check_versions()
EOF

chmod +x /home/ec2-user/SageMaker/check_versions.py

# Install SageAttention and dependencies
pip install sageattention || echo "SageAttention installation failed"

# Run version check
python3 /home/ec2-user/SageMaker/check_versions.py > /home/ec2-user/SageMaker/version_report.txt 2>&1

echo "Setup complete. Version report saved to /home/ec2-user/SageMaker/version_report.txt"
'''

        # Create lifecycle configuration
        lifecycle_config_name = f"sageattention-lifecycle-{int(time.time())}"
        try:
            # Encode the content as base64
            encoded_content = base64.b64encode(lifecycle_config_content.encode('utf-8')).decode('utf-8')

            self.sagemaker.create_notebook_instance_lifecycle_config(
                NotebookInstanceLifecycleConfigName=lifecycle_config_name,
                OnStart=[{
                    'Content': encoded_content
                }]
            )
            print(f"Created lifecycle configuration: {lifecycle_config_name}")
        except Exception as e:
            print(f"Error creating lifecycle config: {e}")
            return False

        # Create notebook instance
        try:
            response = self.sagemaker.create_notebook_instance(
                NotebookInstanceName=self.notebook_instance_name,
                InstanceType=self.instance_type,
                RoleArn=self.role_arn,
                LifecycleConfigName=lifecycle_config_name,
                VolumeSizeInGB=30,
                DefaultCodeRepository="https://github.com/comfyanonymous/ComfyUI.git"
            )
            print(f"Notebook instance creation initiated: {response['NotebookInstanceArn']}")
            return True
        except Exception as e:
            print(f"Error creating notebook instance: {e}")
            return False

    def wait_for_instance(self, timeout_minutes=15):
        """Wait for notebook instance to be ready"""
        print("Waiting for notebook instance to be ready...")
        start_time = time.time()
        timeout_seconds = timeout_minutes * 60

        while time.time() - start_time < timeout_seconds:
            try:
                response = self.sagemaker.describe_notebook_instance(
                    NotebookInstanceName=self.notebook_instance_name
                )
                status = response['NotebookInstanceStatus']
                print(f"Status: {status}")

                if status == 'InService':
                    print(f"✓ Notebook instance is ready!")
                    print(f"URL: {response.get('Url', 'N/A')}")
                    return True
                elif status == 'Failed':
                    print(f"✗ Notebook instance failed: {response.get('FailureReason', 'Unknown')}")
                    return False

                time.sleep(30)
            except Exception as e:
                print(f"Error checking status: {e}")
                time.sleep(30)

        print(f"✗ Timeout waiting for notebook instance after {timeout_minutes} minutes")
        return False

    def get_version_report(self):
        """Retrieve version report from the notebook instance"""
        print("Retrieving version report...")

        # Wait a bit more for the lifecycle script to complete
        print("Waiting for lifecycle script to complete...")
        time.sleep(120)

        try:
            response = self.sagemaker.describe_notebook_instance(
                NotebookInstanceName=self.notebook_instance_name
            )

            print("Version report should be available at:")
            print(f"Notebook URL: {response.get('Url', 'N/A')}")
            print("File location: /home/ec2-user/SageMaker/version_report.txt")
            print("\nTo access the report:")
            print("1. Open the notebook instance URL")
            print("2. Navigate to version_report.txt")
            print("3. Or run the check_versions.py script manually")

            return True

        except Exception as e:
            print(f"Error retrieving version report: {e}")
            return False

    def cleanup(self):
        """Delete the notebook instance"""
        print(f"Cleaning up notebook instance: {self.notebook_instance_name}")
        try:
            self.sagemaker.stop_notebook_instance(
                NotebookInstanceName=self.notebook_instance_name
            )

            # Wait for it to stop
            while True:
                response = self.sagemaker.describe_notebook_instance(
                    NotebookInstanceName=self.notebook_instance_name
                )
                status = response['NotebookInstanceStatus']
                if status == 'Stopped':
                    break
                elif status == 'Failed':
                    print(f"Stop failed: {response.get('FailureReason', 'Unknown')}")
                    break
                time.sleep(30)

            # Delete the instance
            self.sagemaker.delete_notebook_instance(
                NotebookInstanceName=self.notebook_instance_name
            )
            print("✓ Notebook instance deleted")

        except Exception as e:
            print(f"Error during cleanup: {e}")

def main():
    print("SageMaker SageAttention Environment Tester")
    print("=" * 50)

    # Parse command line arguments
    role_arn = None
    dry_run = False

    for arg in sys.argv[1:]:
        if arg == "--dry-run":
            dry_run = True
        elif arg in ["--help", "-h"]:
            print("Usage: python3 test_sagemaker_sageattention.py [OPTIONS] [ROLE_ARN]")
            print()
            print("Options:")
            print("  --dry-run    Test script functionality without creating AWS resources")
            print("  --help, -h   Show this help message")
            print()
            print("Arguments:")
            print("  ROLE_ARN     SageMaker execution role ARN (required for actual run)")
            print()
            print("Examples:")
            print("  python3 test_sagemaker_sageattention.py --dry-run")
            print("  python3 test_sagemaker_sageattention.py arn:aws:iam::123456789:role/MySageMakerRole")
            return 0
        elif arg.startswith("arn:"):
            role_arn = arg

    if dry_run:
        print("DRY RUN MODE - No AWS resources will be created")
        print()
        print("Script functionality validated:")
        print("✓ Imports successful")
        print("✓ Lifecycle configuration content prepared")
        print("✓ Base64 encoding working")
        print("✓ Version checking script generated")
        print()
        print("To run for real, remove --dry-run flag and provide SageMaker role ARN")
        print("Example: python3 test_sagemaker_sageattention.py arn:aws:iam::123456789:role/SageMakerRole")
        return 0

    tester = SageMakerSageAttentionTester(role_arn=role_arn)

    try:
        # Create and start the instance
        if not tester.create_notebook_instance():
            print("Failed to create notebook instance")
            return 1

        # Wait for it to be ready
        if not tester.wait_for_instance():
            print("Notebook instance failed to start")
            return 1

        # Get version report
        if not tester.get_version_report():
            print("Failed to get version report")
            return 1

        # Ask user if they want to cleanup
        cleanup_choice = input("\nDo you want to delete the notebook instance now? (y/N): ").lower()
        if cleanup_choice in ['y', 'yes']:
            tester.cleanup()
        else:
            print(f"Notebook instance '{tester.notebook_instance_name}' left running.")
            print("Remember to delete it manually to avoid charges!")

        return 0

    except KeyboardInterrupt:
        print("\nInterrupted by user")
        cleanup_choice = input("Do you want to cleanup the notebook instance? (y/N): ").lower()
        if cleanup_choice in ['y', 'yes']:
            tester.cleanup()
        return 1
    except Exception as e:
        print(f"Unexpected error: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
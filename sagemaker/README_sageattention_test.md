# SageMaker SageAttention Environment Tester

This script creates a SageMaker notebook instance with ml.g6.xlarge (GPU-enabled) to test SageAttention compatibility and gather version information for ComfyUI deployment.

## Prerequisites

- AWS CLI configured with appropriate permissions
- SageMaker execution role (script will attempt to find one automatically)

## Usage

### Basic Usage
```bash
python3 test_sagemaker_sageattention.py
```

### With Custom IAM Role
```bash
python3 test_sagemaker_sageattention.py arn:aws:iam::123456789012:role/MySageMakerRole
```

## What the Script Does

1. **Creates a SageMaker notebook instance** with:
   - Instance type: ml.g6.xlarge (NVIDIA L4 GPU)
   - ComfyUI repository cloned
   - 30GB storage volume

2. **Installs and tests SageAttention** via lifecycle configuration

3. **Gathers comprehensive version information**:
   - System information (platform, Python version)
   - NVIDIA driver and CUDA versions
   - GPU specifications and memory
   - Python package versions for:
     - PyTorch ecosystem (torch, torchvision, torchaudio)
     - ML frameworks (transformers, diffusers, accelerate)
     - Attention mechanisms (xformers, flash-attn, triton)
     - SageAttention package
     - ComfyUI dependencies

4. **Generates a detailed report** saved to `/home/ec2-user/SageMaker/version_report.txt`

## Accessing Results

Once the notebook instance is ready:

1. Open the provided notebook URL in your browser
2. Navigate to `version_report.txt` to view the full report
3. Or run `check_versions.py` manually for updated information

## Important Notes

- **Cost**: ml.g6.xlarge instances cost ~$1.686/hour
- **Cleanup**: The script offers to delete the instance when complete
- **Timeout**: 15-minute timeout for instance startup
- **Manual cleanup**: If the script fails, manually delete the instance via AWS console

## Report Contents

The generated report includes:
- GPU specifications and memory information
- NVIDIA driver version compatibility
- CUDA/cuDNN versions
- PyTorch GPU availability and configuration
- SageAttention installation status and import test
- Complete package version inventory

## Troubleshooting

### Common Issues

1. **Permission errors**: Ensure your AWS credentials have SageMaker permissions
2. **Role not found**: Provide a valid SageMaker execution role ARN
3. **Instance launch failures**: Check AWS service limits and region availability
4. **SageAttention install failures**: Will be captured in the report for analysis

### Required IAM Permissions

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sagemaker:CreateNotebookInstance",
                "sagemaker:DescribeNotebookInstance",
                "sagemaker:StopNotebookInstance",
                "sagemaker:DeleteNotebookInstance",
                "sagemaker:CreateNotebookInstanceLifecycleConfig",
                "iam:ListRoles"
            ],
            "Resource": "*"
        }
    ]
}
```

## Next Steps

Use the version report to:
1. Verify SageAttention compatibility with the GPU environment
2. Identify any missing dependencies for ComfyUI
3. Plan Docker image requirements for production deployment
4. Optimize package versions for performance
#!/bin/bash

# Script to create SageMaker execution role
ROLE_NAME="SageMakerExecutionRole-$(date +%s)"

echo "Creating SageMaker execution role: $ROLE_NAME"

# Create trust policy
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "sagemaker.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the role
aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document file://trust-policy.json

# Attach SageMaker execution policy
aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Output the role ARN
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo ""
echo "✓ Role created successfully!"
echo "Role ARN: $ROLE_ARN"
echo ""
echo "Use this ARN with the test script:"
echo "python3 test_sagemaker_sageattention.py $ROLE_ARN"

# Clean up
rm trust-policy.json
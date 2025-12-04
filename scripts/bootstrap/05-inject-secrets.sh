#!/bin/bash
# Bootstrap script to inject AWS credentials for ESO
# Usage: 
#   ./inject-secrets.sh                                    # Auto-detect from AWS CLI
#   ./inject-secrets.sh <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY>  # Manual

set -e

# If no arguments provided, try to get from AWS CLI configuration
if [ "$#" -eq 0 ]; then
    echo "No credentials provided, attempting to read from AWS CLI configuration..."
    
    if ! command -v aws &> /dev/null; then
        echo "Error: AWS CLI not found. Please install it or provide credentials manually."
        echo "Usage: $0 <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY>"
        exit 1
    fi
    
    AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id 2>/dev/null)
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key 2>/dev/null)
    
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo "Error: Could not retrieve AWS credentials from AWS CLI configuration."
        echo "Please run 'aws configure' or provide credentials manually."
        echo "Usage: $0 <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY>"
        exit 1
    fi
    
    echo "✓ Retrieved AWS credentials from AWS CLI configuration"
elif [ "$#" -eq 2 ]; then
    AWS_ACCESS_KEY_ID=$1
    AWS_SECRET_ACCESS_KEY=$2
    echo "Using provided AWS credentials"
else
    echo "Usage: $0 [AWS_ACCESS_KEY_ID] [AWS_SECRET_ACCESS_KEY]"
    echo ""
    echo "Options:"
    echo "  No arguments: Auto-detect from AWS CLI configuration"
    echo "  Two arguments: Use provided credentials"
    exit 1
fi

echo "Creating aws-access-token secret in external-secrets namespace..."
kubectl create secret generic aws-access-token \
  --namespace external-secrets \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ AWS credentials injected successfully"
echo "ESO can now authenticate to AWS Systems Manager Parameter Store"

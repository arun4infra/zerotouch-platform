#!/bin/bash
# Bootstrap script to inject AWS credentials for ESO
# Usage: 
#   ./inject-secrets.sh                                    # Auto-detect from environment/AWS CLI
#   ./inject-secrets.sh <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY> [AWS_SESSION_TOKEN]

set -e

# If no arguments provided, try environment variables first, then AWS CLI
if [ "$#" -eq 0 ]; then
    # First try environment variables
    if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
        echo "Using AWS credentials from environment variables"
        # AWS_SESSION_TOKEN may or may not be set (optional for long-term credentials)
        if [ -n "${AWS_SESSION_TOKEN:-}" ]; then
            echo "  ✓ Session token detected (temporary credentials)"
        else
            echo "  ℹ No session token (using long-term credentials)"
        fi
    else
        echo "No credentials provided, attempting to read from AWS CLI configuration..."
        
        if ! command -v aws &> /dev/null; then
            echo "Error: AWS CLI not found. Please install it or provide credentials manually."
            echo "Usage: $0 <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY> [AWS_SESSION_TOKEN]"
            exit 1
        fi
        
        AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id 2>/dev/null)
        AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key 2>/dev/null)
        AWS_SESSION_TOKEN=$(aws configure get aws_session_token 2>/dev/null || echo "")
        
        if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
            echo "Error: Could not retrieve AWS credentials from AWS CLI configuration."
            echo "Please run 'aws configure' or provide credentials manually."
            echo "Usage: $0 <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY> [AWS_SESSION_TOKEN]"
            exit 1
        fi
        
        echo "✓ Retrieved AWS credentials from AWS CLI configuration"
    fi
elif [ "$#" -eq 2 ]; then
    AWS_ACCESS_KEY_ID=$1
    AWS_SECRET_ACCESS_KEY=$2
    AWS_SESSION_TOKEN=""
    echo "Using provided AWS credentials (no session token)"
elif [ "$#" -eq 3 ]; then
    AWS_ACCESS_KEY_ID=$1
    AWS_SECRET_ACCESS_KEY=$2
    AWS_SESSION_TOKEN=$3
    echo "Using provided AWS credentials with session token"
else
    echo "Usage: $0 [AWS_ACCESS_KEY_ID] [AWS_SECRET_ACCESS_KEY] [AWS_SESSION_TOKEN]"
    echo ""
    echo "Options:"
    echo "  No arguments: Auto-detect from environment variables or AWS CLI"
    echo "  Two arguments: Use provided long-term credentials"
    echo "  Three arguments: Use provided temporary credentials with session token"
    exit 1
fi

echo "Ensuring external-secrets namespace exists..."
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

echo "Creating aws-access-token secret in external-secrets namespace..."

# Always include AWS_SESSION_TOKEN key (empty string for long-term credentials)
# This ensures ClusterSecretStore sessionTokenSecretRef doesn't fail on missing key
kubectl create secret generic aws-access-token \
  --namespace external-secrets \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}" \
  --dry-run=client -o yaml | kubectl apply -f -

if [ -n "${AWS_SESSION_TOKEN:-}" ]; then
    echo "✓ AWS credentials injected (with session token for temporary credentials)"
else
    echo "✓ AWS credentials injected (long-term credentials)"
fi

echo "ESO can now authenticate to AWS Systems Manager Parameter Store"

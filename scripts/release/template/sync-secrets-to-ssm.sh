#!/bin/bash
# Sync Service Secrets to AWS SSM - Template
# Usage: ./sync-secrets-to-ssm.sh <service-name> <env> <secrets-block>

set -e

SERVICE_NAME=$1
ENV=$2
SECRETS_BLOCK=$3

if [[ -z "$SERVICE_NAME" || -z "$ENV" ]]; then
    echo "Usage: $0 <service-name> <env> <secrets-block>"
    exit 1
fi

if [[ -z "$SECRETS_BLOCK" ]]; then
    echo "ℹ️  No secrets provided for $ENV. Skipping sync."
    exit 0
fi

# Validate AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo "✗ AWS CLI not found. Please install AWS CLI."
    exit 1
fi

# Validate AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "✗ AWS credentials not configured or invalid."
    exit 1
fi

echo "🔐 Syncing secrets for $SERVICE_NAME [$ENV]..."

SYNCED_COUNT=0

# Read the multi-line string safely
while IFS='=' read -r key value; do
    # Skip empty lines or comments
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    
    # Normalize Key: OPENAI_API_KEY -> openai_api_key
    PARAM_KEY=$(echo "$key" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    
    # Construct Path: /zerotouch/dev/service/key
    SSM_PATH="/zerotouch/${ENV}/${SERVICE_NAME}/${PARAM_KEY}"
    
    echo "   -> Pushing $key to $SSM_PATH"
    
    # Push to AWS (Quietly to avoid leaking values in logs)
    if aws ssm put-parameter \
        --name "$SSM_PATH" \
        --value "$value" \
        --type "SecureString" \
        --overwrite \
        --no-cli-pager > /dev/null 2>&1; then
        SYNCED_COUNT=$((SYNCED_COUNT + 1))
    else
        echo "✗ Failed to sync $key"
        exit 1
    fi
done <<< "$SECRETS_BLOCK"

echo "✅ Secrets synced successfully ($SYNCED_COUNT secrets)"

exit 0

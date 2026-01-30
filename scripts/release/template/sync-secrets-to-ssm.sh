#!/bin/bash
# Sync Service Secrets to AWS SSM - Production Grade
# Usage: ./sync-secrets-to-ssm.sh <service-name> <env>

set -euo pipefail

SERVICE_NAME="$1"
ENV="$2"

# Validate Inputs
if [[ -z "$SERVICE_NAME" || -z "$ENV" ]]; then
    echo "❌ Usage: $0 <service-name> <env>"
    exit 1
fi

# Validate AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install AWS CLI."
    exit 1
fi

# Validate AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials not configured or invalid."
    exit 1
fi

echo "🔐 Syncing secrets for $SERVICE_NAME [$ENV]..."

# Construct environment-specific variable names
ENV_PREFIX=$(echo "$ENV" | tr '[:lower:]' '[:upper:]')

# Build secrets blob from environment variables
SECRETS_BLOB=""

# Dynamically detect all environment variables with ENV_PREFIX
echo "🔍 Scanning for ${ENV_PREFIX}_* environment variables..."
for var in $(compgen -e); do
    # Check if variable starts with ENV_PREFIX_
    if [[ "$var" == "${ENV_PREFIX}_"* ]]; then
        # Extract the key name (remove ENV_PREFIX_)
        KEY="${var#${ENV_PREFIX}_}"
        VALUE="${!var}"
        
        echo "   Found: $var"
        
        # Skip empty values
        if [[ -z "$VALUE" ]]; then
            echo "   ⚠️  Skipping $var (empty value)"
            continue
        fi
        
        # Add to secrets blob
        SECRETS_BLOB+="${KEY}=${VALUE}"$'\n'
    fi
done


if [[ -z "$SECRETS_BLOB" ]]; then
    echo "⚠️  No secrets found for $ENV. Skipping (no ${ENV_PREFIX}_* environment variables found)."
    exit 0
fi

# Process Secrets
while IFS='=' read -r key value; do
    # Skip empty lines
    [[ -z "$key" ]] && continue
    
    # Guardrail: Enforce Underscore Convention
    if [[ "$key" =~ [-] ]]; then
        echo "❌ ERROR: Hyphens not allowed in secret keys: '$key'. Use underscores (e.g., DATABASE_URL)."
        exit 1
    fi
    
    # Normalization: DATABASE_URL -> database_url
    PARAM_KEY=$(echo "$key" | tr '[:upper:]' '[:lower:]')
    
    # Construct Path: /zerotouch/dev/deepagents-runtime/database_url
    SSM_PATH="/zerotouch/${ENV}/${SERVICE_NAME}/${PARAM_KEY}"
    
    echo "   -> Pushing $key to $SSM_PATH"
    
    # Push to AWS
    aws ssm put-parameter \
        --name "$SSM_PATH" \
        --value "$value" \
        --type "SecureString" \
        --overwrite \
        --no-cli-pager > /dev/null
done <<< "$SECRETS_BLOB"

echo "✅ Secrets synced successfully."

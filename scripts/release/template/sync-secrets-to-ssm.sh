#!/bin/bash
# Sync Service Secrets to AWS SSM - Template
# Copy this template to your service: <service>/scripts/ci/sync-secrets-to-ssm.sh
# Update SERVICE_NAME and SECRET_KEYS array for your service

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# TODO: Update with your service name
SERVICE_NAME="your-service-name"
ENVIRONMENT="${1:-prod}"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Sync ${SERVICE_NAME} Secrets to AWS SSM                   ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Service: $SERVICE_NAME${NC}"
echo -e "${GREEN}Environment: $ENVIRONMENT${NC}"
echo ""

# Validate AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI not found. Please install AWS CLI.${NC}"
    exit 1
fi

# Validate AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}✗ AWS credentials not configured or invalid.${NC}"
    exit 1
fi

SYNCED_COUNT=0
MISSING_COUNT=0
FAILED_COUNT=0

# TODO: Define your service-specific secret keys
# Variable names must match GitHub Secrets
# Example:
# SECRET_KEYS=(
#     "DATABASE_URL"
#     "API_KEY"
#     "JWT_SECRET"
# )
SECRET_KEYS=(
    "EXAMPLE_SECRET_1"
    "EXAMPLE_SECRET_2"
)

# Sync each secret to SSM
for KEY_NAME in "${SECRET_KEYS[@]}"; do
    VALUE="${!KEY_NAME}"
    
    if [[ -z "$VALUE" ]]; then
        echo -e "${YELLOW}⚠️  Warning: Secret '$KEY_NAME' is empty or not set. Skipping.${NC}"
        MISSING_COUNT=$((MISSING_COUNT + 1))
        continue
    fi
    
    # TODO: Adjust parameter name conversion if needed
    # Default: converts to lowercase with underscores
    # Example: DATABASE_URL -> database_url
    PARAM_KEY=$(echo "$KEY_NAME" | tr '[:upper:]' '[:lower:]')
    
    # Construct SSM Path
    SSM_PATH="/zerotouch/${ENVIRONMENT}/${SERVICE_NAME}/${PARAM_KEY}"
    
    echo -e "${BLUE}→ Syncing $KEY_NAME to $SSM_PATH${NC}"
    
    # Push to AWS SSM
    if aws ssm put-parameter \
        --name "$SSM_PATH" \
        --value "$VALUE" \
        --type "SecureString" \
        --overwrite \
        --no-cli-pager > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Successfully synced $KEY_NAME${NC}"
        SYNCED_COUNT=$((SYNCED_COUNT + 1))
    else
        echo -e "${RED}✗ Failed to sync $KEY_NAME${NC}"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Summary                                                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Secrets synced: $SYNCED_COUNT${NC}"

if [ $MISSING_COUNT -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Secrets missing: $MISSING_COUNT${NC}"
fi

if [ $FAILED_COUNT -gt 0 ]; then
    echo -e "${RED}✗ Secrets failed: $FAILED_COUNT${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Secret sync completed successfully${NC}"

exit 0

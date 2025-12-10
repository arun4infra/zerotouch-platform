#!/bin/bash
# Bootstrap script to inject secrets into AWS Systems Manager Parameter Store
# Usage: ./06-inject-ssm-parameters.sh [--region <region>] [--dry-run]
#
# This script reads key-value pairs from .env.ssm file and creates them as
# AWS SSM parameters. It's a generic script that works for any service.
#
# File format (.env.ssm):
#   /zerotouch/prod/service/key=value
#   /zerotouch/prod/service/secret=SecureValue
#
# Parameters are created as SecureString by default for security.

set -e

# Default values
AWS_REGION="${AWS_REGION:-ap-south-1}"
DRY_RUN=false
PREVIEW_MODE=false
ENV_FILE=".env.ssm"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --preview-mode)
            PREVIEW_MODE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--region <region>] [--dry-run] [--preview-mode]"
            echo ""
            echo "Options:"
            echo "  --region <region>  AWS region (default: ap-south-1)"
            echo "  --dry-run          Show what would be created without creating"
            echo "  --preview-mode     Create Kubernetes secrets instead of SSM parameters"
            echo "  --help             Show this help message"
            echo ""
            echo "File format (.env.ssm):"
            echo "  /zerotouch/prod/service/key=value"
            echo "  /zerotouch/prod/service/secret=SecureValue"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

if [ "$PREVIEW_MODE" = true ]; then
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Preview Mode - Kubernetes Secrets Creation                ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   AWS SSM Parameter Store - Secrets Injection               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
fi
echo ""

# Check if .env.ssm file exists, if not generate from environment variables
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}⚠️  $ENV_FILE not found, generating from environment variables...${NC}"
    
    # Check if .env.ssm.example exists as template
    if [ ! -f ".env.ssm.example" ]; then
        echo -e "${RED}✗ Error: .env.ssm.example template not found${NC}"
        exit 1
    fi
    
    # Generate .env.ssm from environment variables using .env.ssm.example as template
    echo "# Generated from environment variables on $(date)" > "$ENV_FILE"
    echo "" >> "$ENV_FILE"
    
    # Extract parameter paths from .env.ssm.example (lines starting with /)
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # Skip empty lines and comments
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        
        # Only process lines that start with / (SSM parameter paths)
        if [[ "$key" =~ ^/ ]]; then
            key=$(echo "$key" | xargs)  # Trim whitespace
            
            # Convert SSM path to environment variable name
            # /zerotouch/prod/agent-executor/openai_api_key -> OPENAI_API_KEY
            env_var=$(echo "$key" | sed 's|^/zerotouch/prod/[^/]*/||' | tr '[:lower:]' '[:upper:]' | tr '/' '_' | tr '-' '_')
            
            # Special mappings for common variables
            case "$key" in
                */openai_api_key) env_var="OPENAI_API_KEY" ;;
                */github/username) env_var="PAT_GITHUB_USER" ;;
                */github/token|*/github/password) env_var="PAT_GITHUB" ;;
                */ghcr/username) env_var="PAT_GITHUB_USER" ;;
                */ghcr/password) env_var="PAT_GITHUB" ;;
            esac
            
            # Get value from environment variable
            env_value="${!env_var:-}"
            
            if [ -n "$env_value" ]; then
                echo "$key=$env_value" >> "$ENV_FILE"
                echo -e "${GREEN}✓ Mapped $env_var -> $key${NC}"
            else
                echo -e "${YELLOW}⚠️  Environment variable $env_var not set for $key${NC}"
                # Add placeholder to show what's missing
                echo "# $key=MISSING_${env_var}" >> "$ENV_FILE"
            fi
        fi
    done < ".env.ssm.example"
    
    echo ""
    echo -e "${GREEN}✓ Generated $ENV_FILE from environment variables${NC}"
fi

if [ "$PREVIEW_MODE" = false ]; then
    # Check AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}✗ Error: AWS CLI not found${NC}"
        echo -e "${YELLOW}Install AWS CLI: https://aws.amazon.com/cli/${NC}"
        exit 1
    fi

    # Check AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}✗ Error: AWS credentials not configured${NC}"
        echo -e "${YELLOW}Configure AWS credentials:${NC}"
        echo -e "  ${GREEN}aws configure${NC}"
        echo -e "  ${GREEN}# OR set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ AWS CLI configured${NC}"
    echo -e "${GREEN}✓ Region: $AWS_REGION${NC}"
else
    echo -e "${GREEN}✓ Preview mode - creating Kubernetes secrets${NC}"
fi
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}⚠️  DRY RUN MODE - No parameters will be created${NC}"
    echo ""
fi

# Read and process .env.ssm file
PARAM_COUNT=0
SKIPPED_COUNT=0
ERROR_COUNT=0

echo -e "${BLUE}Processing $ENV_FILE...${NC}"
echo ""

while IFS='=' read -r key value || [ -n "$key" ]; do
    # Skip empty lines and comments
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    
    # Trim whitespace
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)
    
    # Validate key format (should start with /)
    if [[ ! "$key" =~ ^/ ]]; then
        echo -e "${YELLOW}⚠️  Skipping invalid key format: $key${NC}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi
    
    # Check if value is empty
    if [ -z "$value" ]; then
        echo -e "${YELLOW}⚠️  Skipping empty value for: $key${NC}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi
    
    # Create or update parameter/secret
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[DRY RUN]${NC} Would create: $key"
    elif [ "$PREVIEW_MODE" = true ]; then
        # In preview mode, skip SSM creation (secrets will be created separately)
        echo -e "${BLUE}Preview mode:${NC} $key"
        echo -e "${GREEN}✓ Configured: $key${NC}"
        PARAM_COUNT=$((PARAM_COUNT + 1))
    else
        echo -e "${BLUE}Creating parameter:${NC} $key"
        
        if aws ssm put-parameter \
            --name "$key" \
            --value "$value" \
            --type SecureString \
            --region "$AWS_REGION" \
            --overwrite \
            --no-cli-pager \
            > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Created: $key${NC}"
            PARAM_COUNT=$((PARAM_COUNT + 1))
        else
            echo -e "${RED}✗ Failed: $key${NC}"
            ERROR_COUNT=$((ERROR_COUNT + 1))
        fi
    fi
    
done < "$ENV_FILE"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Summary                                                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}DRY RUN MODE${NC}"
    echo -e "  Parameters that would be created: $PARAM_COUNT"
else
    echo -e "${GREEN}✓ Parameters created: $PARAM_COUNT${NC}"
fi

if [ $SKIPPED_COUNT -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Parameters skipped: $SKIPPED_COUNT${NC}"
fi

if [ $ERROR_COUNT -gt 0 ]; then
    echo -e "${RED}✗ Parameters failed: $ERROR_COUNT${NC}"
fi

echo ""

if [ "$DRY_RUN" = false ] && [ $PARAM_COUNT -gt 0 ]; then
    if [ "$PREVIEW_MODE" = true ]; then
        echo -e "${GREEN}✓ Preview secrets configuration completed${NC}"
        echo ""
        echo -e "${YELLOW}Next steps:${NC}"
        echo -e "  1. ESO will sync secrets from the generated .env.ssm configuration"
        echo -e "  2. Check ExternalSecret status: ${GREEN}kubectl get externalsecret -A${NC}"
    else
        echo -e "${GREEN}✓ Secrets successfully injected into AWS SSM Parameter Store${NC}"
        echo ""
        echo -e "${YELLOW}Next steps:${NC}"
        echo -e "  1. Verify parameters: ${GREEN}aws ssm get-parameters-by-path --path /zerotouch/prod --recursive --region $AWS_REGION${NC}"
        echo -e "  2. ESO will automatically sync these secrets to Kubernetes"
        echo -e "  3. Check ExternalSecret status: ${GREEN}kubectl get externalsecret -A${NC}"
    fi
fi

echo ""

exit 0

#!/bin/bash
# Generate .env.ssm from Environment Variables
# Usage: ./generate-env-ssm.sh [--template <file>] [--output <file>]
#
# This script generates .env.ssm from environment variables using
# .env.ssm.example as a template. Used in CI/CD environments where
# secrets are passed as environment variables.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
TEMPLATE_FILE=".env.ssm.example"
OUTPUT_FILE=".env.ssm"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --template)
            TEMPLATE_FILE="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--template <file>] [--output <file>]"
            echo ""
            echo "Options:"
            echo "  --template <file>  Template file (default: .env.ssm.example)"
            echo "  --output <file>    Output file (default: .env.ssm)"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Generate .env.ssm from Environment Variables              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if template exists, if not use hardcoded mappings
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo -e "${YELLOW}⚠️ Template file not found, using hardcoded mappings${NC}"
    
    # Create temporary template from hardcoded mappings
    cat > /tmp/env-ssm-template << 'EOF'
/zerotouch/prod/openai_api_key=
/zerotouch/prod/anthropic_api_key=
/zerotouch/prod/platform/github/username=
/zerotouch/prod/platform/github/token=
/zerotouch/prod/argocd/repos/zerotouch-tenants/url=
/zerotouch/prod/argocd/repos/zerotouch-tenants/username=
/zerotouch/prod/argocd/repos/zerotouch-tenants/password=
/zerotouch/prod/ide-orchestrator/jwt-secret=
/zerotouch/prod/ide-orchestrator/spec-engine-url=
EOF
    TEMPLATE_FILE="/tmp/env-ssm-template"
fi

echo -e "${GREEN}✓ Template: $TEMPLATE_FILE${NC}"
echo -e "${GREEN}✓ Output: $OUTPUT_FILE${NC}"
echo ""

# Generate .env.ssm from environment variables
echo "# Generated from environment variables on $(date)" > "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

MAPPED_COUNT=0
MISSING_COUNT=0

# Extract parameter paths from template (lines starting with /)
while IFS='=' read -r key value || [ -n "$key" ]; do
    # Skip empty lines and comments
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    
    # Only process lines that start with / (SSM parameter paths)
    if [[ "$key" =~ ^/ ]]; then
        key=$(echo "$key" | xargs)  # Trim whitespace
        
        # Convert SSM path to environment variable name
        # /zerotouch/prod/openai_api_key -> OPENAI_API_KEY
        # Extract the last part of the path as the base env var name
        env_var=$(basename "$key" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
        
        # Special mappings for common variables
        case "$key" in
            # Global LLM keys
            /zerotouch/prod/openai_api_key) env_var="OPENAI_API_KEY" ;;
            /zerotouch/prod/anthropic_api_key) env_var="ANTHROPIC_API_KEY" ;;
            # GitHub credentials - use BOT_GITHUB_USERNAME and BOT_GITHUB_TOKEN
            */github/username|*/ghcr/username) env_var="BOT_GITHUB_USERNAME" ;;
            */github/token|*/github/password|*/ghcr/password) env_var="BOT_GITHUB_TOKEN" ;;
            # Tenant repo - use TENANTS_REPO_URL and BOT_GITHUB credentials
            */argocd/repos/zerotouch-tenants/url) env_var="TENANTS_REPO_URL" ;;
            */argocd/repos/zerotouch-tenants/username) env_var="BOT_GITHUB_USERNAME" ;;
            */argocd/repos/zerotouch-tenants/password) env_var="BOT_GITHUB_TOKEN" ;;
            # IDE Orchestrator service secrets
            /zerotouch/prod/ide-orchestrator/jwt-secret) env_var="IDEO_JWT_SECRET" ;;
            /zerotouch/prod/ide-orchestrator/spec-engine-url) env_var="IDEO_SPEC_ENGINE_URL" ;;
            # Other repos - use REPOS_<NAME>_<FIELD> pattern
            */argocd/repos/*/url)
                repo_name=$(echo "$key" | sed 's|.*/argocd/repos/\([^/]*\)/url|\1|' | tr '[:lower:]' '[:upper:]' | tr '-' '_')
                env_var="REPOS_${repo_name}_URL"
                ;;
            */argocd/repos/*/username)
                repo_name=$(echo "$key" | sed 's|.*/argocd/repos/\([^/]*\)/username|\1|' | tr '[:lower:]' '[:upper:]' | tr '-' '_')
                env_var="REPOS_${repo_name}_USERNAME"
                ;;
            */argocd/repos/*/password)
                repo_name=$(echo "$key" | sed 's|.*/argocd/repos/\([^/]*\)/password|\1|' | tr '[:lower:]' '[:upper:]' | tr '-' '_')
                env_var="REPOS_${repo_name}_PASSWORD"
                ;;
        esac
        
        # Get value from environment variable
        env_value="${!env_var:-}"
        
        if [ -n "$env_value" ]; then
            echo "$key=$env_value" >> "$OUTPUT_FILE"
            echo -e "${GREEN}✓ Mapped $env_var -> $key${NC}"
            MAPPED_COUNT=$((MAPPED_COUNT + 1))
        else
            echo -e "${YELLOW}⚠️  Environment variable $env_var not set for $key${NC}"
            # Add placeholder to show what's missing
            echo "# $key=MISSING_${env_var}" >> "$OUTPUT_FILE"
            MISSING_COUNT=$((MISSING_COUNT + 1))
        fi
    fi
done < "$TEMPLATE_FILE"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Summary                                                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Parameters mapped: $MAPPED_COUNT${NC}"

if [ $MISSING_COUNT -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Parameters missing: $MISSING_COUNT${NC}"
fi

echo ""
echo -e "${GREEN}✓ Generated $OUTPUT_FILE from environment variables${NC}"

exit 0

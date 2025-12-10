#!/bin/bash
# Preview Mode: Create Kubernetes Secrets Directly
# Usage: ./create-k8s-secrets.sh <env-file>
#
# This script reads .env.ssm and creates Kubernetes secrets directly
# instead of using AWS SSM + ESO. Used only in preview environments.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ENV_FILE="${1:-.env.ssm}"

if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}✗ Error: $ENV_FILE not found${NC}"
    exit 1
fi

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Preview Mode - Creating Kubernetes Secrets                ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

CREATED_COUNT=0
ERROR_COUNT=0

# Process .env.ssm file
while IFS='=' read -r key value || [ -n "$key" ]; do
    # Skip empty lines and comments
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    
    # Only process SSM parameter paths (start with /)
    if [[ ! "$key" =~ ^/ ]]; then
        continue
    fi
    
    # Trim whitespace
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)
    
    # Skip empty values
    if [ -z "$value" ]; then
        echo -e "${YELLOW}⚠️  Skipping empty value for: $key${NC}"
        continue
    fi
    
    echo -e "${BLUE}Creating secret for:${NC} $key"
    
    # Extract service name and secret key from SSM path
    # /zerotouch/prod/agent-executor/openai_api_key -> agent-executor, openai_api_key
    service_name=$(echo "$key" | sed 's|^/zerotouch/prod/||' | cut -d'/' -f1)
    secret_key=$(echo "$key" | sed 's|^/zerotouch/prod/[^/]*/||' | tr '/' '_' | tr '-' '_')
    
    # Map service to namespace and secret name
    case "$service_name" in
        "agent-executor")
            namespace="intelligence-deepagents"
            secret_name="agent-executor-llm-keys"
            ;;
        "kagent")
            namespace="intelligence"
            secret_name="kagent-llm-keys"
            ;;
        "platform")
            namespace="argocd"
            secret_name="platform-secrets"
            ;;
        "argocd")
            namespace="argocd"
            secret_name="argocd-repo-secrets"
            ;;
        *)
            namespace="default"
            secret_name="${service_name}-secrets"
            ;;
    esac
    
    # Create namespace if it doesn't exist
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
    
    # Create or patch secret
    if kubectl get secret "$secret_name" -n "$namespace" > /dev/null 2>&1; then
        # Update existing secret
        kubectl patch secret "$secret_name" -n "$namespace" \
            --type merge \
            -p "{\"data\":{\"$secret_key\":\"$(echo -n "$value" | base64 -w 0)\"}}" > /dev/null 2>&1
    else
        # Create new secret
        kubectl create secret generic "$secret_name" -n "$namespace" \
            --from-literal="$secret_key=$value" > /dev/null 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Created: $namespace/$secret_name[$secret_key]${NC}"
        CREATED_COUNT=$((CREATED_COUNT + 1))
    else
        echo -e "${RED}✗ Failed: $namespace/$secret_name[$secret_key]${NC}"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    
done < "$ENV_FILE"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Summary                                                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Secrets created: $CREATED_COUNT${NC}"

if [ $ERROR_COUNT -gt 0 ]; then
    echo -e "${RED}✗ Secrets failed: $ERROR_COUNT${NC}"
fi

echo ""
echo -e "${GREEN}✓ Preview secrets created directly in Kubernetes${NC}"
echo -e "${YELLOW}Services can now access secrets without ESO${NC}"
echo ""

exit 0
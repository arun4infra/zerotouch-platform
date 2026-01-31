#!/bin/bash
# Bootstrap script to inject Age private key into ArgoCD namespace
# Usage: ./inject-age-key.sh
#
# This script creates the sops-age secret in the ArgoCD namespace.
# It waits for the namespace to exist and is idempotent.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Age Key Injection - SOPS Decryption Setup                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ Error: kubectl not found${NC}"
    echo -e "${YELLOW}Install kubectl: https://kubernetes.io/docs/tasks/tools/${NC}"
    exit 1
fi

# Check if AGE_PRIVATE_KEY environment variable is set
if [ -z "$AGE_PRIVATE_KEY" ]; then
    echo -e "${RED}✗ Error: AGE_PRIVATE_KEY environment variable not set${NC}"
    echo -e "${YELLOW}Run generate-age-keys.sh first:${NC}"
    echo -e "  ${GREEN}source ./generate-age-keys.sh${NC}"
    exit 1
fi

# Validate Age private key format
if [[ ! "$AGE_PRIVATE_KEY" =~ ^AGE-SECRET-KEY-1 ]]; then
    echo -e "${RED}✗ Error: Invalid Age private key format${NC}"
    echo -e "${YELLOW}Expected format: AGE-SECRET-KEY-1...${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Age private key found in environment${NC}"
echo ""

# Wait for ArgoCD namespace to exist (up to 300 seconds)
echo -e "${BLUE}Waiting for ArgoCD namespace to exist...${NC}"
TIMEOUT=300
ELAPSED=0
INTERVAL=5

while [ $ELAPSED -lt $TIMEOUT ]; do
    if kubectl get namespace argocd &> /dev/null; then
        echo -e "${GREEN}✓ ArgoCD namespace exists${NC}"
        break
    fi
    
    echo -e "${YELLOW}⏳ Waiting for ArgoCD namespace... (${ELAPSED}s/${TIMEOUT}s)${NC}"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo -e "${RED}✗ Error: ArgoCD namespace not found after ${TIMEOUT} seconds${NC}"
    echo -e "${YELLOW}Create the namespace manually:${NC}"
    echo -e "  ${GREEN}kubectl create namespace argocd${NC}"
    exit 1
fi

echo ""

# Create or update the sops-age secret
echo -e "${BLUE}Creating sops-age secret...${NC}"

kubectl create secret generic sops-age \
    --namespace=argocd \
    --from-literal=keys.txt="$AGE_PRIVATE_KEY" \
    --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Secret sops-age created/updated successfully${NC}"
else
    echo -e "${RED}✗ Failed to create secret${NC}"
    exit 1
fi

echo ""

# Verify secret was created successfully
echo -e "${BLUE}Verifying secret...${NC}"

if kubectl get secret sops-age -n argocd &> /dev/null; then
    echo -e "${GREEN}✓ Secret sops-age exists in argocd namespace${NC}"
    
    # Validate secret format
    SECRET_KEY=$(kubectl get secret sops-age -n argocd -o jsonpath='{.data.keys\.txt}' 2>/dev/null | base64 -d)
    
    if [[ "$SECRET_KEY" =~ ^AGE-SECRET-KEY-1 ]]; then
        echo -e "${GREEN}✓ Secret format validated (AGE-SECRET-KEY-1...)${NC}"
    else
        echo -e "${RED}✗ Warning: Secret format validation failed${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ Failed to verify secret${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Summary                                                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Age private key injected into cluster${NC}"
echo -e "${GREEN}✓ Secret: sops-age${NC}"
echo -e "${GREEN}✓ Namespace: argocd${NC}"
echo -e "${GREEN}✓ Data field: keys.txt${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Deploy KSOPS package to ArgoCD"
echo -e "  2. KSOPS sidecar will mount this secret"
echo -e "  3. Verify: ${GREEN}kubectl get secret -n argocd sops-age${NC}"
echo ""

exit 0

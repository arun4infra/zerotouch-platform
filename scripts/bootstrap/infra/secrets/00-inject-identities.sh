#!/bin/bash
# Bootstrap script to inject GitHub App authentication credentials into ArgoCD
# Usage: ./00-inject-identities.sh <github-app-id> <installation-id> <private-key-pem-file>
#
# This script creates the argocd-github-app-creds secret in the ArgoCD namespace
# for GitHub App authentication. It's idempotent and can be run multiple times.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
if [ "$#" -ne 3 ]; then
    echo -e "${RED}Usage:${NC} $0 <github-app-id> <installation-id> <private-key-pem-file>"
    echo ""
    echo "Arguments:"
    echo "  <github-app-id>         GitHub App ID"
    echo "  <installation-id>       GitHub App Installation ID"
    echo "  <private-key-pem-file>  Path to GitHub App private key PEM file"
    echo ""
    echo "Example:"
    echo "  $0 123456 78910 /path/to/github-app-private-key.pem"
    exit 1
fi

GITHUB_APP_ID="$1"
INSTALLATION_ID="$2"
PRIVATE_KEY_FILE="$3"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   GitHub App Authentication - Identity Injection            ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Validate inputs
if [ -z "$GITHUB_APP_ID" ]; then
    echo -e "${RED}✗ Error: GitHub App ID is required${NC}"
    exit 1
fi

if [ -z "$INSTALLATION_ID" ]; then
    echo -e "${RED}✗ Error: Installation ID is required${NC}"
    exit 1
fi

if [ ! -f "$PRIVATE_KEY_FILE" ]; then
    echo -e "${RED}✗ Error: Private key file not found: $PRIVATE_KEY_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✓ GitHub App ID: $GITHUB_APP_ID${NC}"
echo -e "${GREEN}✓ Installation ID: $INSTALLATION_ID${NC}"
echo -e "${GREEN}✓ Private key file: $PRIVATE_KEY_FILE${NC}"
echo ""

# Check kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ Error: kubectl not found${NC}"
    echo -e "${YELLOW}Install kubectl: https://kubernetes.io/docs/tasks/tools/${NC}"
    exit 1
fi

# Ensure ArgoCD namespace exists
echo -e "${BLUE}Ensuring ArgoCD namespace exists...${NC}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
echo -e "${GREEN}✓ ArgoCD namespace ready${NC}"
echo ""

# Read private key content
PRIVATE_KEY_CONTENT=$(cat "$PRIVATE_KEY_FILE")

# Create or update the secret
echo -e "${BLUE}Creating GitHub App credentials secret...${NC}"

kubectl create secret generic argocd-github-app-creds \
    --namespace=argocd \
    --from-literal=githubAppID="$GITHUB_APP_ID" \
    --from-literal=githubAppInstallationID="$INSTALLATION_ID" \
    --from-literal=githubAppPrivateKey="$PRIVATE_KEY_CONTENT" \
    --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Secret argocd-github-app-creds created/updated successfully${NC}"
else
    echo -e "${RED}✗ Failed to create secret${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Summary                                                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ GitHub App authentication credentials injected${NC}"
echo -e "${GREEN}✓ Secret: argocd-github-app-creds${NC}"
echo -e "${GREEN}✓ Namespace: argocd${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Deploy ArgoCD with GitHub App authentication"
echo -e "  2. Configure ArgoCD to use the GitHub App credentials"
echo -e "  3. Verify: ${GREEN}kubectl get secret -n argocd argocd-github-app-creds${NC}"
echo ""

exit 0

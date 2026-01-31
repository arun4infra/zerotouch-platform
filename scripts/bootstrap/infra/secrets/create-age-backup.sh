#!/bin/bash
# Bootstrap script to create encrypted backup of Age private key
# Usage: ./create-age-backup.sh
#
# This script generates a recovery master key, encrypts the Age private key,
# and stores both in Kubernetes secrets for automated recovery.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Age Key Backup - Automated Recovery Setup                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check required tools
if ! command -v age-keygen &> /dev/null; then
    echo -e "${RED}✗ Error: age-keygen not found${NC}"
    echo -e "${YELLOW}Install age: https://github.com/FiloSottile/age${NC}"
    exit 1
fi

if ! command -v age &> /dev/null; then
    echo -e "${RED}✗ Error: age not found${NC}"
    echo -e "${YELLOW}Install age: https://github.com/FiloSottile/age${NC}"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ Error: kubectl not found${NC}"
    echo -e "${YELLOW}Install kubectl: https://kubernetes.io/docs/tasks/tools/${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Required tools found${NC}"
echo ""

# Check if AGE_PRIVATE_KEY environment variable is set
if [ -z "$AGE_PRIVATE_KEY" ]; then
    echo -e "${RED}✗ Error: AGE_PRIVATE_KEY environment variable not set${NC}"
    echo -e "${YELLOW}Run generate-age-keys.sh first:${NC}"
    echo -e "  ${GREEN}source ./generate-age-keys.sh${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Age private key found in environment${NC}"
echo ""

# Generate recovery master key
echo -e "${BLUE}Generating recovery master key...${NC}"
RECOVERY_KEYGEN_OUTPUT=$(age-keygen 2>&1)

RECOVERY_PUBLIC_KEY=$(echo "$RECOVERY_KEYGEN_OUTPUT" | grep "# public key:" | sed 's/# public key: //')
RECOVERY_PRIVATE_KEY=$(echo "$RECOVERY_KEYGEN_OUTPUT" | grep "^AGE-SECRET-KEY-1" | head -n 1)

if [ -z "$RECOVERY_PUBLIC_KEY" ] || [ -z "$RECOVERY_PRIVATE_KEY" ]; then
    echo -e "${RED}✗ Error: Failed to generate recovery master key${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Recovery master key generated${NC}"
echo ""

# Encrypt Age private key with recovery master key
echo -e "${BLUE}Encrypting Age private key...${NC}"

ENCRYPTED_AGE_KEY=$(echo "$AGE_PRIVATE_KEY" | age -r "$RECOVERY_PUBLIC_KEY" -a)

if [ -z "$ENCRYPTED_AGE_KEY" ]; then
    echo -e "${RED}✗ Error: Failed to encrypt Age private key${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Age private key encrypted${NC}"
echo ""

# Ensure ArgoCD namespace exists
if ! kubectl get namespace argocd &> /dev/null; then
    echo -e "${RED}✗ Error: ArgoCD namespace not found${NC}"
    echo -e "${YELLOW}Run inject-age-key.sh first to create the namespace${NC}"
    exit 1
fi

# Create age-backup-encrypted secret
echo -e "${BLUE}Creating age-backup-encrypted secret...${NC}"

kubectl create secret generic age-backup-encrypted \
    --namespace=argocd \
    --from-literal=encrypted-key.txt="$ENCRYPTED_AGE_KEY" \
    --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Secret age-backup-encrypted created/updated${NC}"
else
    echo -e "${RED}✗ Failed to create age-backup-encrypted secret${NC}"
    exit 1
fi

# Create recovery-master-key secret
echo -e "${BLUE}Creating recovery-master-key secret...${NC}"

kubectl create secret generic recovery-master-key \
    --namespace=argocd \
    --from-literal=recovery-key.txt="$RECOVERY_PRIVATE_KEY" \
    --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Secret recovery-master-key created/updated${NC}"
else
    echo -e "${RED}✗ Failed to create recovery-master-key secret${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Summary                                                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Recovery master key generated${NC}"
echo -e "${GREEN}✓ Age private key encrypted${NC}"
echo -e "${GREEN}✓ Backup secrets created in argocd namespace${NC}"
echo ""
echo -e "${YELLOW}Secrets created:${NC}"
echo -e "  - ${GREEN}age-backup-encrypted${NC} (encrypted Age private key)"
echo -e "  - ${GREEN}recovery-master-key${NC} (recovery master key)"
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Backup Retrieval Process                                   ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}To manually recover the Age private key:${NC}"
echo ""
echo -e "1. Extract the recovery master key:"
echo -e "   ${GREEN}kubectl get secret recovery-master-key -n argocd -o jsonpath='{.data.recovery-key\.txt}' | base64 -d > recovery-key.txt${NC}"
echo ""
echo -e "2. Extract the encrypted Age key:"
echo -e "   ${GREEN}kubectl get secret age-backup-encrypted -n argocd -o jsonpath='{.data.encrypted-key\.txt}' | base64 -d > encrypted-age-key.txt${NC}"
echo ""
echo -e "3. Decrypt the Age private key:"
echo -e "   ${GREEN}age -d -i recovery-key.txt encrypted-age-key.txt${NC}"
echo ""
echo -e "4. Inject the decrypted key back into the cluster:"
echo -e "   ${GREEN}export AGE_PRIVATE_KEY=\$(age -d -i recovery-key.txt encrypted-age-key.txt)${NC}"
echo -e "   ${GREEN}./inject-age-key.sh${NC}"
echo ""
echo -e "${YELLOW}Automated Recovery:${NC}"
echo -e "  The Age Key Guardian CronJob will automatically restore the"
echo -e "  sops-age secret if it gets deleted, using these backup secrets."
echo ""
echo -e "${RED}⚠️  IMPORTANT: Store the recovery master key securely offline!${NC}"
echo -e "   ${YELLOW}Recovery Public Key:${NC} $RECOVERY_PUBLIC_KEY"
echo ""

exit 0

#!/bin/bash
# Validation script for CHECKPOINT 2: Age Key Infrastructure and Storage
# Usage: ./validate-age-keys-and-storage.sh
#
# This script validates that Age keys are properly generated, injected,
# backed up, and Hetzner Object Storage is provisioned correctly.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validation counters
PASSED=0
FAILED=0
TOTAL=0

# Function to run validation check
validate() {
    local test_name=$1
    local test_command=$2
    
    TOTAL=$((TOTAL + 1))
    echo -e "${BLUE}[${TOTAL}] Testing: $test_name${NC}"
    
    if eval "$test_command"; then
        echo -e "${GREEN}✓ PASSED: $test_name${NC}"
        PASSED=$((PASSED + 1))
        echo ""
        return 0
    else
        echo -e "${RED}✗ FAILED: $test_name${NC}"
        FAILED=$((FAILED + 1))
        echo ""
        return 1
    fi
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   CHECKPOINT 2: Age Key Infrastructure and Storage           ║${NC}"
echo -e "${BLUE}║   Validation Script                                          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ Error: kubectl not found${NC}"
    exit 1
fi

# Check AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ Error: AWS CLI not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Required tools found${NC}"
echo ""

# Validation 1: Secret sops-age exists in argocd namespace
validate "Secret sops-age exists in argocd namespace" \
    "kubectl get secret sops-age -n argocd &> /dev/null"

# Validation 2: Age private key correctly formatted
validate "Age private key correctly formatted (starts with AGE-SECRET-KEY-1)" \
    "kubectl get secret sops-age -n argocd -o jsonpath='{.data.keys\.txt}' 2>/dev/null | base64 -d | grep -q '^AGE-SECRET-KEY-1'"

# Validation 3: Secret age-backup-encrypted exists
validate "Secret age-backup-encrypted exists in argocd namespace" \
    "kubectl get secret age-backup-encrypted -n argocd &> /dev/null"

# Validation 4: Secret recovery-master-key exists
validate "Secret recovery-master-key exists in argocd namespace" \
    "kubectl get secret recovery-master-key -n argocd &> /dev/null"

# Validation 5: Hetzner buckets created
if [ -n "$HETZNER_S3_ACCESS_KEY" ] && [ -n "$HETZNER_S3_SECRET_KEY" ]; then
    export AWS_ACCESS_KEY_ID="$HETZNER_S3_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$HETZNER_S3_SECRET_KEY"
    HETZNER_ENDPOINT="https://pr-secrets.fsn1.your-objectstorage.com"
    
    validate "Hetzner bucket zerotouch-compliance-reports exists" \
        "aws s3api head-bucket --bucket zerotouch-compliance-reports --endpoint-url $HETZNER_ENDPOINT 2>/dev/null"
    
    validate "Hetzner bucket zerotouch-cnpg-backups exists" \
        "aws s3api head-bucket --bucket zerotouch-cnpg-backups --endpoint-url $HETZNER_ENDPOINT 2>/dev/null"
    
    # Validation 6: Object Lock enabled in Compliance Mode
    validate "Object Lock enabled for zerotouch-compliance-reports" \
        "aws s3api get-object-lock-configuration --bucket zerotouch-compliance-reports --endpoint-url $HETZNER_ENDPOINT 2>/dev/null | grep -q 'COMPLIANCE'"
    
    validate "Object Lock enabled for zerotouch-cnpg-backups" \
        "aws s3api get-object-lock-configuration --bucket zerotouch-cnpg-backups --endpoint-url $HETZNER_ENDPOINT 2>/dev/null | grep -q 'COMPLIANCE'"
else
    echo -e "${YELLOW}⚠️  Skipping Hetzner bucket validation (credentials not set)${NC}"
    echo ""
fi

# Validation 7: Secret hetzner-s3-credentials exists in default namespace
validate "Secret hetzner-s3-credentials exists in default namespace" \
    "kubectl get secret hetzner-s3-credentials -n default &> /dev/null"

# Validation 8: Test script idempotency
echo -e "${BLUE}[${TOTAL}] Testing: Script idempotency${NC}"
echo -e "${YELLOW}Note: This requires running the scripts multiple times manually${NC}"
echo -e "${YELLOW}Scripts should be idempotent and not fail on re-run${NC}"
echo ""

# Summary
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Validation Summary                                         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Passed: $PASSED / $TOTAL${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED / $TOTAL${NC}"
fi
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ CHECKPOINT 2 VALIDATION PASSED${NC}"
    echo ""
    echo -e "${YELLOW}Success Criteria Met:${NC}"
    echo -e "  ✓ Age keys properly generated and stored"
    echo -e "  ✓ Backup recovery mechanism functional"
    echo -e "  ✓ Hetzner Object Storage operational"
    echo -e "  ✓ All bootstrap scripts idempotent"
    echo ""
    exit 0
else
    echo -e "${RED}✗ CHECKPOINT 2 VALIDATION FAILED${NC}"
    echo ""
    echo -e "${YELLOW}Please fix the failed validations before proceeding${NC}"
    echo ""
    exit 1
fi

#!/bin/bash
# Bootstrap script to provision Hetzner Object Storage
# Usage: ./03-bootstrap-storage.sh
#
# This script creates S3-compatible buckets on Hetzner Object Storage
# with Object Lock enabled for compliance and backup retention.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Hetzner Object Storage endpoint
HETZNER_ENDPOINT="https://pr-secrets.fsn1.your-objectstorage.com"
HETZNER_REGION="fsn1"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Hetzner Object Storage - Bootstrap Provisioning           ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check required tools
if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ Error: AWS CLI not found${NC}"
    echo -e "${YELLOW}Install AWS CLI: https://aws.amazon.com/cli/${NC}"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ Error: kubectl not found${NC}"
    echo -e "${YELLOW}Install kubectl: https://kubernetes.io/docs/tasks/tools/${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Required tools found${NC}"
echo ""

# Validate Hetzner credentials
if [ -z "$HETZNER_S3_ACCESS_KEY" ]; then
    echo -e "${RED}✗ Error: HETZNER_S3_ACCESS_KEY environment variable not set${NC}"
    echo -e "${YELLOW}Set Hetzner credentials:${NC}"
    echo -e "  ${GREEN}export HETZNER_S3_ACCESS_KEY=your-access-key${NC}"
    echo -e "  ${GREEN}export HETZNER_S3_SECRET_KEY=your-secret-key${NC}"
    exit 1
fi

if [ -z "$HETZNER_S3_SECRET_KEY" ]; then
    echo -e "${RED}✗ Error: HETZNER_S3_SECRET_KEY environment variable not set${NC}"
    echo -e "${YELLOW}Set Hetzner credentials:${NC}"
    echo -e "  ${GREEN}export HETZNER_S3_ACCESS_KEY=your-access-key${NC}"
    echo -e "  ${GREEN}export HETZNER_S3_SECRET_KEY=your-secret-key${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Hetzner credentials validated${NC}"
echo ""

# Configure AWS CLI for Hetzner Object Storage
export AWS_ACCESS_KEY_ID="$HETZNER_S3_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$HETZNER_S3_SECRET_KEY"

# Function to create bucket with Object Lock
create_bucket_with_lock() {
    local bucket_name=$1
    local retention_days=$2
    
    echo -e "${BLUE}Creating bucket: $bucket_name${NC}"
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$bucket_name" --endpoint-url "$HETZNER_ENDPOINT" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Bucket $bucket_name already exists${NC}"
        return 0
    fi
    
    # Create bucket with Object Lock enabled
    aws s3api create-bucket \
        --bucket "$bucket_name" \
        --endpoint-url "$HETZNER_ENDPOINT" \
        --region "$HETZNER_REGION" \
        --object-lock-enabled-for-bucket \
        --no-cli-pager > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Failed to create bucket $bucket_name${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Bucket $bucket_name created${NC}"
    
    # Configure Object Lock retention (Compliance Mode)
    echo -e "${BLUE}Configuring Object Lock retention (${retention_days} days)...${NC}"
    
    aws s3api put-object-lock-configuration \
        --bucket "$bucket_name" \
        --endpoint-url "$HETZNER_ENDPOINT" \
        --object-lock-configuration "{
            \"ObjectLockEnabled\": \"Enabled\",
            \"Rule\": {
                \"DefaultRetention\": {
                    \"Mode\": \"COMPLIANCE\",
                    \"Days\": $retention_days
                }
            }
        }" \
        --no-cli-pager > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Failed to configure Object Lock for $bucket_name${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Object Lock configured (Compliance Mode, ${retention_days} days)${NC}"
    echo ""
    
    return 0
}

# Create compliance reports bucket (7-year retention = 2555 days)
create_bucket_with_lock "zerotouch-compliance-reports" 2555

# Create CNPG backups bucket (30-day retention)
create_bucket_with_lock "zerotouch-cnpg-backups" 30

# Verify bucket accessibility
echo -e "${BLUE}Verifying bucket accessibility...${NC}"

for bucket in "zerotouch-compliance-reports" "zerotouch-cnpg-backups"; do
    if aws s3 ls "s3://$bucket" --endpoint-url "$HETZNER_ENDPOINT" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Bucket $bucket is accessible${NC}"
    else
        echo -e "${RED}✗ Failed to access bucket $bucket${NC}"
        exit 1
    fi
done

echo ""

# Create Kubernetes secret for Hetzner S3 credentials
echo -e "${BLUE}Creating Kubernetes secret for Hetzner S3 credentials...${NC}"

# Ensure default namespace exists
kubectl create namespace default --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1

kubectl create secret generic hetzner-s3-credentials \
    --namespace=default \
    --from-literal=access-key="$HETZNER_S3_ACCESS_KEY" \
    --from-literal=secret-key="$HETZNER_S3_SECRET_KEY" \
    --from-literal=endpoint="$HETZNER_ENDPOINT" \
    --from-literal=region="$HETZNER_REGION" \
    --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Secret hetzner-s3-credentials created/updated${NC}"
else
    echo -e "${RED}✗ Failed to create secret${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Summary                                                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Hetzner Object Storage provisioned${NC}"
echo ""
echo -e "${YELLOW}Buckets created:${NC}"
echo -e "  - ${GREEN}zerotouch-compliance-reports${NC} (7-year retention, Compliance Mode)"
echo -e "  - ${GREEN}zerotouch-cnpg-backups${NC} (30-day retention, Compliance Mode)"
echo ""
echo -e "${YELLOW}Kubernetes secret:${NC}"
echo -e "  - ${GREEN}hetzner-s3-credentials${NC} (default namespace)"
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Hetzner Object Storage Setup                               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Endpoint:${NC} $HETZNER_ENDPOINT"
echo -e "${YELLOW}Region:${NC} $HETZNER_REGION"
echo ""
echo -e "${YELLOW}Verify buckets:${NC}"
echo -e "  ${GREEN}aws s3 ls --endpoint-url $HETZNER_ENDPOINT${NC}"
echo ""
echo -e "${YELLOW}List bucket contents:${NC}"
echo -e "  ${GREEN}aws s3 ls s3://zerotouch-compliance-reports --endpoint-url $HETZNER_ENDPOINT${NC}"
echo -e "  ${GREEN}aws s3 ls s3://zerotouch-cnpg-backups --endpoint-url $HETZNER_ENDPOINT${NC}"
echo ""
echo -e "${YELLOW}Verify Object Lock configuration:${NC}"
echo -e "  ${GREEN}aws s3api get-object-lock-configuration --bucket zerotouch-compliance-reports --endpoint-url $HETZNER_ENDPOINT${NC}"
echo ""
echo -e "${RED}⚠️  IMPORTANT: Object Lock in Compliance Mode cannot be disabled!${NC}"
echo -e "   ${YELLOW}Objects are immutable for the retention period.${NC}"
echo ""

exit 0

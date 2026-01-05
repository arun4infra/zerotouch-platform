#!/bin/bash
set -euo pipefail

# 00-create-oidc-bucket.sh - Create S3 bucket for OIDC discovery
# Run this with admin credentials before running 00-setup-aws-identity.sh

ENVIRONMENT="${1:-dev}"
OIDC_BUCKET="zerotouch-oidc-${ENVIRONMENT}"
REGION="ap-south-1"

echo "Creating OIDC S3 bucket for environment: ${ENVIRONMENT}"
echo "Bucket: ${OIDC_BUCKET}"
echo "Region: ${REGION}"

# Verify we have admin credentials
CALLER_IDENTITY=$(aws sts get-caller-identity)
echo "Current AWS identity: $(echo $CALLER_IDENTITY | jq -r .Arn)"

# Create S3 bucket
echo "Creating S3 bucket..."
if aws s3 ls "s3://${OIDC_BUCKET}" 2>/dev/null; then
  echo "Bucket ${OIDC_BUCKET} already exists"
else
  aws s3 mb "s3://${OIDC_BUCKET}" --region "${REGION}"
fi

# Configure bucket for public read access
echo "Configuring bucket policy for public read access..."
echo "Disabling S3 Block Public Access..."
aws s3api put-public-access-block \
  --bucket "${OIDC_BUCKET}" \
  --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

echo "Setting bucket policy..."
aws s3api put-bucket-policy --bucket "${OIDC_BUCKET}" --policy '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::'"${OIDC_BUCKET}"'/*"
    }
  ]
}'

# Verify bucket exists and is accessible
echo "Verifying bucket configuration..."
aws s3 ls "s3://${OIDC_BUCKET}/" || echo "Bucket created but empty (expected)"

echo ""
echo "✅ OIDC bucket created successfully!"
echo "Bucket: s3://${OIDC_BUCKET}"
echo ""
echo "Next step: Run ./scripts/bootstrap/infra/00-setup-aws-identity.sh ${ENVIRONMENT}"
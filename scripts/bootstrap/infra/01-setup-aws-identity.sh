#!/bin/bash
set -euo pipefail

# 00-setup-aws-identity.sh - Setup AWS OIDC Identity for ZeroTouch Platform
# This script creates the foundational OIDC infrastructure for AWS integration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Configuration
AWS_ACCOUNT_ID="337832075585"
ENVIRONMENT="${1:-dev}"
OIDC_BUCKET="zerotouch-oidc-${ENVIRONMENT}"
OIDC_URL="https://${OIDC_BUCKET}.s3.ap-south-1.amazonaws.com"
ESO_ROLE_NAME="zerotouch-eso-role-${ENVIRONMENT}"
CROSSPLANE_ROLE_NAME="zerotouch-crossplane-role-${ENVIRONMENT}"

echo "Setting up AWS OIDC Identity for environment: ${ENVIRONMENT}"
echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
echo "OIDC Bucket: ${OIDC_BUCKET}"

# Create temporary directory for OIDC files
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

cd "${TEMP_DIR}"

# Part A: Generate RSA Keys
echo "Generating RSA key pair..."
openssl genrsa -out sa-signer.key 2048
openssl rsa -in sa-signer.key -pubout -out sa-signer.pub

# Extract key components for JWKS
MODULUS=$(openssl rsa -in sa-signer.key -noout -modulus | sed 's/Modulus=//' | xxd -r -p | base64 | tr -d '=' | tr '/+' '_-')
EXPONENT=$(openssl rsa -in sa-signer.key -noout -text | grep publicExponent | awk '{print $2}' | sed 's/(//' | sed 's/)//' | printf "%08x" $(cat) | xxd -r -p | base64 | tr -d '=' | tr '/+' '_-')

# Create OIDC discovery document
mkdir -p .well-known
cat > .well-known/openid_configuration << EOF
{
  "issuer": "${OIDC_URL}",
  "jwks_uri": "${OIDC_URL}/keys.json",
  "authorization_endpoint": "${OIDC_URL}/authorize",
  "response_types_supported": ["id_token"],
  "subject_types_supported": ["public"],
  "id_token_signing_alg_values_supported": ["RS256"]
}
EOF

# Create JWKS document
cat > keys.json << EOF
{
  "keys": [
    {
      "use": "sig",
      "kty": "RSA",
      "kid": "zerotouch-${ENVIRONMENT}",
      "alg": "RS256",
      "n": "${MODULUS}",
      "e": "${EXPONENT}"
    }
  ]
}
EOF

# Part B: Verify S3 Bucket for OIDC exists
echo "Verifying S3 bucket for OIDC discovery..."
if ! aws s3 ls "s3://${OIDC_BUCKET}" 2>/dev/null; then
  echo "❌ OIDC bucket ${OIDC_BUCKET} does not exist"
  echo ""
  echo "Please run the bucket creation script first:"
  echo "  ./scripts/bootstrap/infra/00-create-oidc-bucket.sh ${ENVIRONMENT}"
  echo ""
  exit 1
fi
echo "✅ OIDC bucket ${OIDC_BUCKET} exists"

# Upload OIDC discovery files
echo "Uploading OIDC discovery files..."
aws s3 cp .well-known/openid_configuration "s3://${OIDC_BUCKET}/.well-known/openid_configuration" --content-type "application/json"
aws s3 cp keys.json "s3://${OIDC_BUCKET}/keys.json" --content-type "application/json"

# Part C: Create OIDC Provider in AWS
echo "Creating OIDC Provider in AWS..."
OIDC_PROVIDER_ARN=$(aws iam create-open-id-connect-provider \
  --url "${OIDC_URL}" \
  --thumbprint-list "9e99a48a9960b14926bb7f3b02e22da2b0ab7280" \
  --client-id-list "sts.amazonaws.com" \
  --query 'OpenIDConnectProviderArn' \
  --output text 2>/dev/null || \
  aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_BUCKET}.s3.ap-south-1.amazonaws.com" \
  --query 'Url' --output text | sed "s|https://|arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/|")

echo "OIDC Provider ARN: ${OIDC_PROVIDER_ARN}"

# Part D: Create ESO IAM Role
echo "Creating ESO IAM Role..."
cat > eso-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_BUCKET}.s3.ap-south-1.amazonaws.com:sub": "system:serviceaccount:external-secrets:external-secrets",
          "${OIDC_BUCKET}.s3.ap-south-1.amazonaws.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name "${ESO_ROLE_NAME}" \
  --assume-role-policy-document file://eso-trust-policy.json \
  --description "Role for External Secrets Operator OIDC access" || echo "ESO role may already exist"

# Attach SSM policy to ESO role
aws iam attach-role-policy \
  --role-name "${ESO_ROLE_NAME}" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"

# Part E: Create Crossplane IAM Role
echo "Creating Crossplane IAM Role..."
cat > crossplane-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_BUCKET}.s3.ap-south-1.amazonaws.com:sub": "system:serviceaccount:crossplane-system:provider-aws-*",
          "${OIDC_BUCKET}.s3.ap-south-1.amazonaws.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name "${CROSSPLANE_ROLE_NAME}" \
  --assume-role-policy-document file://crossplane-trust-policy.json \
  --description "Role for Crossplane AWS providers OIDC access" || echo "Crossplane role may already exist"

# Create and attach S3 policy for Crossplane
cat > crossplane-s3-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetBucketPolicy",
        "s3:PutBucketPolicy",
        "s3:DeleteBucketPolicy",
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::deepagents-*",
        "arn:aws:s3:::deepagents-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy"
      ],
      "Resource": [
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/deepagents-*",
        "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/deepagents-*"
      ]
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name "zerotouch-crossplane-s3-policy-${ENVIRONMENT}" \
  --policy-document file://crossplane-s3-policy.json \
  --description "S3 and IAM permissions for Crossplane" || echo "Policy may already exist"

aws iam attach-role-policy \
  --role-name "${CROSSPLANE_ROLE_NAME}" \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/zerotouch-crossplane-s3-policy-${ENVIRONMENT}"

# Part F: Save private key for Talos configuration
echo "Saving private key for Talos configuration..."
cp sa-signer.key "${PLATFORM_ROOT}/sa-signer-${ENVIRONMENT}.key"

echo ""
echo "✅ AWS OIDC Identity setup complete!"
echo ""
echo "Next steps:"
echo "1. Add the private key to Talos configuration:"
echo "   - File: ${PLATFORM_ROOT}/sa-signer-${ENVIRONMENT}.key"
echo "   - Configure in talos-values.yaml under cluster.serviceAccount.key"
echo ""
echo "2. Update External Secrets ClusterSecretStore to use OIDC:"
echo "   - ESO Role ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ESO_ROLE_NAME}"
echo ""
echo "3. Update Crossplane ProviderConfig to use OIDC:"
echo "   - Crossplane Role ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CROSSPLANE_ROLE_NAME}"
echo ""
echo "OIDC Issuer URL: ${OIDC_URL}"
echo "OIDC Provider ARN: ${OIDC_PROVIDER_ARN}"
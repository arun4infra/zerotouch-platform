#!/bin/bash
set -euo pipefail

# 01-setup-aws-identity.sh
# Idempotent setup for AWS OIDC Identity
# Persists the Service Account Key in AWS SSM
# AWS_PROFILE=zerotouch-platform-admin ./scripts/bootstrap/infra/01-setup-aws-identity.sh dev

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Configuration
ENVIRONMENT="${1:-dev}"
# Fetch Account ID dynamically to avoid hardcoding
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="ap-south-1"

OIDC_BUCKET="zerotouch-oidc-${ENVIRONMENT}"
OIDC_URL="https://${OIDC_BUCKET}.s3.${REGION}.amazonaws.com"
ESO_ROLE_NAME="zerotouch-eso-role-${ENVIRONMENT}"
CROSSPLANE_ROLE_NAME="zerotouch-crossplane-role-${ENVIRONMENT}"

# SSM Path for the private key
SSM_KEY_PATH="/zerotouch/${ENVIRONMENT}/oidc/sa-signer-key"

echo "Setting up AWS OIDC Identity for environment: ${ENVIRONMENT}"
echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "OIDC Bucket: ${OIDC_BUCKET}"

# Prerequisites Check
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install it."
    exit 1
fi

# Verify we have credentials and they are valid
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ No valid AWS Credentials found."
    echo "   - Local: Run 'aws configure' or export AWS_PROFILE"
    echo "   - CI: Ensure 'aws-actions/configure-aws-credentials' runs before this step."
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT
cd "${TEMP_DIR}"

# ------------------------------------------------------------------
# Part A: RSA Key Management (Idempotent via SSM)
# ------------------------------------------------------------------
echo "Checking for existing key in SSM (${SSM_KEY_PATH})..."

if aws ssm get-parameter --name "${SSM_KEY_PATH}" --with-decryption >/dev/null 2>&1; then
    echo "✅ Found existing key in SSM. Retrieving..."
    aws ssm get-parameter --name "${SSM_KEY_PATH}" --with-decryption --query "Parameter.Value" --output text > sa-signer.key
else
    echo "⚠️  No key found. Generating NEW RSA key pair..."
    openssl genrsa -out sa-signer.key 2048
    
    echo "Backing up new key to SSM (SecureString)..."
    aws ssm put-parameter \
        --name "${SSM_KEY_PATH}" \
        --value "$(cat sa-signer.key)" \
        --type "SecureString" \
        --description "Talos Service Account Signing Key for ${ENVIRONMENT}" \
        --overwrite
fi

# Always regenerate public key from the (retrieved or new) private key
openssl rsa -in sa-signer.key -pubout -out sa-signer.pub

# Extract key components for JWKS
MODULUS=$(openssl rsa -in sa-signer.key -noout -modulus | sed 's/Modulus=//' | xxd -r -p | base64 | tr -d '=' | tr '/+' '_-')
EXPONENT=$(openssl rsa -in sa-signer.key -noout -text | grep publicExponent | awk '{print $2}' | sed 's/(//' | sed 's/)//' | printf "%08x" $(cat) | xxd -r -p | base64 | tr -d '=' | tr '/+' '_-')

# Create OIDC discovery document
mkdir -p .well-known
cat > .well-known/openid-configuration << EOF
{
  "issuer": "${OIDC_URL}",
  "jwks_uri": "${OIDC_URL}/keys.json",
  "authorization_endpoint": "${OIDC_URL}/authorize",
  "response_types_supported": ["id_token"],
  "subject_types_supported": ["public"],
  "id_token_signing_alg_values_supported": ["RS256"],
  "claims_supported": ["sub", "iss", "aud", "exp", "iat"]
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

# ------------------------------------------------------------------
# Part B: S3 Upload (Idempotent)
# ------------------------------------------------------------------
echo "Updating S3 bucket content..."
aws s3 cp .well-known/openid-configuration "s3://${OIDC_BUCKET}/.well-known/openid-configuration" --content-type "application/json"
aws s3 cp keys.json "s3://${OIDC_BUCKET}/keys.json" --content-type "application/json"

# ------------------------------------------------------------------
# Part C: AWS OIDC Provider (Idempotent)
# ------------------------------------------------------------------
echo "Ensuring AWS OIDC Provider exists..."
# Check if exists to avoid error
EXISTING_ARN=$(aws iam list-open-id-connect-providers | grep "${OIDC_BUCKET}" | awk -F'"' '{print $4}' || true)

if [ -n "$EXISTING_ARN" ]; then
    echo "✅ Provider already exists: ${EXISTING_ARN}"
    OIDC_PROVIDER_ARN="${EXISTING_ARN}"
else
    OIDC_PROVIDER_ARN=$(aws iam create-open-id-connect-provider \
      --url "${OIDC_URL}" \
      --thumbprint-list "9e99a48a9960b14926bb7f3b02e22da2b0ab7280" \
      --client-id-list "sts.amazonaws.com" \
      --query 'OpenIDConnectProviderArn' \
      --output text)
    echo "Created Provider: ${OIDC_PROVIDER_ARN}"
fi

# ------------------------------------------------------------------
# Part D & E: IAM Roles (Idempotent updates)
# ------------------------------------------------------------------
echo "Configuring ESO Role..."
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
          "${OIDC_BUCKET}.s3.${REGION}.amazonaws.com:sub": "system:serviceaccount:external-secrets:external-secrets",
          "${OIDC_BUCKET}.s3.${REGION}.amazonaws.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Create if missing, or update trust policy if exists
aws iam create-role --role-name "${ESO_ROLE_NAME}" --assume-role-policy-document file://eso-trust-policy.json 2>/dev/null || \
aws iam update-assume-role-policy --role-name "${ESO_ROLE_NAME}" --policy-document file://eso-trust-policy.json

aws iam attach-role-policy \
  --role-name "${ESO_ROLE_NAME}" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess" 2>/dev/null || true

echo "Configuring Crossplane Role..."
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
        "StringLike": {
          "${OIDC_BUCKET}.s3.${REGION}.amazonaws.com:sub": [
            "system:serviceaccount:crossplane-system:provider-aws-s3-*",
            "system:serviceaccount:crossplane-system:provider-aws-iam-*",
            "system:serviceaccount:crossplane-system:upbound-provider-family-aws-*"
          ]
        },
        "StringEquals": {
          "${OIDC_BUCKET}.s3.${REGION}.amazonaws.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

aws iam create-role --role-name "${CROSSPLANE_ROLE_NAME}" --assume-role-policy-document file://crossplane-trust-policy.json 2>/dev/null || \
aws iam update-assume-role-policy --role-name "${CROSSPLANE_ROLE_NAME}" --policy-document file://crossplane-trust-policy.json

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

POLICY_NAME="zerotouch-crossplane-s3-policy-${ENVIRONMENT}"
aws iam create-policy \
  --policy-name "${POLICY_NAME}" \
  --policy-document file://crossplane-s3-policy.json \
  --description "S3 and IAM permissions for Crossplane" 2>/dev/null || \
aws iam create-policy-version \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" \
  --policy-document file://crossplane-s3-policy.json \
  --set-as-default 2>/dev/null || true

aws iam attach-role-policy \
  --role-name "${CROSSPLANE_ROLE_NAME}" \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" 2>/dev/null || true

# ------------------------------------------------------------------
# Part F: Output for Talos
# ------------------------------------------------------------------
echo ""
echo "✅ AWS OIDC Identity is synced."
echo "   Key Source: SSM Parameter Store (${SSM_KEY_PATH})"
echo "   Public Discovery: S3 (${OIDC_URL})"
echo ""

# Copy the key to the platform root so the Bootstrap script can find it
cp sa-signer.key "${PLATFORM_ROOT}/sa-signer-${ENVIRONMENT}.key"
chmod 600 "${PLATFORM_ROOT}/sa-signer-${ENVIRONMENT}.key"

echo "The private key has been saved to: ${PLATFORM_ROOT}/sa-signer-${ENVIRONMENT}.key"
echo ""
echo "Next steps:"
echo "1. Update Crossplane ProviderConfig to use OIDC:"
echo "   - Crossplane Role ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CROSSPLANE_ROLE_NAME}"
echo ""
echo "OIDC Issuer URL: ${OIDC_URL}"
echo "OIDC Provider ARN: ${OIDC_PROVIDER_ARN}"
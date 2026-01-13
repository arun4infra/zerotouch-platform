#!/bin/bash
# Helper: Prepare OIDC Patch for Talos
# Usage: ./prepare-oidc-patch.sh <ENV> [REGION]
# Returns: Path to the generated temporary patch file

set -e

ENV="${1:-dev}"
REGION="${2:-ap-south-1}"

# Paths
SSM_KEY_PATH="/zerotouch/${ENV}/oidc/sa-signer-key"
OIDC_BUCKET="zerotouch-oidc-${ENV}"
ISSUER_URL="https://${OIDC_BUCKET}.s3.${REGION}.amazonaws.com"

# Check prerequisites
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI not found" >&2
    exit 1
fi

# Fetch Private Key from SSM
# We output logs to stderr (>2) so they don't pollute the file path output
echo "Fetching OIDC key from SSM (${SSM_KEY_PATH})..." >&2

# Check if parameter exists first
if ! aws ssm describe-parameters --parameter-filters "Key=Name,Values=${SSM_KEY_PATH}" --query "Parameters[0].Name" --output text >/dev/null 2>&1; then
    echo "Warning: SSM parameter ${SSM_KEY_PATH} does not exist" >&2
    
    # Fallback: check for local key file
    LOCAL_KEY_FILE="$(dirname "$0")/../../sa-signer-${ENV}.key"
    if [ -f "$LOCAL_KEY_FILE" ]; then
        echo "Using local key file: $LOCAL_KEY_FILE" >&2
        SA_KEY=$(cat "$LOCAL_KEY_FILE")
    else
        echo "Error: Neither SSM parameter nor local key file found" >&2
        echo "Ensure 01-setup-aws-identity.sh has been run for env: ${ENV}" >&2
        exit 1
    fi
else
    SA_KEY=$(aws ssm get-parameter --name "${SSM_KEY_PATH}" --with-decryption --query "Parameter.Value" --output text)
    if [ $? -ne 0 ] || [ -z "$SA_KEY" ]; then
        echo "Error: Could not fetch Key from ${SSM_KEY_PATH}" >&2
        echo "AWS CLI error or empty parameter value" >&2
        exit 1
    fi
fi

# Base64 Encode for Talos Config
SA_KEY_B64=$(echo "$SA_KEY" | base64 | tr -d '\n')

# Create Patch File
PATCH_FILE="/tmp/talos-oidc-patch-${ENV}.yaml"
cat > "$PATCH_FILE" <<EOF
cluster:
  apiServer:
    extraArgs:
      service-account-issuer: "${ISSUER_URL}"
      service-account-jwks-uri: "${ISSUER_URL}/keys.json"
  serviceAccount:
    key: "${SA_KEY_B64}"
  network:
    cni:
      name: none
EOF

echo "OIDC Patch generated at $PATCH_FILE" >&2

# Output the file path to stdout so the caller can capture it
echo "$PATCH_FILE"
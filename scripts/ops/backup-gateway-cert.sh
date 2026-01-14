#!/bin/bash
# scripts/ops/backup-gateway-cert.sh
# Saves the production TLS certificate to AWS SSM

set -e

ENV="prod"
SECRET_NAME="nutgraf-tls-cert"
NAMESPACE="kube-system"
SSM_PATH="/zerotouch/${ENV}/gateway/tls-cert"

echo "Backing up $SECRET_NAME to AWS SSM..."

# 1. Get the certificate data (JSON)
CERT_JSON=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o json)

if [ -z "$CERT_JSON" ]; then
    echo "Error: Secret not found in cluster."
    exit 1
fi

# 2. Upload to SSM as SecureString
# We store the whole JSON to preserve tls.crt, tls.key, and ca.crt
echo "$CERT_JSON" | jq -c '{data: .data, type: .type}' | \
    aws ssm put-parameter \
        --name "$SSM_PATH" \
        --type "SecureString" \
        --value file:///dev/stdin \
        --overwrite

echo "✅ Certificate backed up to $SSM_PATH"

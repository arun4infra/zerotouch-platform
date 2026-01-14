#!/bin/bash
# scripts/bootstrap/helpers/restore-gateway-cert.sh
# Restores TLS certificate from SSM to avoid Let's Encrypt rate limits

set -e

ENV="prod"
SECRET_NAME="nutgraf-tls-cert"
NAMESPACE="kube-system"
SSM_PATH="/zerotouch/${ENV}/gateway/tls-cert"

echo "Checking for existing TLS certificate backup..."

# 1. Check if parameter exists
if aws ssm get-parameter --name "$SSM_PATH" &>/dev/null; then
    echo "Found backup in SSM. Restoring..."
    
    # 2. Fetch and Decode
    CERT_DATA=$(aws ssm get-parameter --name "$SSM_PATH" --with-decryption --query "Parameter.Value" --output text)
    
    # 3. Inject into Cluster
    # We use 'apply' so it doesn't fail if it exists
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $NAMESPACE
  labels:
    controller.cert-manager.io/fao: "true"
type: kubernetes.io/tls
data:
$(echo "$CERT_DATA" | jq -r '.data | to_entries | .[] | "  \(.key): \(.value)"')
EOF
    
    echo "✅ Certificate restored. Cert-Manager will skip issuance."
else
    echo "ℹ️  No backup found. Cert-Manager will issue a new certificate."
fi

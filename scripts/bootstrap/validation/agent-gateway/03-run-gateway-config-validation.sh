#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Cleanup function to always delete the job
cleanup() {
    echo "Cleaning up..."
    kubectl delete job validate-gateway-config -n platform-agent-gateway --ignore-not-found=true
}

# Set trap to cleanup on exit (success or failure)
trap cleanup EXIT

echo "Building validation image..."
docker build -t validation-gateway-config:latest .

echo "Loading image into cluster..."
kind load docker-image validation-gateway-config:latest --name zerotouch-preview

echo "Cleaning up any existing job..."
kubectl delete job validate-gateway-config -n platform-agent-gateway --ignore-not-found=true

echo "Applying validation job..."
kubectl apply -f 03-gateway-config-validation-job.yaml

echo "Waiting for job to complete..."
if kubectl wait --for=condition=complete job/validate-gateway-config -n platform-agent-gateway --timeout=120s; then
    echo "Job completed successfully"
elif kubectl wait --for=condition=failed job/validate-gateway-config -n platform-agent-gateway --timeout=10s; then
    echo "Job failed"
else
    echo "Job status unknown"
fi

echo "Getting job results..."
kubectl logs job/validate-gateway-config -n platform-agent-gateway
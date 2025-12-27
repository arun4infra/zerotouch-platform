#!/bin/bash
set -euo pipefail

# ==============================================================================
# IDE Orchestrator Dependency Setup Script
# ==============================================================================
# Purpose: Setup DeepAgents Runtime service for IDE Orchestrator testing
# Called by: GitHub Actions workflow before IDE Orchestrator deployment
# Usage: ./setup-dependencies.sh
#
# This script:
# 1. Clones deepagents-runtime repository
# 2. Builds and deploys actual deepagents-runtime service
# 3. Uses deepagents-runtime's own validation scripts internally
# 4. Ensures intelligence-deepagents namespace and service are available
# ==============================================================================

# Configuration
DEEPAGENTS_REPO="https://github.com/arun4infra/deepagents-runtime.git"
DEEPAGENTS_DIR="/tmp/deepagents-runtime"
DEEPAGENTS_NAMESPACE="intelligence-deepagents"
DEEPAGENTS_IMAGE_TAG="ci-test"
KIND_CLUSTER_NAME="zerotouch-preview"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[SETUP-DEPS]${NC} $*"; }
log_success() { echo -e "${GREEN}[SETUP-DEPS]${NC} $*"; }
log_error() { echo -e "${RED}[SETUP-DEPS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[SETUP-DEPS]${NC} $*"; }

echo "================================================================================"
echo "Setting up DeepAgents Runtime Dependency for IDE Orchestrator Testing"
echo "================================================================================"
echo "  Target Namespace: ${DEEPAGENTS_NAMESPACE}"
echo "  Image Tag:        ${DEEPAGENTS_IMAGE_TAG}"
echo "  Kind Cluster:     ${KIND_CLUSTER_NAME}"
echo "================================================================================"

# Step 1: Clone deepagents-runtime repository
log_info "Cloning deepagents-runtime repository..."
if [ -d "${DEEPAGENTS_DIR}" ]; then
    log_warn "Removing existing deepagents-runtime directory..."
    rm -rf "${DEEPAGENTS_DIR}"
fi

git clone "${DEEPAGENTS_REPO}" "${DEEPAGENTS_DIR}"
cd "${DEEPAGENTS_DIR}"

log_success "DeepAgents Runtime repository cloned to ${DEEPAGENTS_DIR}"

# Step 2: Build deepagents-runtime Docker image
log_info "Building deepagents-runtime Docker image..."
docker build -t deepagents-runtime:${DEEPAGENTS_IMAGE_TAG} .

# Step 3: Load image into Kind cluster
log_info "Loading deepagents-runtime image into Kind cluster..."
kind load docker-image deepagents-runtime:${DEEPAGENTS_IMAGE_TAG} --name ${KIND_CLUSTER_NAME}

log_success "DeepAgents Runtime image loaded into Kind cluster"

# Step 4: Apply deepagents-runtime preview patches (following deepagents-runtime workflow pattern)
log_info "Applying deepagents-runtime preview patches..."
chmod +x scripts/patches/00-apply-all-patches.sh
./scripts/patches/00-apply-all-patches.sh --force

# Step 5: Run deepagents-runtime pre-deploy diagnostics
log_info "Running deepagents-runtime pre-deploy diagnostics..."
chmod +x scripts/ci/pre-deploy-diagnostics.sh
./scripts/ci/pre-deploy-diagnostics.sh

# Step 6: Deploy deepagents-runtime service
log_info "Deploying deepagents-runtime service..."
export IMAGE_TAG=${DEEPAGENTS_IMAGE_TAG}
export NAMESPACE=${DEEPAGENTS_NAMESPACE}

chmod +x scripts/ci/deploy.sh
./scripts/ci/deploy.sh preview

# Step 7: Run deepagents-runtime post-deploy diagnostics
log_info "Running deepagents-runtime post-deploy diagnostics..."
chmod +x scripts/ci/post-deploy-diagnostics.sh
./scripts/ci/post-deploy-diagnostics.sh ${DEEPAGENTS_NAMESPACE} deepagents-runtime

# Step 8: Verify service is accessible
log_info "Verifying deepagents-runtime service accessibility..."

# Wait for service to be ready
log_info "Waiting for deepagents-runtime service to be ready..."
kubectl wait deployment/deepagents-runtime \
    -n ${DEEPAGENTS_NAMESPACE} \
    --for=condition=Available \
    --timeout=300s

# Test service endpoint
log_info "Testing deepagents-runtime service endpoint..."
SERVICE_IP=$(kubectl get svc deepagents-runtime -n ${DEEPAGENTS_NAMESPACE} -o jsonpath='{.spec.clusterIP}')
SERVICE_PORT=$(kubectl get svc deepagents-runtime -n ${DEEPAGENTS_NAMESPACE} -o jsonpath='{.spec.ports[0].port}')

log_info "Service endpoint: http://${SERVICE_IP}:${SERVICE_PORT}"

# Test readiness endpoint using a test pod
log_info "Testing /ready endpoint..."
kubectl run deepagents-test --image=curlimages/curl:latest --rm -i --restart=Never -- \
    curl -f -m 10 "http://${SERVICE_IP}:${SERVICE_PORT}/ready" || {
    log_error "DeepAgents Runtime readiness check failed!"
    
    # Debug information
    echo ""
    echo "=== DEEPAGENTS RUNTIME DEBUG INFO ==="
    echo "Service details:"
    kubectl get svc deepagents-runtime -n ${DEEPAGENTS_NAMESPACE} -o wide
    echo ""
    echo "Pod status:"
    kubectl get pods -n ${DEEPAGENTS_NAMESPACE} -l app.kubernetes.io/name=deepagents-runtime -o wide
    echo ""
    echo "Recent logs:"
    kubectl logs -n ${DEEPAGENTS_NAMESPACE} -l app.kubernetes.io/name=deepagents-runtime --tail=20
    echo ""
    
    exit 1
}

log_success "DeepAgents Runtime service is ready and accessible"

# Step 9: Validate platform dependencies (using ide-orchestrator's validation script)
log_info "Running platform dependency validation..."
# Return to the original directory (ide-orchestrator) to run validation
cd - > /dev/null
"./scripts/ci/validate-platform-dependencies.sh" || {
    log_error "Platform dependency validation failed!"
    echo ""
    echo "This means deepagents-runtime may not be properly accessible from ide-orchestrator's perspective."
    echo "Check the validation output above for specific issues."
    exit 1
}

log_success "Platform dependency validation passed"

# Step 10: Final validation summary
echo ""
echo "================================================================================"
echo "DEEPAGENTS RUNTIME DEPENDENCY SETUP COMPLETE"
echo "================================================================================"
echo "  Namespace:        ${DEEPAGENTS_NAMESPACE}"
echo "  Service:          deepagents-runtime"
echo "  Endpoint:         http://${SERVICE_IP}:${SERVICE_PORT}"
echo ""
echo "Service Status:"
kubectl get deployment,pods,svc -n ${DEEPAGENTS_NAMESPACE} -l app.kubernetes.io/name=deepagents-runtime
echo ""
echo "Dependencies:"
kubectl get pods -n ${DEEPAGENTS_NAMESPACE} -l 'app.kubernetes.io/name in (deepagents-runtime-db,deepagents-runtime-cache)'
echo ""
echo "✅ DeepAgents Runtime is ready for IDE Orchestrator testing"
echo "================================================================================"

# Cleanup temporary directory
log_info "Cleaning up temporary files..."
cd /
rm -rf "${DEEPAGENTS_DIR}"

log_success "Dependency setup completed successfully"
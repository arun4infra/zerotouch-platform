#!/bin/bash
set -euo pipefail

# ==============================================================================
# Shared In-Cluster Test Script
# ==============================================================================
# Purpose: Mimics zerotouch-platform/.github/workflows/in-cluster-test.yml exactly
# Usage: ./in-cluster-test.sh --service=<name> --test-path=<path> --test-name=<name> [options]
# 
# This script replicates the exact same steps and order as the centralized workflow
# ==============================================================================

# Default values (matching workflow defaults)
SERVICE_NAME="ide-orchestrator"
TEST_PATH=""
TEST_NAME=""
TIMEOUT=600
IMAGE_TAG="ci-test"
NAMESPACE="intelligence-orchestrator"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[IN-CLUSTER-TEST]${NC} $*"; }
log_success() { echo -e "${GREEN}[IN-CLUSTER-TEST]${NC} $*"; }
log_error() { echo -e "${RED}[IN-CLUSTER-TEST]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[IN-CLUSTER-TEST]${NC} $*"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --service=*)
            SERVICE_NAME="${1#*=}"
            shift
            ;;
        --test-path=*)
            TEST_PATH="${1#*=}"
            shift
            ;;
        --test-name=*)
            TEST_NAME="${1#*=}"
            shift
            ;;
        --timeout=*)
            TIMEOUT="${1#*=}"
            shift
            ;;
        --image-tag=*)
            IMAGE_TAG="${1#*=}"
            shift
            ;;
        --namespace=*)
            NAMESPACE="${1#*=}"
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Usage: $0 --service=<name> --test-path=<path> --test-name=<name> [--timeout=<seconds>] [--image-tag=<tag>] [--namespace=<ns>]"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$TEST_PATH" ]]; then
    log_error "Test path is required. Use --test-path=<path>"
    exit 1
fi

if [[ -z "$TEST_NAME" ]]; then
    log_error "Test name is required. Use --test-name=<name>"
    exit 1
fi

# Get script directory and determine paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

echo "================================================================================"
echo "Shared In-Cluster Test Script (Mimics GitHub Workflow)"
echo "================================================================================"
echo "  Service:    ${SERVICE_NAME}"
echo "  Test Path:  ${TEST_PATH}"
echo "  Test Name:  ${TEST_NAME}"
echo "  Timeout:    ${TIMEOUT}s"
echo "  Image Tag:  ${IMAGE_TAG}"
echo "  Namespace:  ${NAMESPACE}"
echo "================================================================================"

# Export environment variables for scripts
export SERVICE_NAME="${SERVICE_NAME}"
export IMAGE_TAG="${IMAGE_TAG}"
export NAMESPACE="${NAMESPACE}"
export TEST_PATH="${TEST_PATH}"
export TEST_NAME="${TEST_NAME}"
export TIMEOUT="${TIMEOUT}"
export JWT_SECRET="test-secret-key-for-ci-testing"

# Cleanup function (matches workflow cleanup step)
cleanup() {
    log_info "Cleanup: Getting logs from failed pods for debugging..."
    if kubectl get pods -n "${NAMESPACE}" -l test-suite="${TEST_NAME}" --field-selector=status.phase=Failed -o name 2>/dev/null | grep -q .; then
        echo "=== Failed Pod Logs ==="
        kubectl get pods -n "${NAMESPACE}" -l test-suite="${TEST_NAME}" --field-selector=status.phase=Failed -o name | while read pod; do
            echo "--- Logs for $pod ---"
            kubectl logs "$pod" -n "${NAMESPACE}" || true
        done
    fi
    
    log_info "Cleanup: Cleaning up test jobs..."
    kubectl delete jobs -n "${NAMESPACE}" -l test-suite="${TEST_NAME}" --ignore-not-found=true || true
    
    log_info "Cleanup: Cleaning up Kind cluster..."
    kind delete cluster --name zerotouch-preview || true
}

# Error handler
error_handler() {
    local exit_code=$?
    local line_number=$1
    log_error "Script failed at line $line_number with exit code $exit_code"
    log_error "Last command: $BASH_COMMAND"
    cleanup
    exit $exit_code
}

trap 'error_handler $LINENO' ERR
trap cleanup EXIT

# Step 1: Checkout repository (simulated - we're already in the repo)
log_info "Step 1: Checkout repository (already in repository)"

# Step 2: Checkout zerotouch-platform (simulated - we're already in platform)
log_info "Step 2: Checkout zerotouch-platform (already in platform)"

# Step 3: Configure AWS credentials (skip for local - assume already configured)
log_info "Step 3: Configure AWS credentials (assuming already configured locally)"

# Step 4: Set up Docker Buildx (skip for local - assume Docker is available)
log_info "Step 4: Set up Docker Buildx (assuming Docker is available locally)"

# Step 5: Setup Platform Environment
log_info "Step 5: Setup Platform Environment"
if [[ -f "${SCRIPT_DIR}/setup-platform-environment.sh" ]]; then
    chmod +x "${SCRIPT_DIR}/setup-platform-environment.sh"
    "${SCRIPT_DIR}/setup-platform-environment.sh" --service="${SERVICE_NAME}" --image-tag="${IMAGE_TAG}"
else
    log_error "Platform setup script not found: ${SCRIPT_DIR}/setup-platform-environment.sh"
    exit 1
fi

# Step 6: Bootstrap platform
log_info "Step 6: Bootstrap platform"
cd "${PLATFORM_ROOT}"
if [[ -f "scripts/bootstrap/01-master-bootstrap.sh" ]]; then
    chmod +x scripts/bootstrap/01-master-bootstrap.sh
    ./scripts/bootstrap/01-master-bootstrap.sh --mode preview
else
    log_error "Master bootstrap script not found: scripts/bootstrap/01-master-bootstrap.sh"
    exit 1
fi

# Return to service directory (assuming we're running from service root)
cd - > /dev/null

# Step 7: Apply preview patches
log_info "Step 7: Apply preview patches"
if [[ -f "${SCRIPT_DIR}/00-apply-all-patches.sh" ]]; then
    chmod +x "${SCRIPT_DIR}/00-apply-all-patches.sh"
    "${SCRIPT_DIR}/00-apply-all-patches.sh" --force
else
    log_error "Preview patches script not found: ${SCRIPT_DIR}/00-apply-all-patches.sh"
    exit 1
fi

# Step 8: Setup dependencies
log_info "Step 8: Setup dependencies"
if [[ -f "${SCRIPT_DIR}/setup-dependencies.sh" ]]; then
    chmod +x "${SCRIPT_DIR}/setup-dependencies.sh"
    "${SCRIPT_DIR}/setup-dependencies.sh"
else
    log_error "Setup dependencies script not found: ${SCRIPT_DIR}/setup-dependencies.sh"
    exit 1
fi

# Step 9: Run pre-deploy diagnostics
log_info "Step 9: Run pre-deploy diagnostics"
if [[ -f "${SCRIPT_DIR}/pre-deploy-diagnostics.sh" ]]; then
    chmod +x "${SCRIPT_DIR}/pre-deploy-diagnostics.sh"
    "${SCRIPT_DIR}/pre-deploy-diagnostics.sh"
else
    log_error "Pre-deploy diagnostics script not found: ${SCRIPT_DIR}/pre-deploy-diagnostics.sh"
    exit 1
fi

# Step 10: Validate platform dependencies
log_info "Step 10: Validate platform dependencies"
if [[ -f "${SCRIPT_DIR}/validate-platform-dependencies.sh" ]]; then
    chmod +x "${SCRIPT_DIR}/validate-platform-dependencies.sh"
    "${SCRIPT_DIR}/validate-platform-dependencies.sh"
else
    log_error "Validate platform dependencies script not found: ${SCRIPT_DIR}/validate-platform-dependencies.sh"
    exit 1
fi

# Step 11: Deploy service
log_info "Step 11: Deploy service"
if [[ -f "${SCRIPT_DIR}/deploy.sh" ]]; then
    chmod +x "${SCRIPT_DIR}/deploy.sh"
    "${SCRIPT_DIR}/deploy.sh"
else
    log_error "Deploy script not found: ${SCRIPT_DIR}/deploy.sh"
    exit 1
fi

# Step 12: Run database migrations
log_info "Step 12: Run database migrations"
if [[ -f "${SCRIPT_DIR}/run-migrations.sh" ]]; then
    chmod +x "${SCRIPT_DIR}/run-migrations.sh"
    "${SCRIPT_DIR}/run-migrations.sh" "${NAMESPACE}"
else
    log_error "Migration script not found: ${SCRIPT_DIR}/run-migrations.sh"
    exit 1
fi

# Step 13: Run post-deploy diagnostics
log_info "Step 13: Run post-deploy diagnostics"
if [[ -f "${SCRIPT_DIR}/post-deploy-diagnostics.sh" ]]; then
    chmod +x "${SCRIPT_DIR}/post-deploy-diagnostics.sh"
    "${SCRIPT_DIR}/post-deploy-diagnostics.sh" "${NAMESPACE}" "${SERVICE_NAME}"
else
    log_error "Post-deploy diagnostics script not found: ${SCRIPT_DIR}/post-deploy-diagnostics.sh"
    exit 1
fi

# Step 14: Run in-cluster tests
log_info "Step 14: Run in-cluster tests"
if [[ -f "${SCRIPT_DIR}/run-test-job.sh" ]]; then
    chmod +x "${SCRIPT_DIR}/run-test-job.sh"
    if "${SCRIPT_DIR}/run-test-job.sh" "${TEST_PATH}" "${TEST_NAME}" "${TIMEOUT}" "${NAMESPACE}" "${IMAGE_TAG}"; then
        log_success "✅ In-cluster tests completed successfully!"
    else
        log_error "❌ In-cluster tests failed!"
        exit 1
    fi
else
    log_error "Test job script not found: ${SCRIPT_DIR}/run-test-job.sh"
    exit 1
fi

# Step 15: Comment PR with test results (skip for local)
log_info "Step 15: Comment PR with test results (skipped for local execution)"

# Step 16: Cleanup (handled by trap)
log_info "Step 16: Cleanup (will be handled by trap on exit)"

echo ""
echo "================================================================================"
echo "SHARED IN-CLUSTER TEST COMPLETE"
echo "================================================================================"
log_success "✅ All workflow steps completed successfully!"
echo "  Service:    ${SERVICE_NAME}"
echo "  Test:       ${TEST_NAME}"
echo "  Result:     PASSED"
echo ""
echo "This script exactly mimicked the GitHub workflow steps in the same order."
echo "================================================================================"
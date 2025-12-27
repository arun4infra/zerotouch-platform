#!/bin/bash
set -euo pipefail

# ==============================================================================
# Platform Environment Setup Orchestrator
# ==============================================================================
# Purpose: Orchestrates platform setup by calling existing moved scripts
# Usage: ./setup-platform-environment.sh --service=<service-name> [--image-tag=<tag>]
# ==============================================================================

# Default values
SERVICE_NAME=""
IMAGE_TAG="ci-test"
BUILD_MODE="test"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[ORCHESTRATOR]${NC} $*"; }
log_success() { echo -e "${GREEN}[ORCHESTRATOR]${NC} $*"; }
log_error() { echo -e "${RED}[ORCHESTRATOR]${NC} $*"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --service=*)
            SERVICE_NAME="${1#*=}"
            shift
            ;;
        --image-tag=*)
            IMAGE_TAG="${1#*=}"
            shift
            ;;
        --build-mode=*)
            BUILD_MODE="${1#*=}"
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Usage: $0 --service=<service-name> [--image-tag=<tag>] [--build-mode=<mode>]"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SERVICE_NAME" ]]; then
    log_error "Service name is required. Use --service=<service-name>"
    exit 1
fi

echo "================================================================================"
echo "Platform Environment Setup Orchestrator"
echo "================================================================================"
echo "  Service:    ${SERVICE_NAME}"
echo "  Image Tag:  ${IMAGE_TAG}"
echo "  Build Mode: ${BUILD_MODE}"
echo "================================================================================"

# Ensure all platform scripts have execute permissions
log_info "Setting execute permissions on all platform scripts..."
find "${SCRIPT_DIR}" -name "*.sh" -type f -exec chmod +x {} \;
find "${SCRIPT_DIR}/../patches" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
find "${SCRIPT_DIR}/../../../.." -name "*.sh" -path "*/zerotouch-platform/*" -type f -exec chmod +x {} \; 2>/dev/null || true
log_info "Execute permissions set on all platform scripts"

# Install required tools
log_info "Installing required tools..."
if ! command -v yq &> /dev/null; then
    log_info "Installing yq..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install yq
        else
            curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_darwin_amd64 -o /tmp/yq
            chmod +x /tmp/yq
            sudo mv /tmp/yq /usr/local/bin/yq
        fi
    else
        # Linux
        curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /tmp/yq
        chmod +x /tmp/yq
        sudo mv /tmp/yq /usr/local/bin/yq
    fi
    log_success "yq installed successfully"
else
    log_info "yq is already installed"
fi

# Step 1: Setup Kind cluster first (before building image)
log_info "Step 1: Setting up Kind cluster..."

# Clean up existing cluster first
log_info "Cleaning up existing cluster..."
kind delete cluster --name zerotouch-preview || true

if ! command -v kind &> /dev/null; then
    echo "Installing kind..."
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
fi

mkdir -p /tmp/kind
cat > /tmp/kind/config.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: zerotouch-preview
nodes:
- role: control-plane
  extraPortMappings:
  # NATS client port
  - containerPort: 30080
    hostPort: 4222
    protocol: TCP
  # PostgreSQL port
  - containerPort: 30432
    hostPort: 5432
    protocol: TCP
  # DeepAgents Runtime port
  - containerPort: 30081
    hostPort: 8080
    protocol: TCP
  extraMounts:
  # Mount zerotouch-platform subdirectory for ArgoCD to sync from
  - hostPath: $(pwd)/zerotouch-platform
    containerPath: /repo
    readOnly: true
EOF

kind create cluster --config /tmp/kind/config.yaml
kubectl config use-context kind-zerotouch-preview
kubectl label nodes --all workload.bizmatters.dev/databases=true --overwrite

# Step 2: Build Docker image only (without loading into cluster)
log_info "Step 2: Building Docker image..."
export SERVICE_NAME="${SERVICE_NAME}"
export BUILD_ONLY=true
"${SCRIPT_DIR}/scripts/build.sh" --mode="${BUILD_MODE}"

# Step 3: Load Docker image into Kind cluster (now that cluster exists)
log_info "Step 3: Loading Docker image into Kind cluster..."
"${SCRIPT_DIR}/scripts/load-image-to-kind.sh" --service="${SERVICE_NAME}" --image-tag="${IMAGE_TAG}"

# Step 3: Apply platform patches
log_info "Step 3: Applying platform patches..."
cd "${SCRIPT_DIR}/../../../.."
"${SCRIPT_DIR}/scripts/apply-platform-patches.sh" apply
cd - > /dev/null

log_success "Platform environment setup complete for ${SERVICE_NAME}"
log_info "Next: Run Master Bootstrap Script as separate workflow step"
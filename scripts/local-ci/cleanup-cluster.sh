#!/bin/bash
# Cleanup Local CI Cluster
# Deletes the Kind cluster created for local integration testing
# Usage: ./scripts/local-ci/cleanup-cluster.sh [--force]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="zerotouch-preview"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
FORCE_CLEANUP=false
if [ "$1" = "--force" ]; then
    FORCE_CLEANUP=true
fi

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}==>${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Cleanup Local CI Cluster                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
log_step "Step 1/4: Checking prerequisites..."

if ! command_exists kind; then
    log_error "kind is not installed"
    echo "Please install kind: https://kind.sigs.k8s.io/docs/user/quick-start/"
    exit 1
fi

if ! command_exists docker; then
    log_error "docker is not installed or not running"
    echo "Please install and start Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

log_info "✓ Prerequisites available"

# Check if cluster exists
log_step "Step 2/4: Checking cluster status..."

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    log_info "Found Kind cluster: $CLUSTER_NAME"
    
    # Show cluster info
    echo ""
    echo "Cluster information:"
    kind get nodes --name "$CLUSTER_NAME" 2>/dev/null || true
    echo ""
    
    if [ "$FORCE_CLEANUP" = false ]; then
        echo -e "${YELLOW}This will delete the Kind cluster '$CLUSTER_NAME' and all its data.${NC}"
        echo -e "${YELLOW}Are you sure you want to continue? (y/N)${NC}"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
else
    log_warn "Kind cluster '$CLUSTER_NAME' not found"
    
    # Check if there are any containers with the cluster name
    if docker ps -a --filter "name=${CLUSTER_NAME}" --format "{{.Names}}" | grep -q "${CLUSTER_NAME}"; then
        log_warn "Found Docker containers with cluster name, will attempt cleanup"
    else
        log_info "No cleanup needed - cluster doesn't exist"
        exit 0
    fi
fi

# Delete the Kind cluster
log_step "Step 3/4: Deleting Kind cluster..."

if kind delete cluster --name "$CLUSTER_NAME"; then
    log_info "✓ Kind cluster '$CLUSTER_NAME' deleted successfully"
else
    log_error "Failed to delete Kind cluster"
    
    # Try to force cleanup Docker containers
    log_warn "Attempting to force cleanup Docker containers..."
    
    # Stop and remove containers
    CONTAINERS=$(docker ps -a --filter "name=${CLUSTER_NAME}" --format "{{.Names}}" || true)
    if [ -n "$CONTAINERS" ]; then
        echo "$CONTAINERS" | while read -r container; do
            log_info "Stopping container: $container"
            docker stop "$container" 2>/dev/null || true
            log_info "Removing container: $container"
            docker rm "$container" 2>/dev/null || true
        done
    fi
    
    # Remove networks
    NETWORKS=$(docker network ls --filter "name=${CLUSTER_NAME}" --format "{{.Name}}" || true)
    if [ -n "$NETWORKS" ]; then
        echo "$NETWORKS" | while read -r network; do
            log_info "Removing network: $network"
            docker network rm "$network" 2>/dev/null || true
        done
    fi
fi

# Clean up any remaining Docker resources
log_step "Step 4/4: Cleaning up Docker resources..."

# Remove any dangling volumes related to the cluster
VOLUMES=$(docker volume ls --filter "name=${CLUSTER_NAME}" --format "{{.Name}}" 2>/dev/null || true)
if [ -n "$VOLUMES" ]; then
    echo "$VOLUMES" | while read -r volume; do
        log_info "Removing volume: $volume"
        docker volume rm "$volume" 2>/dev/null || true
    done
fi

# Clean up any dangling images (optional)
if [ "$FORCE_CLEANUP" = true ]; then
    log_info "Cleaning up dangling Docker images..."
    docker image prune -f >/dev/null 2>&1 || true
fi

# Verify cleanup
log_info "Verifying cleanup..."

# Check if cluster still exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    log_error "Cluster still exists after cleanup attempt"
    exit 1
fi

# Check for remaining containers
REMAINING_CONTAINERS=$(docker ps -a --filter "name=${CLUSTER_NAME}" --format "{{.Names}}" 2>/dev/null || true)
if [ -n "$REMAINING_CONTAINERS" ]; then
    log_warn "Some containers may still exist:"
    echo "$REMAINING_CONTAINERS"
else
    log_info "✓ No remaining containers found"
fi

# Check kubectl context
if kubectl config current-context 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
    log_warn "kubectl context still points to deleted cluster"
    log_info "You may want to switch context: kubectl config use-context <other-context>"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    ✓ Cleanup Completed                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

log_info "Kind cluster '$CLUSTER_NAME' has been cleaned up"
log_info "You can now run the integration test again with a fresh cluster"

# Show remaining Kind clusters
REMAINING_CLUSTERS=$(kind get clusters 2>/dev/null || true)
if [ -n "$REMAINING_CLUSTERS" ]; then
    echo ""
    log_info "Remaining Kind clusters:"
    echo "$REMAINING_CLUSTERS"
else
    log_info "No Kind clusters remaining"
fi
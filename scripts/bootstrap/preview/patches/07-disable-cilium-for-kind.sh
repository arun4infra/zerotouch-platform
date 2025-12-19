#!/bin/bash
# Disable Cilium for Kind clusters (use Kind's default CNI instead)
# Kind clusters work better with kindnet than Cilium for port-forward stability

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Find repository root by looking for .git directory
PLATFORM_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR" && while [[ ! -d .git && $(pwd) != "/" ]]; do cd ..; done; pwd))"

FORCE_UPDATE=false

# Parse arguments
if [ "$1" = "--force" ]; then
    FORCE_UPDATE=true
fi

# Check if this is Kind cluster
IS_KIND_CLUSTER=false

if [ "$FORCE_UPDATE" = true ]; then
    IS_KIND_CLUSTER=true
elif command -v kubectl > /dev/null 2>&1 && kubectl cluster-info > /dev/null 2>&1; then
    # Check if running on Kind cluster (no control-plane taints on nodes)
    if ! kubectl get nodes -o jsonpath='{.items[*].spec.taints[?(@.key=="node-role.kubernetes.io/control-plane")]}' 2>/dev/null | grep -q "control-plane"; then
        IS_KIND_CLUSTER=true
    fi
fi

if [ "$IS_KIND_CLUSTER" = true ]; then
    echo -e "${YELLOW}NOTE: This script is now deprecated.${NC}"
    echo -e "${BLUE}Cilium exclusion is now handled by Kustomize overlays:${NC}"
    echo -e "${BLUE}  - bootstrap/argocd/overlays/preview/kustomization.yaml excludes cilium.yaml${NC}"
    echo -e "${BLUE}  - bootstrap/argocd/overlays/production includes Cilium in overlays/production/cilium/${NC}"
    echo -e "${GREEN}✓ No action needed - overlay structure handles Cilium exclusion${NC}"
    echo -e "${BLUE}  Kind clusters use kindnet CNI instead${NC}"
else
    echo -e "${YELLOW}Not a Kind cluster - Cilium will be deployed via production overlay${NC}"
fi

exit 0
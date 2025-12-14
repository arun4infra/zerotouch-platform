#!/bin/bash
# Exclude Local Path Provisioner in Preview Mode
# Kind clusters already have local-path storage built-in
# Deploying via ArgoCD causes StorageClass conflicts

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

FORCE_UPDATE=false

# Parse arguments
if [ "$1" = "--force" ]; then
    FORCE_UPDATE=true
fi

# Check if this is preview mode
IS_PREVIEW_MODE=false

if [ "$FORCE_UPDATE" = true ]; then
    IS_PREVIEW_MODE=true
elif command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    if ! kubectl get nodes -o jsonpath='{.items[*].spec.taints[?(@.key=="node-role.kubernetes.io/control-plane")]}' 2>/dev/null | grep -q "control-plane"; then
        IS_PREVIEW_MODE=true
    fi
fi

if [ "$IS_PREVIEW_MODE" = true ]; then
    echo -e "${BLUE}Excluding local-path-provisioner from preview mode...${NC}"
    
    ROOT_YAML="$REPO_ROOT/bootstrap/root.yaml"
    
    if [ ! -f "$ROOT_YAML" ]; then
        echo -e "${RED}Error: root.yaml not found at $ROOT_YAML${NC}"
        exit 1
    fi
    
    # Add exclude pattern for 00-local-path-provisioner.yaml
    # Kind already provides local-path storage
    if ! grep -q "exclude:" "$ROOT_YAML" 2>/dev/null; then
        # No exclude pattern exists, add it after include line
        sed -i.bak "/include:/a\\
      exclude: '00-local-path-provisioner.yaml'" "$ROOT_YAML"
        rm -f "$ROOT_YAML.bak"
        echo -e "  ${GREEN}✓${NC} Added exclude pattern for local-path-provisioner"
    elif ! grep -q "exclude:.*00-local-path-provisioner" "$ROOT_YAML" 2>/dev/null; then
        # Exclude exists but doesn't include local-path-provisioner
        sed -i.bak "s/exclude: '\(.*\)'/exclude: '\1|00-local-path-provisioner.yaml'/" "$ROOT_YAML"
        rm -f "$ROOT_YAML.bak"
        echo -e "  ${GREEN}✓${NC} Updated exclude pattern to include local-path-provisioner"
    else
        echo -e "  ${YELLOW}⊘${NC} local-path-provisioner already excluded"
    fi
    
    # Verify the change
    echo -e "${BLUE}Verifying local-path-provisioner exclusion...${NC}"
    if grep -q "exclude:.*00-local-path-provisioner" "$ROOT_YAML" 2>/dev/null; then
        echo -e "  ${GREEN}✓ root.yaml verified - local-path-provisioner excluded${NC}"
        grep -n "exclude:" "$ROOT_YAML" || true
    else
        echo -e "  ${RED}✗ Failed to exclude local-path-provisioner!${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Local-path-provisioner excluded from preview mode${NC}"
fi

exit 0

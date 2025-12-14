#!/bin/bash
# Exclude Tenants in Preview Mode
# Removes tenant applications (11-*) from root.yaml include pattern in preview mode
# Tenants require production secrets that don't exist in preview environments

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
    echo -e "${BLUE}Excluding tenant applications from preview mode...${NC}"
    
    ROOT_YAML="$REPO_ROOT/bootstrap/root.yaml"
    
    if [ ! -f "$ROOT_YAML" ]; then
        echo -e "${RED}Error: root.yaml not found at $ROOT_YAML${NC}"
        exit 1
    fi
    
    # Update include pattern to exclude 11-* (tenant applications)
    # Change from: include: '{00-*,10-*,11-*}.yaml'
    # To:          include: '{00-*,10-*}.yaml'
    if grep -q "include:.*11-\*" "$ROOT_YAML" 2>/dev/null; then
        sed -i.bak "s/include: '{00-\*,10-\*,11-\*}\.yaml'/include: '{00-*,10-*}.yaml'/" "$ROOT_YAML"
        rm -f "$ROOT_YAML.bak"
        echo -e "  ${GREEN}✓${NC} Excluded 11-* (tenants) from root.yaml"
    else
        echo -e "  ${YELLOW}⊘${NC} root.yaml already excludes tenants or pattern not found"
    fi
    
    # Verify the change
    echo -e "${BLUE}Verifying tenant exclusion...${NC}"
    if grep -q "include:.*11-\*" "$ROOT_YAML" 2>/dev/null; then
        echo -e "  ${RED}✗ root.yaml still includes 11-* pattern!${NC}"
        grep -n "include:" "$ROOT_YAML" || true
        exit 1
    else
        echo -e "  ${GREEN}✓ root.yaml verified - tenants excluded${NC}"
        grep -n "include:" "$ROOT_YAML" || true
    fi
    
    echo -e "${GREEN}✓ Tenant applications excluded from preview mode${NC}"
fi

exit 0

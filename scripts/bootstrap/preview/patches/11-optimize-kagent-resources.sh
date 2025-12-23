#!/bin/bash
# Optimize Kagent resources for preview mode
# Disables Kagent completely for preview environments (not needed for testing)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Find repository root by looking for .git directory
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR" && while [[ ! -d .git && $(pwd) != "/" ]]; do cd ..; done; pwd))"

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
    echo -e "${BLUE}Optimizing Kagent resources for preview mode...${NC}"
    
    # Find Kagent ArgoCD application file
    KAGENT_FILE="$REPO_ROOT/bootstrap/argocd/base/01-kagent.yaml"
    
    if [ -f "$KAGENT_FILE" ]; then
        echo -e "${BLUE}Processing: $(basename "$KAGENT_FILE")${NC}"
        
        # Disable Kagent for preview mode by setting enabled: false in helm values
        if grep -q "kmcp:" "$KAGENT_FILE" 2>/dev/null; then
            # Add agents.enabled: false to disable all agents
            sed -i.bak '/kmcp:/i\        agents:\n          enabled: false\n          replicas: 0' "$KAGENT_FILE"
            rm -f "$KAGENT_FILE.bak"
            echo -e "  ${GREEN}✓${NC} Kagent: disabled all agents for preview"
        fi
        
        echo -e "${GREEN}✓ Kagent optimization complete${NC}"
        echo -e "${BLUE}  Kagent agents disabled for preview (saves ~500m CPU, ~1Gi memory)${NC}"
    else
        echo -e "${YELLOW}⚠${NC} Kagent file not found: $KAGENT_FILE"
    fi
else
    echo -e "${YELLOW}⊘${NC} Not in preview mode, skipping Kagent optimization"
fi

exit 0
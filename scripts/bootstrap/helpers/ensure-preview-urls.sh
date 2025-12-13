#!/bin/bash
# Ensure Preview URLs Helper
# Ensures ArgoCD applications use local filesystem URLs in preview mode
# Can be called with --force to skip cluster detection

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

FORCE_UPDATE=false

# Parse arguments
if [ "$1" = "--force" ]; then
    FORCE_UPDATE=true
fi

# Check if this is preview mode (either forced or Kind cluster detected)
IS_PREVIEW_MODE=false

if [ "$FORCE_UPDATE" = true ]; then
    IS_PREVIEW_MODE=true
elif command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    # Check if this is a Kind cluster (no control-plane taints)
    if ! kubectl get nodes -o jsonpath='{.items[*].spec.taints[?(@.key=="node-role.kubernetes.io/control-plane")]}' 2>/dev/null | grep -q "control-plane"; then
        IS_PREVIEW_MODE=true
    fi
fi

if [ "$IS_PREVIEW_MODE" = true ]; then
    echo -e "${BLUE}Updating ArgoCD manifests to use local filesystem...${NC}"
    
    GITHUB_URL="https://github.com/arun4infra/zerotouch-platform.git"
    LOCAL_URL="file:///repo"
    
    # Update URLs in bootstrap files
    for file in "$REPO_ROOT"/bootstrap/*.yaml "$REPO_ROOT"/bootstrap/components/*.yaml "$REPO_ROOT"/bootstrap/components-tenants/*.yaml; do
        if [ -f "$file" ]; then
            if grep -q "$GITHUB_URL" "$file" 2>/dev/null; then
                sed -i.bak "s|$GITHUB_URL|$LOCAL_URL|g" "$file"
                rm -f "$file.bak"
                echo -e "  ${GREEN}✓${NC} Updated: $(basename "$file")"
            fi
        fi
    done
    
    # Also remove targetRevision since local files don't have branches
    for file in "$REPO_ROOT"/bootstrap/*.yaml "$REPO_ROOT"/bootstrap/components/*.yaml "$REPO_ROOT"/bootstrap/components-tenants/*.yaml; do
        if [ -f "$file" ]; then
            if grep -q "targetRevision:" "$file" 2>/dev/null; then
                sed -i.bak '/targetRevision:/d' "$file"
                rm -f "$file.bak"
            fi
        fi
    done
    
    echo -e "${GREEN}✓ ArgoCD manifests updated for local filesystem sync${NC}"
fi

exit 0
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
    echo -e "${BLUE}Excluding local-path-provisioner from preview mode...${NC}"
    
    # With overlay structure, 00-* files should stay in bootstrap root, not in base/
    # Ensure local-path-provisioner application is disabled
    LOCAL_PATH_APP="$REPO_ROOT/bootstrap/argocd/bootstrap-files/00-local-path-provisioner.yaml"
    LOCAL_PATH_DISABLED="$REPO_ROOT/bootstrap/argocd/bootstrap-files/00-local-path-provisioner.yaml.disabled"
    
    if [ -f "$LOCAL_PATH_APP" ]; then
        mv "$LOCAL_PATH_APP" "$LOCAL_PATH_DISABLED"
        echo -e "  ${GREEN}✓${NC} Disabled: 00-local-path-provisioner.yaml"
    elif [ -f "$LOCAL_PATH_DISABLED" ]; then
        echo -e "  ${GREEN}✓${NC} Already disabled: 00-local-path-provisioner.yaml"
    else
        echo -e "  ${BLUE}ℹ${NC} No local-path-provisioner application found"
    fi
    
    # Ensure no 00-* files leak into base/ directory (overlays don't include them)
    ZERO_FILES_IN_BASE=$(find "$REPO_ROOT/bootstrap/argocd/base/" -name "00-*.yaml" 2>/dev/null || true)
    
    if [ -n "$ZERO_FILES_IN_BASE" ]; then
        echo -e "${YELLOW}⚠️  Found 00-* files in base directory - moving them:${NC}"
        for file in $ZERO_FILES_IN_BASE; do
            filename=$(basename "$file")
            mv "$file" "$REPO_ROOT/bootstrap/argocd/bootstrap-files/$filename"
            echo -e "  ${GREEN}✓${NC} Moved: $filename to bootstrap-files"
        done
    else
        echo -e "  ${GREEN}✓${NC} No 00-* files found in base directory"
    fi
    
    echo -e "  ${BLUE}ℹ${NC} Kind clusters use built-in local-path storage"
    echo -e "  ${BLUE}ℹ${NC} Preview overlay excludes 00-* bootstrap files"
    echo -e "${GREEN}✓ Local-path-provisioner excluded from preview mode${NC}"
fi

exit 0

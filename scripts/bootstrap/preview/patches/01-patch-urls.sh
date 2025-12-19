#!/bin/bash
# Ensure Preview URLs Helper
# Ensures ArgoCD applications use local filesystem URLs in preview mode
# Can be called with --force to skip cluster detection

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

echo -e "${BLUE}Script directory: $SCRIPT_DIR${NC}"
echo -e "${BLUE}Repository root: $REPO_ROOT${NC}"

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
    
    # Match any GitHub URL for zerotouch-platform
    GITHUB_URL_PATTERN="https://github.com/.*/zerotouch-platform.git"
    LOCAL_URL="file:///repo"
    
    # Update URLs in bootstrap files (base/ and production tenant components)
    for file in "$REPO_ROOT"/bootstrap/base/*.yaml "$REPO_ROOT"/bootstrap/overlays/production/components-tenants/*.yaml; do
        if [ -f "$file" ]; then
            if grep -qE "$GITHUB_URL_PATTERN" "$file" 2>/dev/null; then
                sed -i.bak -E "s|$GITHUB_URL_PATTERN|$LOCAL_URL|g" "$file"
                rm -f "$file.bak"
                echo -e "  ${GREEN}✓${NC} Updated: $(basename "$file")"
            fi
        fi
    done
    
    # Remove targetRevision ONLY for Git sources (not Helm charts)
    # Helm charts need targetRevision to specify chart version
    for file in "$REPO_ROOT"/bootstrap/base/*.yaml "$REPO_ROOT"/bootstrap/overlays/production/components-tenants/*.yaml; do
        if [ -f "$file" ]; then
            # Only remove targetRevision if this is a Git source (has repoURL with file:///repo)
            # Skip if it's a Helm chart (has 'chart:' field)
            if grep -q "file:///repo" "$file" 2>/dev/null && ! grep -q "^  chart:" "$file" 2>/dev/null; then
                if grep -q "targetRevision:" "$file" 2>/dev/null; then
                    sed -i.bak '/targetRevision:/d' "$file"
                    rm -f "$file.bak"
                fi
            fi
        fi
    done
    
    # Verify patches were applied
    echo -e "${BLUE}Verifying URL patches...${NC}"
    
    # List all files that still contain GitHub URL
    echo -e "${BLUE}Checking for remaining GitHub URLs...${NC}"
    REMAINING=$(grep -l "$GITHUB_URL_PATTERN" "$REPO_ROOT"/bootstrap/base/*.yaml "$REPO_ROOT"/bootstrap/overlays/production/components-tenants/*.yaml 2>/dev/null || true)
    if [ -n "$REMAINING" ]; then
        echo -e "  ${RED}✗ Files still containing GitHub URL:${NC}"
        echo "$REMAINING" | while read f; do echo "    - $(basename "$f")"; done
    else
        echo -e "  ${GREEN}✓ No files contain GitHub URL${NC}"
    fi
    
    echo -e "${GREEN}✓ ArgoCD manifests updated for local filesystem sync${NC}"
fi

exit 0
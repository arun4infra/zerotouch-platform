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
# Find repository root by looking for .git directory
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR" && while [[ ! -d .git && $(pwd) != "/" ]]; do cd ..; done; pwd))"

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
    # Detect if running in CI environment
    IS_CI=false
    if [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${CI:-}" ]; then
        IS_CI=true
        echo -e "${BLUE}Detected CI environment - using GitHub URL with commit SHA${NC}"
    else
        echo -e "${BLUE}Detected local environment - using local filesystem${NC}"
    fi
    
    # Get current commit SHA - more reliable than branch names
    CURRENT_COMMIT=$(cd "$REPO_ROOT" && git rev-parse HEAD 2>/dev/null || echo "")
    
    if [ -z "$CURRENT_COMMIT" ]; then
        echo -e "${RED}Error: Could not get current commit SHA${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Using commit SHA: $CURRENT_COMMIT${NC}"
    
    # Match any GitHub URL for zerotouch-platform
    GITHUB_URL_PATTERN="https://github.com/.*/zerotouch-platform.git"
    GITHUB_URL="https://github.com/arun4infra/zerotouch-platform.git"
    LOCAL_URL="file:///repo"
    
    if [ "$IS_CI" = true ]; then
        # CI: Keep GitHub URL, only update targetRevision to commit SHA
        echo -e "${BLUE}CI Mode: Keeping GitHub URLs and updating targetRevision to commit SHA${NC}"
        
        # Update targetRevision for Git sources (not Helm charts) to use commit SHA
        for file in "$REPO_ROOT"/bootstrap/argocd/base/*.yaml "$REPO_ROOT"/bootstrap/argocd/overlays/production/components-tenants/*.yaml; do
            if [ -f "$file" ]; then
                # Only update targetRevision if this is a Git source (has GitHub URL)
                # Skip if it's a Helm chart (has 'chart:' field)
                if grep -qE "$GITHUB_URL_PATTERN" "$file" 2>/dev/null && ! grep -q "^  chart:" "$file" 2>/dev/null; then
                    if grep -q "targetRevision:" "$file" 2>/dev/null; then
                        sed -i.bak "s/targetRevision:.*/targetRevision: $CURRENT_COMMIT/" "$file"
                        rm -f "$file.bak"
                        echo -e "  ${GREEN}✓${NC} Updated targetRevision in: $(basename "$file")"
                    fi
                fi
            fi
        done
        
        # Update root.yaml files to use commit SHA (keep GitHub URL)
        for root_file in "$REPO_ROOT"/bootstrap/argocd/overlays/*/root.yaml; do
            if [ -f "$root_file" ] && grep -qE "$GITHUB_URL_PATTERN" "$root_file" 2>/dev/null; then
                if grep -q "targetRevision:" "$root_file" 2>/dev/null; then
                    sed -i.bak "s/targetRevision:.*/targetRevision: $CURRENT_COMMIT/" "$root_file"
                    rm -f "$root_file.bak"
                    echo -e "  ${GREEN}✓${NC} Updated targetRevision to $CURRENT_COMMIT: $(basename "$(dirname "$root_file")")/$(basename "$root_file")"
                fi
            fi
        done
        
    else
        # Local: Use file:///repo for faster sync
        echo -e "${BLUE}Local Mode: Converting to local filesystem URLs${NC}"
        
        # Update URLs in bootstrap files (base/ and production tenant components)
        for file in "$REPO_ROOT"/bootstrap/argocd/base/*.yaml "$REPO_ROOT"/bootstrap/argocd/overlays/production/components-tenants/*.yaml; do
            if [ -f "$file" ]; then
                if grep -qE "$GITHUB_URL_PATTERN" "$file" 2>/dev/null; then
                    sed -i.bak -E "s|$GITHUB_URL_PATTERN|$LOCAL_URL|g" "$file"
                    rm -f "$file.bak"
                    echo -e "  ${GREEN}✓${NC} Updated URL in: $(basename "$file")"
                fi
            fi
        done
        
        # Update targetRevision for local file sources
        for file in "$REPO_ROOT"/bootstrap/argocd/base/*.yaml "$REPO_ROOT"/bootstrap/argocd/overlays/production/components-tenants/*.yaml; do
            if [ -f "$file" ]; then
                # Only update targetRevision if this is a Git source (has file:///repo)
                # Skip if it's a Helm chart (has 'chart:' field)
                if grep -q "file:///repo" "$file" 2>/dev/null && ! grep -q "^  chart:" "$file" 2>/dev/null; then
                    if grep -q "targetRevision:" "$file" 2>/dev/null; then
                        sed -i.bak "s/targetRevision:.*/targetRevision: $CURRENT_COMMIT/" "$file"
                        rm -f "$file.bak"
                    fi
                fi
            fi
        done
        
        # Update root.yaml files to use local filesystem
        for root_file in "$REPO_ROOT"/bootstrap/argocd/overlays/*/root.yaml; do
            if [ -f "$root_file" ]; then
                # Update URL to local filesystem
                if grep -qE "$GITHUB_URL_PATTERN" "$root_file" 2>/dev/null; then
                    sed -i.bak -E "s|$GITHUB_URL_PATTERN|$LOCAL_URL|g" "$root_file"
                    rm -f "$root_file.bak"
                fi
                
                # Update targetRevision if it's now a local file source
                if grep -q "file:///repo" "$root_file" 2>/dev/null && grep -q "targetRevision:" "$root_file" 2>/dev/null; then
                    sed -i.bak "s/targetRevision:.*/targetRevision: $CURRENT_COMMIT/" "$root_file"
                    rm -f "$root_file.bak"
                    echo -e "  ${GREEN}✓${NC} Updated to local filesystem: $(basename "$(dirname "$root_file")")/$(basename "$root_file")"
                fi
            fi
        done
    fi
    
    # Verify patches were applied
    echo -e "${BLUE}Verifying patches...${NC}"
    
    if [ "$IS_CI" = true ]; then
        # CI: Verify GitHub URLs are kept and targetRevision is updated
        echo -e "${BLUE}Checking CI configuration (GitHub URL + commit SHA)...${NC}"
        
        # Check that GitHub URLs are still present
        GITHUB_COUNT=$(grep -c "$GITHUB_URL_PATTERN" "$REPO_ROOT"/bootstrap/argocd/base/*.yaml "$REPO_ROOT"/bootstrap/argocd/overlays/*/root.yaml 2>/dev/null || echo "0")
        echo -e "  ${GREEN}✓${NC} GitHub URLs found: $GITHUB_COUNT"
        
        # Check that commit SHA is being used
        COMMIT_COUNT=$(grep -c "targetRevision: $CURRENT_COMMIT" "$REPO_ROOT"/bootstrap/argocd/base/*.yaml "$REPO_ROOT"/bootstrap/argocd/overlays/*/root.yaml 2>/dev/null || echo "0")
        echo -e "  ${GREEN}✓${NC} Files using commit SHA: $COMMIT_COUNT"
        
    else
        # Local: Verify conversion to file:///repo
        echo -e "${BLUE}Checking local configuration (file:///repo)...${NC}"
        
        # List all files that still contain GitHub URL
        REMAINING=$(grep -l "$GITHUB_URL_PATTERN" "$REPO_ROOT"/bootstrap/argocd/base/*.yaml "$REPO_ROOT"/bootstrap/argocd/overlays/production/components-tenants/*.yaml "$REPO_ROOT"/bootstrap/argocd/overlays/*/root.yaml 2>/dev/null || true)
        if [ -n "$REMAINING" ]; then
            echo -e "  ${RED}✗ Files still containing GitHub URL:${NC}"
            echo "$REMAINING" | while read f; do echo "    - $(basename "$f")"; done
        else
            echo -e "  ${GREEN}✓${NC} No files contain GitHub URL"
        fi
        
        # Check local file URLs
        LOCAL_COUNT=$(grep -c "file:///repo" "$REPO_ROOT"/bootstrap/argocd/base/*.yaml "$REPO_ROOT"/bootstrap/argocd/overlays/*/root.yaml 2>/dev/null || echo "0")
        echo -e "  ${GREEN}✓${NC} Local file URLs: $LOCAL_COUNT"
    fi
    
    if [ "$IS_CI" = true ]; then
        echo -e "${GREEN}✓ ArgoCD manifests configured for CI (GitHub URL + commit SHA)${NC}"
    else
        echo -e "${GREEN}✓ ArgoCD manifests configured for local development (file:///repo)${NC}"
    fi
fi

exit 0
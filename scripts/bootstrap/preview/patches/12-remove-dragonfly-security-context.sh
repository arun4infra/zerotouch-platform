#!/bin/bash
# Remove security context from Dragonfly composition for local testing
# Local Kind clusters don't enforce PodSecurity "restricted" policy

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
    DRAGONFLY_COMPOSITION="$REPO_ROOT/platform/databases/dragonfly/dragonfly-composition.yaml"
    
    if [ -f "$DRAGONFLY_COMPOSITION" ]; then
        # Remove pod-level securityContext block
        sed -i.bak '/^                    securityContext:$/,/^                    containers:$/{ /^                    securityContext:$/d; /runAsNonRoot:/d; /runAsUser:/d; /runAsGroup:/d; /fsGroup:/d; /seccompProfile:/d; /type: RuntimeDefault/d; }' "$DRAGONFLY_COMPOSITION"
        
        # Remove container-level securityContext block
        sed -i.bak '/^                        securityContext:$/,/^                        ports:$/{ /^                        securityContext:$/d; /allowPrivilegeEscalation:/d; /capabilities:/d; /drop:/d; /- ALL/d; }' "$DRAGONFLY_COMPOSITION"
        
        rm -f "$DRAGONFLY_COMPOSITION.bak"
        echo -e "${GREEN}✓${NC} Dragonfly composition: security context removed for local testing"
    else
        echo -e "${RED}✗${NC} Dragonfly composition not found: $DRAGONFLY_COMPOSITION"
        exit 1
    fi
else
    echo -e "${YELLOW}Not in preview mode - skipping Dragonfly security context removal${NC}"
fi

exit 0
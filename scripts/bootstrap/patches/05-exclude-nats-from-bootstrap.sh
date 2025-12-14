#!/bin/bash
# Exclude NATS from platform-bootstrap in preview mode
# NATS will be created separately with correct storage class
#
# Usage: ./05-exclude-nats-from-bootstrap.sh [--force]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FORCE_UPDATE=false
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
    echo -e "${BLUE}Excluding NATS from platform-bootstrap for preview mode...${NC}"
    
    PLATFORM_BOOTSTRAP="$REPO_ROOT/bootstrap/10-platform-bootstrap.yaml"
    
    if [ -f "$PLATFORM_BOOTSTRAP" ]; then
        # Check current exclude pattern
        CURRENT_EXCLUDE=$(grep "exclude:" "$PLATFORM_BOOTSTRAP" 2>/dev/null || echo "")
        
        if echo "$CURRENT_EXCLUDE" | grep -q "01-nats.yaml"; then
            echo -e "  ${GREEN}✓${NC} NATS already excluded from platform-bootstrap"
        else
            # Update exclude pattern to include NATS
            # Change: exclude: '01-eso.yaml'
            # To:     exclude: '{01-eso.yaml,01-nats.yaml}'
            if grep -q "exclude: '01-eso.yaml'" "$PLATFORM_BOOTSTRAP" 2>/dev/null; then
                sed -i.bak "s|exclude: '01-eso.yaml'|exclude: '{01-eso.yaml,01-nats.yaml}'|g" "$PLATFORM_BOOTSTRAP"
                rm -f "$PLATFORM_BOOTSTRAP.bak"
                echo -e "  ${GREEN}✓${NC} Updated exclude pattern to include NATS"
            elif grep -q 'exclude:' "$PLATFORM_BOOTSTRAP" 2>/dev/null; then
                # Already has a glob pattern, add NATS to it
                sed -i.bak "s|exclude: '{\([^}]*\)}'|exclude: '{\1,01-nats.yaml}'|g" "$PLATFORM_BOOTSTRAP"
                rm -f "$PLATFORM_BOOTSTRAP.bak"
                echo -e "  ${GREEN}✓${NC} Added NATS to existing exclude pattern"
            else
                echo -e "  ${YELLOW}⚠${NC} No exclude pattern found - manual intervention needed"
            fi
        fi
        
        # Verify
        echo -e "${BLUE}Verifying exclude pattern:${NC}"
        grep -n "exclude:" "$PLATFORM_BOOTSTRAP" || echo "  (no exclude found)"
    else
        echo -e "  ${YELLOW}⚠${NC} platform-bootstrap.yaml not found"
    fi
    
    echo -e "${GREEN}✓ NATS exclusion patch applied${NC}"
fi

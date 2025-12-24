#!/bin/bash
# Apply all preview/Kind patches to ide-orchestrator claims
# This script runs all numbered patch scripts in order
#
# Usage: ./00-apply-all-patches.sh [--force]
#
# Run this BEFORE deploying to preview environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pass through arguments (e.g., --force)
ARGS="$@"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Applying Preview Environment Patches                      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if patches already applied
PATCH_MARKER="/tmp/.ide-orchestrator-patches-applied"
if [ -f "$PATCH_MARKER" ] && [ "$1" != "--force" ]; then
    echo -e "${YELLOW}Patches already applied. Use --force to reapply.${NC}"
    exit 0
fi

# Run all numbered patch scripts (01-*, 02-*, etc.)
for script in "$SCRIPT_DIR"/[0-9][0-9]-*.sh; do
    if [ -f "$script" ] && [ "$script" != "$0" ]; then
        script_name=$(basename "$script")
        echo -e "${BLUE}Running: $script_name${NC}"
        chmod +x "$script"
        "$script" $ARGS
        echo ""
    fi
done

# Mark patches as applied
touch "$PATCH_MARKER"

echo -e "${GREEN}✓ All preview patches applied successfully${NC}"
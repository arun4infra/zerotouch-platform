#!/bin/bash
# Validate all Platform APIs
# This script runs all API validation scripts in order
#
# Usage: ./validate-apis.sh
#
# Validates EventDrivenService and WebService Platform APIs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Validating Platform APIs                                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Track validation results
FAILED=0
TOTAL=0

# Run all numbered validation scripts (15-*, 16-*, etc.)
for script in "$SCRIPT_DIR"/[0-9][0-9]-*.sh; do
    if [ -f "$script" ] && [ "$script" != "$0" ]; then
        script_name=$(basename "$script")
        api_name=$(echo "$script_name" | sed 's/[0-9][0-9]-verify-\(.*\)-api\.sh/\1/')
        
        echo -e "${BLUE}Validating: ${api_name} API${NC}"
        ((TOTAL++))
        
        chmod +x "$script"
        # Run script and show all output, capture exit code
        if "$script" 2>&1; then
            echo -e "  ✅ ${GREEN}${api_name} API validation passed${NC}"
        else
            echo -e "  ❌ ${RED}${api_name} API validation failed${NC}"
            echo -e "  ${YELLOW}See detailed error output above${NC}"
            ((FAILED++))
        fi
        echo ""
    fi
done

# Summary
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Platform API Validation Summary                           ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

if [[ $FAILED -eq 0 ]]; then
    echo -e "✅ ${GREEN}All $TOTAL Platform APIs validated successfully${NC}"
    exit 0
else
    echo -e "❌ ${RED}$FAILED out of $TOTAL Platform API validations failed${NC}"
    echo ""
    echo -e "${YELLOW}To debug individual failures, run:${NC}"
    for script in "$SCRIPT_DIR"/[0-9][0-9]-*.sh; do
        if [ -f "$script" ] && [ "$script" != "$0" ]; then
            echo -e "  $script"
        fi
    done
    exit 1
fi
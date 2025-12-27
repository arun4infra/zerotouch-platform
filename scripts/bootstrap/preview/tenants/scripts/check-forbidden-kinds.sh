#!/bin/bash
# Governance Script: Ban Infrastructure Kinds in App Repos
# Usage: ./check-forbidden-kinds.sh <path-to-manifests>

set -e

SEARCH_DIR="${1:-.}"
FORBIDDEN_KINDS=("Namespace" "ResourceQuota" "LimitRange" "NetworkPolicy")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🔍 Scanning '$SEARCH_DIR' for forbidden infrastructure kinds..."

FOUND_ERROR=0

# Loop through all YAML files
while IFS= read -r file; do
    for kind in "${FORBIDDEN_KINDS[@]}"; do
        # Use grep to find 'kind: <Forbidden>' (ignoring comments)
        if grep -E "^[[:space:]]*kind:[[:space:]]*$kind" "$file" > /dev/null 2>&1; then
            echo -e "${RED}❌ VIOLATION: Found '$kind' in $file${NC}"
            echo -e "${YELLOW}   Reason: $kind is managed by Platform State (zerotouch-tenants), not App Logic.${NC}"
            FOUND_ERROR=1
        fi
    done
done < <(find "$SEARCH_DIR" -name "*.yaml" -o -name "*.yml" 2>/dev/null)

if [ $FOUND_ERROR -eq 1 ]; then
    echo ""
    echo -e "${RED}⛔ Governance Check Failed.${NC}"
    echo -e "${YELLOW}Please remove infrastructure definitions from this repository.${NC}"
    echo -e "${YELLOW}Infrastructure should be defined in zerotouch-tenants repository.${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Governance Check Passed: No forbidden infrastructure kinds found.${NC}"
    exit 0
fi
#!/bin/bash
# Remove control plane tolerations for Kind
# Usage: ./03-patch-tolerations.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Removing control plane tolerations...${NC}"

# Files that have control plane tolerations in helm values
FILES_TO_PATCH=(
    "$REPO_ROOT/bootstrap/components/01-eso.yaml"
    "$REPO_ROOT/bootstrap/components/01-crossplane.yaml"
    "$REPO_ROOT/bootstrap/components/01-keda.yaml"
    "$REPO_ROOT/bootstrap/components/01-nats.yaml"
    "$REPO_ROOT/bootstrap/components/01-cnpg.yaml"
    "$REPO_ROOT/bootstrap/components/01-kagent.yaml"
)

for file in "${FILES_TO_PATCH[@]}"; do
    if [ -f "$file" ]; then
        if grep -q "node-role.kubernetes.io/control-plane" "$file" 2>/dev/null; then
            # Remove lines containing control-plane references
            sed -i.bak '/node-role.kubernetes.io\/control-plane/d' "$file"
            rm -f "$file.bak"
            echo -e "  ${GREEN}✓${NC} Patched: $(basename "$file")"
        fi
    fi
done

echo -e "${GREEN}✓ Toleration patches applied${NC}"

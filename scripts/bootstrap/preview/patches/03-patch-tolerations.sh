#!/bin/bash
# Remove control plane tolerations for Kind
# Usage: ./03-patch-tolerations.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}NOTE: This script is now deprecated.${NC}"
echo -e "${BLUE}Control plane toleration removal is now handled by Kustomize overlays in bootstrap/overlays/preview${NC}"
echo -e "${GREEN}✓ No action needed - overlays will handle toleration patching automatically${NC}"

#!/bin/bash
# Remove control plane tolerations for Kind
# Usage: ./03-patch-tolerations.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Find repository root by looking for .git directory
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR" && while [[ ! -d .git && $(pwd) != "/" ]]; do cd ..; done; pwd))"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}NOTE: This script is now deprecated.${NC}"
echo -e "${BLUE}Control plane toleration removal is now handled by Kustomize overlays in bootstrap/argocd/overlays/preview${NC}"
echo -e "${GREEN}✓ No action needed - overlays will handle toleration patching automatically${NC}"

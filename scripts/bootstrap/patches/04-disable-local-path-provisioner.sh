#!/bin/bash
# Disable local-path-provisioner ArgoCD Application for Kind/preview
# Kind comes with its own local-path-provisioner, so we don't need to deploy ours
#
# Usage: ./04-disable-local-path-provisioner.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOCAL_PATH_FILE="$REPO_ROOT/bootstrap/components/01-local-path-provisioner.yaml"
DISABLED_FILE="$REPO_ROOT/bootstrap/components/01-local-path-provisioner.yaml.disabled"

echo -e "${BLUE}Disabling local-path-provisioner for preview mode...${NC}"

if [ -f "$LOCAL_PATH_FILE" ]; then
    # Rename to .disabled so ArgoCD won't pick it up
    mv "$LOCAL_PATH_FILE" "$DISABLED_FILE"
    echo -e "  ${GREEN}✓${NC} Disabled: 01-local-path-provisioner.yaml"
    echo -e "  ${BLUE}ℹ${NC} Kind's built-in provisioner will be used instead"
elif [ -f "$DISABLED_FILE" ]; then
    echo -e "  ${YELLOW}⚠${NC} Already disabled"
else
    echo -e "  ${YELLOW}⚠${NC} File not found (may already be removed)"
fi

echo -e "${GREEN}✓ local-path-provisioner disabled for preview mode${NC}"

#!/bin/bash
# Cleanup Preview Environment
# Usage: ./cleanup-preview.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CLUSTER_NAME="zerotouch-preview"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Cleanup Preview Environment                               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo -e "${RED}Error: kind is not installed${NC}"
    exit 1
fi

# Check if cluster exists
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${YELLOW}Kind cluster '$CLUSTER_NAME' does not exist${NC}"
    exit 0
fi

echo -e "${BLUE}Deleting Kind cluster '$CLUSTER_NAME'...${NC}"
kind delete cluster --name "$CLUSTER_NAME"

echo ""
echo -e "${GREEN}✓ Preview environment cleaned up${NC}"
echo ""

#!/bin/bash
# Bootstrap Talos Cluster
# Usage: ./04-bootstrap-talos.sh <server-ip>
#
# This script:
# 1. Applies Talos configuration
# 2. Bootstraps etcd cluster
# 3. Fetches kubeconfig
# 4. Verifies cluster is ready

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Kubectl retry function
kubectl_retry() {
    local max_attempts=20
    local timeout=15
    local attempt=1
    local exitCode=0

    while [ $attempt -le $max_attempts ]; do
        if timeout $timeout kubectl "$@"; then
            return 0
        fi

        exitCode=$?

        if [ $attempt -lt $max_attempts ]; then
            local delay=$((attempt * 2))
            echo -e "${YELLOW}⚠️  kubectl command failed (attempt $attempt/$max_attempts). Retrying in ${delay}s...${NC}" >&2
            sleep $delay
        fi

        attempt=$((attempt + 1))
    done

    echo -e "${RED}✗ kubectl command failed after $max_attempts attempts${NC}" >&2
    return $exitCode
}

# Check arguments
if [ "$#" -ne 1 ]; then
    echo -e "${RED}Usage: $0 <server-ip>${NC}"
    exit 1
fi

SERVER_IP="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Bootstrapping Talos Cluster                                ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Wait for Talos to boot
echo -e "${BLUE}⏳ Waiting 3 minutes for Talos to boot...${NC}"
sleep 180

# Change to Talos config directory
cd "$SCRIPT_DIR/../../bootstrap/talos"

# Apply Talos configuration
echo -e "${BLUE}Applying Talos configuration (with CNI=none to prevent Flannel)...${NC}"
if ! talosctl apply-config --insecure \
  --nodes "$SERVER_IP" \
  --endpoints "$SERVER_IP" \
  --file nodes/cp01-main/config.yaml \
  --config-patch '[{"op": "add", "path": "/cluster/network/cni", "value": {"name": "none"}}]'; then
    echo -e "${RED}Failed to apply Talos config. Waiting 30s and retrying...${NC}"
    sleep 30
    talosctl apply-config --insecure \
      --nodes "$SERVER_IP" \
      --endpoints "$SERVER_IP" \
      --file nodes/cp01-main/config.yaml \
      --config-patch '[{"op": "add", "path": "/cluster/network/cni", "value": {"name": "none"}}]'
fi

echo -e "${BLUE}Waiting 30 seconds for config to apply...${NC}"
sleep 30

# Bootstrap etcd
echo -e "${BLUE}Bootstrapping etcd cluster...${NC}"
talosctl bootstrap \
  --nodes "$SERVER_IP" \
  --endpoints "$SERVER_IP" \
  --talosconfig talosconfig

echo -e "${BLUE}Waiting 180 seconds for cluster to stabilize and API server to start...${NC}"
sleep 180

# Fetch kubeconfig
echo -e "${BLUE}Fetching kubeconfig...${NC}"
talosctl kubeconfig \
  --nodes "$SERVER_IP" \
  --endpoints "$SERVER_IP" \
  --talosconfig talosconfig \
  --force

# Verify cluster
echo -e "${BLUE}Verifying cluster (with retries)...${NC}"
kubectl_retry get nodes

echo ""
echo -e "${GREEN}✓ Talos cluster bootstrapped successfully${NC}"
echo ""

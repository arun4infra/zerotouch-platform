#!/bin/bash
# Production Mode Setup
# Usage: ./setup-production.sh <server-ip> <root-password> [worker-nodes] [worker-password]
#
# This script handles production-specific setup including credentials file
# initialization and cluster validation checks.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SERVER_IP="$1"
ROOT_PASSWORD="$2"
WORKER_NODES="${3:-}"
WORKER_PASSWORD="${4:-}"
YES_FLAG="${5:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CREDENTIALS_FILE="$BOOTSTRAP_DIR/bootstrap-credentials/bootstrap-credentials-$(date +%Y%m%d-%H%M%S).txt"

echo -e "${BLUE}Running in PRODUCTION mode (Bare Metal/Talos)${NC}" >&2
echo "" >&2

# Check if cluster is already bootstrapped
if kubectl cluster-info &>/dev/null; then
    echo -e "${YELLOW}⚠️  WARNING: Kubernetes cluster is already accessible${NC}" >&2
    echo -e "${YELLOW}   This script is designed for initial bootstrap only.${NC}" >&2
    echo "" >&2
    echo -e "${BLUE}Current cluster:${NC}" >&2
    kubectl get nodes >&2 2>&1 || true
    echo "" >&2
    echo -e "${YELLOW}If you need to:${NC}" >&2
    echo -e "  - Add repository credentials: ${GREEN}./scripts/bootstrap/install/13-configure-repo-credentials.sh${NC}" >&2
    echo -e "  - Inject secrets: ${GREEN}./scripts/bootstrap/install/07-inject-eso-secrets.sh${NC}" >&2
    echo -e "  - Add worker nodes: ${GREEN}./scripts/bootstrap/install/05-add-worker-nodes.sh${NC}" >&2
    echo "" >&2
    if [ "$YES_FLAG" = "--yes" ]; then
        echo "y" >&2
        REPLY="y"
    else
        read -p "Do you want to continue anyway? This may cause issues! (y/N): " -n 1 -r </dev/tty
        echo "" >&2
    fi
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Aborted. Use individual scripts for post-bootstrap tasks.${NC}" >&2
        exit 0
    fi
    echo -e "${YELLOW}Continuing with bootstrap (you've been warned!)...${NC}" >&2
    echo "" >&2
fi

echo -e "${GREEN}Server IP:${NC} $SERVER_IP" >&2
echo -e "${GREEN}Credentials will be saved to:${NC} $CREDENTIALS_FILE" >&2
echo "" >&2

# Initialize credentials file
cat > "$CREDENTIALS_FILE" << EOF
╔══════════════════════════════════════════════════════════════╗
║   BizMatters Infrastructure - Bootstrap Credentials         ║
║   Generated: $(date)                            ║
╚══════════════════════════════════════════════════════════════╝

Server IP: $SERVER_IP
Bootstrap Date: $(date)

EOF

# Export credentials file path for other scripts to use (redirect other output to stderr)
echo "$CREDENTIALS_FILE"

exit 0

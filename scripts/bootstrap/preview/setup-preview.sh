#!/bin/bash
# Tier 3 Script: Setup Preview Cluster
# Creates Kind cluster and installs required tools for CI/CD testing
#
# Environment Variables (required):
#   AWS_ACCESS_KEY_ID - AWS access key for ESO
#   AWS_SECRET_ACCESS_KEY - AWS secret key for ESO
#   AWS_SESSION_TOKEN - AWS session token (optional, for OIDC)
#
# Exit Codes:
#   0 - Success
#   1 - Missing AWS credentials
#   2 - Tool installation failed
#   3 - Kind cluster creation failed

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLUSTER_NAME="zerotouch-preview"
KIND_CONFIG="$SCRIPT_DIR/helpers/kind-config.yaml"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Setup Preview Cluster                                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Preview mode - tenant resources will be cleaned up after ArgoCD deployment
echo -e "${BLUE}Preview mode configured${NC}"
echo ""

# 1. Apply preview patches (URLs, storage class, tolerations, disable local-path-provisioner)
echo -e "${BLUE}Applying preview patches...${NC}"
# Pass --force since we're definitely in preview mode (cluster doesn't exist yet)
"$SCRIPT_DIR/patches/00-apply-all-patches.sh" --force

# Patches applied - using default storage class (no verification needed)
echo ""

# 2. Update Kind config to mount local repo
echo -e "${BLUE}Updating Kind config to mount local repo...${NC}"

cat > "$KIND_CONFIG" << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: zerotouch-preview
nodes:
- role: control-plane
  extraPortMappings:
  # NATS client port
  - containerPort: 30080
    hostPort: 4222
    protocol: TCP
  # PostgreSQL port
  - containerPort: 30432
    hostPort: 5432
    protocol: TCP
  # Dragonfly (Redis-compatible) port
  - containerPort: 30379
    hostPort: 6379
    protocol: TCP
  extraMounts:
  # Mount local repo for ArgoCD to sync from
  - hostPath: $REPO_ROOT
    containerPath: /repo
    readOnly: true
EOF

echo -e "${GREEN}✓ Kind config updated with local repo mount at /repo${NC}"
echo ""

# 4. Validate AWS credentials
if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    echo -e "${RED}Error: AWS credentials required${NC}"
    echo -e "Set: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN (optional)"
    exit 1
fi

echo -e "${GREEN}✓ AWS credentials configured${NC}"
echo ""

# 5. Install required tools
echo -e "${YELLOW}Checking required tools...${NC}"

# kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${BLUE}Installing kubectl...${NC}"
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/kubectl || exit 2
fi
echo -e "${GREEN}✓ kubectl available${NC}"

# helm
if ! command -v helm &> /dev/null; then
    echo -e "${BLUE}Installing helm...${NC}"
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash || exit 2
fi
echo -e "${GREEN}✓ helm available${NC}"

# kind
if ! command -v kind &> /dev/null; then
    echo -e "${BLUE}Installing kind...${NC}"
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind || exit 2
fi
echo -e "${GREEN}✓ kind available${NC}"
echo ""

# 6. Create Kind cluster
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${YELLOW}Kind cluster '$CLUSTER_NAME' already exists${NC}"
else
    echo -e "${BLUE}Creating Kind cluster '$CLUSTER_NAME'...${NC}"
    if [ ! -f "$KIND_CONFIG" ]; then
        echo -e "${RED}Error: Kind config not found at $KIND_CONFIG${NC}"
        exit 3
    fi
    kind create cluster --config "$KIND_CONFIG" || exit 3
    echo -e "${GREEN}✓ Kind cluster created${NC}"
fi

# 7. Set kubectl context
kubectl config use-context "kind-${CLUSTER_NAME}"

# 8. Label nodes for database workloads
echo -e "${BLUE}Labeling nodes for database workloads...${NC}"
kubectl label nodes --all workload.bizmatters.dev/databases=true --overwrite
echo -e "${GREEN}✓ Nodes labeled${NC}"

echo ""

# Preview-specific exclusions and setup complete
echo ""
echo -e "${GREEN}✓ Preview cluster setup complete${NC}"
echo -e "  Cluster: ${BLUE}kind-${CLUSTER_NAME}${NC}"
echo -e "  Context: ${BLUE}kind-${CLUSTER_NAME}${NC}"
echo ""

exit 0
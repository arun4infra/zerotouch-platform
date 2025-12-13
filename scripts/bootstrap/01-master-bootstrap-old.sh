#!/bin/bash
# Master Bootstrap Script for BizMatters Infrastructure
# Usage: ./01-master-bootstrap.sh <server-ip> <root-password> [--worker-nodes <list>]
#
# This script orchestrates the complete cluster bootstrap process by calling
# numbered scripts in sequence. All logic is in the individual scripts.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
if [ "$#" -lt 2 ]; then
    echo -e "${RED}Usage: $0 <server-ip> <root-password> [--worker-nodes <list>] [--worker-password <password>]${NC}"
    echo ""
    echo "Arguments:"
    echo "  <server-ip>         Control plane server IP"
    echo "  <root-password>     Root password for rescue mode"
    echo "  --worker-nodes      Optional: Comma-separated list of worker nodes (name:ip format)"
    echo "  --worker-password   Optional: Worker node rescue password (if different from control plane)"
    echo ""
    echo "Examples:"
    echo "  Single node:  $0 46.62.218.181 MyS3cur3P@ssw0rd"
    echo "  Multi-node:   $0 46.62.218.181 MyS3cur3P@ssw0rd --worker-nodes worker01-db:95.216.151.243 --worker-password WorkerP@ss"
    exit 1
fi

SERVER_IP="$1"
ROOT_PASSWORD="$2"
WORKER_NODES=""
WORKER_PASSWORD=""

# Parse optional worker nodes parameter
shift 2
while [[ $# -gt 0 ]]; do
    case $1 in
        --worker-nodes)
            WORKER_NODES="$2"
            shift 2
            ;;
        --worker-password)
            WORKER_PASSWORD="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# If worker password not specified, use control plane password
if [ -z "$WORKER_PASSWORD" ]; then
    WORKER_PASSWORD="$ROOT_PASSWORD"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDENTIALS_FILE="$SCRIPT_DIR/.bootstrap-credentials-$(date +%Y%m%d-%H%M%S).txt"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   BizMatters Infrastructure - Master Bootstrap Script      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if cluster is already bootstrapped
if kubectl cluster-info &>/dev/null; then
    echo -e "${YELLOW}⚠️  WARNING: Kubernetes cluster is already accessible${NC}"
    echo -e "${YELLOW}   This script is designed for initial bootstrap only.${NC}"
    echo ""
    echo -e "${BLUE}Current cluster:${NC}"
    kubectl get nodes 2>/dev/null || true
    echo ""
    echo -e "${YELLOW}If you need to:${NC}"
    echo -e "  - Add repository credentials: ${GREEN}./scripts/bootstrap/13-configure-repo-credentials.sh${NC}"
    echo -e "  - Inject secrets: ${GREEN}./scripts/bootstrap/07-inject-eso-secrets.sh${NC}"
    echo -e "  - Add worker nodes: ${GREEN}./scripts/bootstrap/05-add-worker-nodes.sh${NC}"
    echo ""
    read -p "Do you want to continue anyway? This may cause issues! (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Aborted. Use individual scripts for post-bootstrap tasks.${NC}"
        exit 0
    fi
    echo -e "${YELLOW}Continuing with bootstrap (you've been warned!)...${NC}"
    echo ""
fi

echo -e "${GREEN}Server IP:${NC} $SERVER_IP"
echo -e "${GREEN}Credentials will be saved to:${NC} $CREDENTIALS_FILE"
echo ""

# Initialize credentials file
cat > "$CREDENTIALS_FILE" << EOF
╔══════════════════════════════════════════════════════════════╗
║   BizMatters Infrastructure - Bootstrap Credentials         ║
║   Generated: $(date)                            ║
╚══════════════════════════════════════════════════════════════╝

Server IP: $SERVER_IP
Bootstrap Date: $(date)

EOF

# ============================================================================
# BOOTSTRAP SEQUENCE - All logic is in numbered scripts
# ============================================================================

# Step 1: Embed Cilium in Talos config
echo -e "${YELLOW}[1/13] Embedding Cilium CNI...${NC}"
"$SCRIPT_DIR/02-embed-cilium.sh"

# Step 2: Install Talos OS
echo -e "${YELLOW}[2/13] Installing Talos OS...${NC}"
"$SCRIPT_DIR/03-install-talos.sh" --server-ip "$SERVER_IP" --user root --password "$ROOT_PASSWORD" --yes

cat >> "$CREDENTIALS_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TALOS CREDENTIALS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Talos Config: bootstrap/talos/talosconfig
Control Plane Config: bootstrap/talos/nodes/cp01-main/config.yaml

Access Talos:
  talosctl --talosconfig bootstrap/talos/talosconfig -n $SERVER_IP version

EOF

# Step 3: Bootstrap Talos cluster
echo -e "${YELLOW}[3/13] Bootstrapping Talos cluster...${NC}"
"$SCRIPT_DIR/04-bootstrap-talos.sh" "$SERVER_IP"

# Step 4: Add Worker Nodes (if specified)
if [ -n "$WORKER_NODES" ]; then
    echo -e "${YELLOW}[4/13] Adding worker nodes...${NC}"
    "$SCRIPT_DIR/05-add-worker-nodes.sh" "$WORKER_NODES" "$WORKER_PASSWORD"
else
    echo -e "${BLUE}[4/13] No worker nodes specified - single node cluster${NC}"
fi

# Step 5: Wait for Cilium CNI
echo -e "${YELLOW}[5/13] Waiting for Cilium CNI...${NC}"
"$SCRIPT_DIR/06-wait-cilium.sh"

# Step 6: Inject ESO Secrets
echo -e "${YELLOW}[6/13] Injecting ESO secrets...${NC}"
"$SCRIPT_DIR/07-inject-eso-secrets.sh"

# Step 7: Inject SSM Parameters (BEFORE ArgoCD)
echo -e "${YELLOW}[7/13] Injecting SSM parameters...${NC}"
"$SCRIPT_DIR/08-inject-ssm-parameters.sh"

cat >> "$CREDENTIALS_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
AWS SSM PARAMETER STORE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Parameters injected from .env.ssm to AWS SSM Parameter Store

Verify parameters:
  aws ssm get-parameters-by-path --path /zerotouch/prod --region ap-south-1

EOF

# Step 8: Install ArgoCD
echo -e "${YELLOW}[8/13] Installing ArgoCD...${NC}"
"$SCRIPT_DIR/09-install-argocd.sh"

# Step 9: Wait for platform-bootstrap
echo -e "${YELLOW}[9/13] Waiting for platform-bootstrap...${NC}"
"$SCRIPT_DIR/10-wait-platform-bootstrap.sh"

# Step 10: Verify ESO
echo -e "${YELLOW}[10/13] Verifying ESO...${NC}"
"$SCRIPT_DIR/11-verify-eso.sh"

# Step 11: Verify child applications
echo -e "${YELLOW}[11/13] Verifying child applications...${NC}"
"$SCRIPT_DIR/12-verify-child-apps.sh"

# Extract ArgoCD password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "NOT_GENERATED")

cat >> "$CREDENTIALS_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ARGOCD CREDENTIALS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Username: admin
Password: $ARGOCD_PASSWORD

Access ArgoCD UI:
  kubectl port-forward -n argocd svc/argocd-server 8080:443
  Open: https://localhost:8080

Access via CLI:
  argocd login localhost:8080 --username admin --password '$ARGOCD_PASSWORD'

EOF

# Step 12: Configure repository credentials
echo -e "${YELLOW}[12/13] Configuring repository credentials...${NC}"
"$SCRIPT_DIR/13-configure-repo-credentials.sh" --auto || {
    echo -e "${YELLOW}⚠️  Repository credentials configuration had issues${NC}"
    echo -e "${BLUE}ℹ  You can configure manually: ./scripts/bootstrap/13-configure-repo-credentials.sh --auto${NC}"
}

cat >> "$CREDENTIALS_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ARGOCD REPOSITORY CREDENTIALS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Repository credentials managed via ExternalSecrets from AWS SSM

Verify:
  kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository
  kubectl get externalsecret -n argocd

EOF

# Step 13: Final cluster validation
echo -e "${YELLOW}[13/13] Running final cluster validation...${NC}"
"$SCRIPT_DIR/99-validate-cluster.sh" || {
    echo -e "${YELLOW}⚠️  Cluster validation found issues${NC}"
    echo -e "${BLUE}ℹ  Check ArgoCD applications: kubectl get applications -n argocd${NC}"
}

# ============================================================================
# BOOTSTRAP COMPLETE
# ============================================================================

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║             Bootstrap Complete!                              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Talos OS installed and configured${NC}"
if [ -n "$WORKER_NODES" ]; then
    echo -e "${GREEN}✓ Worker nodes installed and joined cluster${NC}"
fi
echo -e "${GREEN}✓ ArgoCD bootstrapped and managing platform${NC}"
echo -e "${GREEN}✓ Cluster validation complete${NC}"
echo ""
echo -e "${YELLOW}📝 Credentials saved to:${NC}"
echo -e "   ${GREEN}$CREDENTIALS_FILE${NC}"
echo ""
echo -e "${YELLOW}📌 Next Steps:${NC}"
echo -e "   1. Review credentials file and ${RED}BACK UP${NC} important credentials"
echo -e "   2. Port-forward ArgoCD UI: ${GREEN}kubectl port-forward -n argocd svc/argocd-server 8080:443${NC}"
echo -e "   3. Monitor applications: ${GREEN}kubectl get applications -n argocd${NC}"
echo ""
echo -e "${BLUE}Happy deploying! 🚀${NC}"
echo ""

# Display credentials file content
cat "$CREDENTIALS_FILE"

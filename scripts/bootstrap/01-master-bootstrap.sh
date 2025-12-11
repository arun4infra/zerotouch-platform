#!/bin/bash
# Master Bootstrap Script for BizMatters Infrastructure
# Usage: 
#   Production: ./01-master-bootstrap.sh <server-ip> <root-password> [--worker-nodes <list>]
#   Preview:    ./01-master-bootstrap.sh --mode preview
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

# Default mode
MODE="production"
SERVER_IP=""
ROOT_PASSWORD=""
WORKER_NODES=""
WORKER_PASSWORD=""

# Parse arguments
if [ "$#" -eq 0 ]; then
    echo -e "${RED}Usage:${NC}"
    echo -e "  ${GREEN}Production:${NC} $0 <server-ip> <root-password> [--worker-nodes <list>] [--worker-password <password>]"
    echo -e "  ${GREEN}Preview:${NC}    $0 --mode preview"
    echo ""
    echo "Arguments:"
    echo "  <server-ip>         Control plane server IP (production mode)"
    echo "  <root-password>     Root password for rescue mode (production mode)"
    echo "  --mode preview      Run in preview mode (GitHub Actions/Kind cluster)"
    echo "  --worker-nodes      Optional: Comma-separated list of worker nodes (name:ip format)"
    echo "  --worker-password   Optional: Worker node rescue password (if different from control plane)"
    echo ""
    echo "Examples:"
    echo "  Production single node:  $0 46.62.218.181 MyS3cur3P@ssw0rd"
    echo "  Production multi-node:   $0 46.62.218.181 MyS3cur3P@ssw0rd --worker-nodes worker01-db:95.216.151.243"
    echo "  Preview (CI/CD):         $0 --mode preview"
    exit 1
fi

# Check if first argument is --mode
if [ "$1" = "--mode" ]; then
    MODE="$2"
    shift 2
else
    # Production mode - require server-ip and password
    if [ "$#" -lt 2 ]; then
        echo -e "${RED}Error: Production mode requires <server-ip> and <root-password>${NC}"
        echo -e "Usage: $0 <server-ip> <root-password> [--worker-nodes <list>]"
        echo -e "   or: $0 --mode preview"
        exit 1
    fi
    SERVER_IP="$1"
    ROOT_PASSWORD="$2"
    shift 2
fi

# Parse remaining optional arguments
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
if [ -z "$WORKER_PASSWORD" ] && [ -n "$ROOT_PASSWORD" ]; then
    WORKER_PASSWORD="$ROOT_PASSWORD"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   BizMatters Infrastructure - Master Bootstrap Script      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Mode:${NC} $MODE"
echo ""

# ============================================================================
# PREVIEW MODE SETUP
# ============================================================================
if [ "$MODE" = "preview" ]; then
    echo -e "${BLUE}Running in PREVIEW mode (GitHub Actions/Kind)${NC}"
    echo ""
    "$SCRIPT_DIR/helpers/setup-preview.sh"
fi

# ============================================================================
# PRODUCTION MODE SETUP
# ============================================================================
if [ "$MODE" = "production" ]; then
    CREDENTIALS_FILE=$("$SCRIPT_DIR/helpers/setup-production.sh" "$SERVER_IP" "$ROOT_PASSWORD" "$WORKER_NODES" "$WORKER_PASSWORD")
fi

# ============================================================================
# BOOTSTRAP SEQUENCE - All logic is in numbered scripts
# ============================================================================

if [ "$MODE" = "production" ]; then
    # Step 1: Embed Cilium in Talos config
    echo -e "${YELLOW}[1/14] Embedding Cilium CNI...${NC}"
    "$SCRIPT_DIR/02-embed-cilium.sh"

    # Step 2: Install Talos OS
    echo -e "${YELLOW}[2/14] Installing Talos OS...${NC}"
    "$SCRIPT_DIR/03-install-talos.sh" --server-ip "$SERVER_IP" --user root --password "$ROOT_PASSWORD" --yes

    "$SCRIPT_DIR/helpers/add-credentials.sh" "$CREDENTIALS_FILE" "TALOS CREDENTIALS" "Talos Config: bootstrap/talos/talosconfig
Control Plane Config: bootstrap/talos/nodes/cp01-main/config.yaml

Access Talos:
  talosctl --talosconfig bootstrap/talos/talosconfig -n $SERVER_IP version"

    # Step 3: Bootstrap Talos cluster
    echo -e "${YELLOW}[3/14] Bootstrapping Talos cluster...${NC}"
    "$SCRIPT_DIR/04-bootstrap-talos.sh" "$SERVER_IP"

    # Step 4: Add Worker Nodes (if specified)
    if [ -n "$WORKER_NODES" ]; then
        echo -e "${YELLOW}[4/14] Adding worker nodes...${NC}"
        "$SCRIPT_DIR/05-add-worker-nodes.sh" "$WORKER_NODES" "$WORKER_PASSWORD"
    else
        echo -e "${BLUE}[4/14] No worker nodes specified - single node cluster${NC}"
    fi

    # Step 5: Wait for Cilium CNI
    echo -e "${YELLOW}[5/14] Waiting for Cilium CNI...${NC}"
    "$SCRIPT_DIR/06-wait-cilium.sh"
else
    echo -e "${BLUE}[1-5/14] Skipping Talos installation (preview mode uses Kind)${NC}"
fi

# Step 6: Inject ESO Secrets
echo -e "${YELLOW}[6/14] Injecting ESO secrets...${NC}"
"$SCRIPT_DIR/07-inject-eso-secrets.sh"

# Step 7: Inject SSM Parameters (BEFORE ArgoCD)
echo -e "${YELLOW}[7/14] Injecting SSM parameters...${NC}"
"$SCRIPT_DIR/08-inject-ssm-parameters.sh"

if [ "$MODE" = "production" ]; then
    "$SCRIPT_DIR/helpers/add-credentials.sh" "$CREDENTIALS_FILE" "AWS SSM PARAMETER STORE" "Parameters injected from .env.ssm to AWS SSM Parameter Store

Verify parameters:
  aws ssm get-parameters-by-path --path /zerotouch/prod --region ap-south-1"
fi

# Step 8: Install ArgoCD
echo -e "${YELLOW}[8/14] Installing ArgoCD...${NC}"
"$SCRIPT_DIR/09-install-argocd.sh"

# Step 9: Wait for platform-bootstrap
echo -e "${YELLOW}[9/14] Waiting for platform-bootstrap...${NC}"
"$SCRIPT_DIR/10-wait-platform-bootstrap.sh"

# Step 10: Verify ESO
echo -e "${YELLOW}[10/14] Verifying ESO...${NC}"
"$SCRIPT_DIR/11-verify-eso.sh"

# Step 11: Verify child applications
echo -e "${YELLOW}[11/14] Verifying child applications...${NC}"
"$SCRIPT_DIR/12-verify-child-apps.sh"

# Step 12: Wait for all apps to be healthy
echo -e "${YELLOW}[12/14] Waiting for all applications to be healthy...${NC}"
"$SCRIPT_DIR/12a-wait-apps-healthy.sh" --timeout 600

# Extract ArgoCD password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "NOT_GENERATED")

if [ "$MODE" = "production" ]; then
    "$SCRIPT_DIR/helpers/add-credentials.sh" "$CREDENTIALS_FILE" "ARGOCD CREDENTIALS" "Username: admin
Password: $ARGOCD_PASSWORD

Access ArgoCD UI:
  kubectl port-forward -n argocd svc/argocd-server 8080:443
  Open: https://localhost:8080

Access via CLI:
  argocd login localhost:8080 --username admin --password '$ARGOCD_PASSWORD'"
else
    echo ""
    echo -e "${GREEN}ArgoCD Credentials:${NC}"
    echo -e "  Username: ${YELLOW}admin${NC}"
    echo -e "  Password: ${YELLOW}$ARGOCD_PASSWORD${NC}"
    echo ""
fi

if [ "$MODE" = "production" ]; then
    # Step 14: Configure repository credentials
    echo -e "${YELLOW}[14/15] Configuring repository credentials...${NC}"
    "$SCRIPT_DIR/13-configure-repo-credentials.sh" --auto || {
        echo -e "${YELLOW}⚠️  Repository credentials configuration had issues${NC}"
        echo -e "${BLUE}ℹ  You can configure manually: ./scripts/bootstrap/13-configure-repo-credentials.sh --auto${NC}"
    }

    "$SCRIPT_DIR/helpers/add-credentials.sh" "$CREDENTIALS_FILE" "ARGOCD REPOSITORY CREDENTIALS" "Repository credentials managed via ExternalSecrets from AWS SSM

Verify:
  kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository
  kubectl get externalsecret -n argocd"
else
    echo -e "${BLUE}[14/15] Skipping repository credentials configuration (preview mode)${NC}"
fi

# Step 15: Final cluster validation
echo -e "${YELLOW}[15/15] Running final cluster validation...${NC}"
"$SCRIPT_DIR/99-validate-cluster.sh" || {
    echo -e "${YELLOW}⚠️  Cluster validation found issues${NC}"
    echo -e "${BLUE}ℹ  Check ArgoCD applications: kubectl get applications -n argocd${NC}"
}

# ============================================================================
# BOOTSTRAP COMPLETE
# ============================================================================

"$SCRIPT_DIR/99-bootstrap-complete.sh" "$MODE" "${CREDENTIALS_FILE:-}" "${SERVER_IP:-}" "${WORKER_NODES:-}"

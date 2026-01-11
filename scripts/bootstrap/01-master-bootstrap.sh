#!/bin/bash
# Master Bootstrap Script for BizMatters Infrastructure
# Usage: 
#   Production: ./01-master-bootstrap.sh <server-ip> <root-password> [--worker-nodes <list>]
#   Preview:    ./01-master-bootstrap.sh --mode preview
#
# This script orchestrates the complete cluster bootstrap process by calling
# numbered scripts in sequence. All logic is in the individual scripts.

# To Test argocd sync options without recreating cluster: 
# 1 - kubectl delete namespace argocd --wait=false
# 2 - sleep 5 && kubectl get namespace argocd 2>/dev/null || echo "ArgoCD namespace deleted"
# 3 - ./scripts/bootstrap/install/09-install-argocd.sh production dev

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Step counter for progress display
TOTAL_STEPS=17
CURRENT_STEP=0

# Function to display step progress
step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo -e "${YELLOW}[${CURRENT_STEP}/${TOTAL_STEPS}] $1${NC}"
}

# Function to display skipped step
skip_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo -e "${BLUE}[${CURRENT_STEP}/${TOTAL_STEPS}] $1 (skipped)${NC}"
}

# Default mode
MODE="production"
ENV="dev"
SERVER_IP=""
ROOT_PASSWORD=""
WORKER_NODES=""
WORKER_PASSWORD=""

# Parse arguments
if [ "$#" -eq 0 ]; then
    echo -e "${RED}Usage:${NC}"
    echo -e "  ${GREEN}Production (from tenant repo):${NC} $0 [ENV]"
    echo -e "  ${GREEN}Production (manual):${NC}           $0 <server-ip> <root-password> [--worker-nodes <list>]"
    echo -e "  ${GREEN}Preview:${NC}                       $0 --mode preview"
    echo ""
    echo "Arguments:"
    echo "  ENV                 Environment name (dev/staging/production) - reads from tenant repo"
    echo "  <server-ip>         Control plane server IP (manual mode)"
    echo "  <root-password>     Root password for rescue mode (manual mode)"
    echo "  --mode preview      Run in preview mode (GitHub Actions/Kind cluster)"
    echo "  --worker-nodes      Optional: Comma-separated list of worker nodes (name:ip format)"
    echo "  --worker-password   Optional: Worker node rescue password (if different from control plane)"
    echo ""
    echo "Examples:"
    echo "  From tenant repo:        $0 dev"
    echo "  Manual single node:      $0 46.62.218.181 MyS3cur3P@ssw0rd"
    echo "  Manual multi-node:       $0 46.62.218.181 MyS3cur3P@ssw0rd --worker-nodes worker01:95.216.151.243"
    echo "  Preview (CI/CD):         $0 --mode preview"
    exit 1
fi

# Check if first argument is --mode
if [ "$1" = "--mode" ]; then
    MODE="$2"
    shift 2
# Check if first argument looks like an environment name (not an IP)
elif [[ "$1" =~ ^(dev|staging|production)$ ]]; then
    ENV="$1"
    shift
    echo -e "${BLUE}Using environment: $ENV${NC}"
    echo -e "${BLUE}Fetching configuration from tenant repository...${NC}"
    
    # Parse tenant config using helper
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/helpers/parse-tenant-config.sh" "$ENV"
    
    echo -e "${GREEN}✓ Configuration loaded from tenant repo${NC}"
else
    # Manual mode - require server-ip and password
    if [ "$#" -lt 2 ]; then
        echo -e "${RED}Error: Manual mode requires <server-ip> and <root-password>${NC}"
        echo -e "Usage: $0 <server-ip> <root-password> [--worker-nodes <list>]"
        echo -e "   or: $0 [ENV]  (to use tenant repo)"
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

# Validate worker nodes format if provided
if [ -n "$WORKER_NODES" ]; then
    echo -e "${BLUE}Validating worker nodes format...${NC}"
    
    # Split by comma and validate each entry
    IFS=',' read -ra WORKER_ARRAY <<< "$WORKER_NODES"
    for worker_entry in "${WORKER_ARRAY[@]}"; do
        # Check if entry contains colon (name:ip format)
        if [[ ! "$worker_entry" =~ ^[a-zA-Z0-9_-]+:[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${RED}Error: Invalid worker node format: '$worker_entry'${NC}"
            echo -e "${RED}Expected format: name:ip (e.g., worker01:95.216.151.243)${NC}"
            echo ""
            echo -e "${YELLOW}Examples:${NC}"
            echo -e "  Single worker:   --worker-nodes worker01:95.216.151.243"
            echo -e "  Multiple workers: --worker-nodes worker01:95.216.151.243,worker02:95.216.151.244"
            echo ""
            exit 1
        fi
    done
    
    echo -e "${GREEN}✓ Worker nodes format validated${NC}"
fi

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
    
    # Copy service .env file to platform folder for bootstrap scripts to use
    SERVICE_ENV_FILE="$(cd "$SCRIPT_DIR/../../.." && pwd)/.env"
    PLATFORM_ENV_FILE="$SCRIPT_DIR/.env"
    
    if [[ -f "$SERVICE_ENV_FILE" ]]; then
        echo -e "${BLUE}Copying service .env file to platform folder...${NC}"
        cp "$SERVICE_ENV_FILE" "$PLATFORM_ENV_FILE"
        echo -e "${GREEN}✓ Service .env file copied to: $PLATFORM_ENV_FILE${NC}"
        
        # Source the copied .env file
        set -a  # automatically export all variables
        source "$PLATFORM_ENV_FILE"
        set +a  # stop automatically exporting
        echo -e "${GREEN}✓ Environment variables loaded${NC}"
    else
        echo -e "${YELLOW}⚠ Service .env file not found at: $SERVICE_ENV_FILE${NC}"
    fi
    
    "$SCRIPT_DIR/preview/setup-preview.sh"
fi

# ============================================================================
# PRODUCTION MODE SETUP
# ============================================================================
if [ "$MODE" = "production" ]; then
    echo -e "${BLUE}Setting up production environment...${NC}"
    CREDENTIALS_FILE=$("$SCRIPT_DIR/helpers/setup-production.sh" "$SERVER_IP" "$ROOT_PASSWORD" "$WORKER_NODES" "$WORKER_PASSWORD" --yes)
    echo -e "${GREEN}✓ Credentials file: $CREDENTIALS_FILE${NC}"
    
    if [ -z "$CREDENTIALS_FILE" ] || [ ! -f "$CREDENTIALS_FILE" ]; then
        echo -e "${RED}Error: Failed to create credentials file${NC}"
        exit 1
    fi
fi

# ============================================================================
# BOOTSTRAP SEQUENCE - All logic is in numbered scripts
# ============================================================================

if [ "$MODE" = "production" ]; then
    # Step 1: Embed Gateway API CRDs and Cilium in Talos config
    step "Embedding Gateway API CRDs and Cilium CNI..."
    "$SCRIPT_DIR/install/02-embed-network-manifests.sh"

    # Step 2: Install Talos OS
    step "Installing Talos OS..."
    "$SCRIPT_DIR/install/03-install-talos.sh" --server-ip "$SERVER_IP" --user root --password "$ROOT_PASSWORD" --yes

    # Step 3: Bootstrap Talos cluster
    step "Bootstrapping Talos cluster..."
    "$SCRIPT_DIR/install/04-bootstrap-talos.sh" "$SERVER_IP"

    "$SCRIPT_DIR/helpers/add-credentials.sh" "$CREDENTIALS_FILE" "TALOS CREDENTIALS" "Talos Config: bootstrap/talos/talosconfig
Control Plane Config: bootstrap/talos/nodes/cp01-main/config.yaml

Access Talos:
  talosctl --talosconfig bootstrap/talos/talosconfig -n $SERVER_IP version"

    # Step 4: Add Worker Nodes (if specified)
    if [ -n "$WORKER_NODES" ]; then
        step "Adding worker nodes..."
        "$SCRIPT_DIR/install/05-add-worker-nodes.sh" "$WORKER_NODES" "$WORKER_PASSWORD"
    else
        skip_step "No worker nodes specified - single node cluster"
    fi

    # Step 5: Wait for Cilium CNI
    step "Waiting for Cilium CNI..."
    "$SCRIPT_DIR/wait/06-wait-cilium.sh"

    # Step 6: Validate Gateway API readiness
    step "Validating Gateway API readiness..."
    "$SCRIPT_DIR/wait/06a-wait-gateway-api.sh"
else
    # Skip production-only steps in preview mode
    CURRENT_STEP=7
    echo -e "${BLUE}[1-7/${TOTAL_STEPS}] Skipping Talos installation (preview mode uses Kind)${NC}"
fi

# Step 7: Inject ESO Secrets
step "Injecting ESO secrets..."
"$SCRIPT_DIR/install/07-inject-eso-secrets.sh"

# Step 8: Inject SSM Parameters (BEFORE ArgoCD)
step "Injecting SSM parameters..."
"$SCRIPT_DIR/install/08-inject-ssm-parameters.sh"

if [ "$MODE" = "production" ]; then
    "$SCRIPT_DIR/helpers/add-credentials.sh" "$CREDENTIALS_FILE" "AWS SSM PARAMETER STORE" "Parameters injected from .env.ssm to AWS SSM Parameter Store

Verify parameters:
  aws ssm get-parameters-by-path --path /zerotouch/prod --region ap-south-1"
fi

# Step 9: Apply patches for preview mode BEFORE ArgoCD installation
if [ "$MODE" = "preview" ]; then
    step "Applying patches before ArgoCD installation..."
    "$SCRIPT_DIR/preview/patches/00-apply-all-patches.sh" --force
    
    # Verify critical patches in the mounted filesystem
    echo -e "${BLUE}Verifying patches in Kind container...${NC}"
    KIND_CONTAINER=$(docker ps --filter "name=zerotouch-preview-control-plane" --format "{{.Names}}" 2>/dev/null || echo "")
    if [ -n "$KIND_CONTAINER" ]; then
        echo -e "${BLUE}NATS file in container:${NC}"
        docker exec "$KIND_CONTAINER" grep -n "storageClassName" /repo/bootstrap/argocd/base/05-nats.yaml || echo "File not found"
        echo -e "${BLUE}Preview overlay kustomization:${NC}"
        docker exec "$KIND_CONTAINER" cat /repo/bootstrap/argocd/overlays/preview/kustomization.yaml || echo "Overlay not found"
        echo -e "${BLUE}Cilium status in container:${NC}"
        docker exec "$KIND_CONTAINER" ls -la /repo/platform/foundation/cilium.yaml* || echo "Cilium files not found"
    fi
else
    skip_step "Applying patches (production mode)"
fi

# Step 10: Install ArgoCD (includes NATS pre-creation for preview mode)
step "Installing ArgoCD..."
"$SCRIPT_DIR/install/09-install-argocd.sh" "$MODE" "$ENV"

# Step 11: Wait for platform-bootstrap
step "Waiting for platform-bootstrap..."
"$SCRIPT_DIR/wait/10-wait-platform-bootstrap.sh"

# Step 12: Wait for tenant repository authentication (production mode only)
if [ "$MODE" != "preview" ]; then
    step "Waiting for tenant repository authentication..."
    "$SCRIPT_DIR/wait/10b-wait-tenant-auth.sh"
else
    skip_step "Tenant repository authentication (preview mode)"
fi

# Step 13: Verify ESO
step "Verifying ESO..."
"$SCRIPT_DIR/validation/11-verify-eso.sh"

# Step 14: Verify child applications
step "Verifying child applications..."
"$SCRIPT_DIR/validation/12-verify-child-apps.sh"

# Step 15: Verify tenant landing zones
step "Verifying tenant landing zones..."
"$SCRIPT_DIR/validation/16-verify-landing-zones.sh"

# Step 16: Wait for all apps to be healthy
step "Waiting for all applications to be healthy..."
if [ "$MODE" = "preview" ]; then
    "$SCRIPT_DIR/wait/12a-wait-apps-healthy.sh" --timeout 600 --preview-mode
else
    "$SCRIPT_DIR/wait/12a-wait-apps-healthy.sh" --timeout 600
fi

# Wait for service dependencies (not counted as separate step)
echo -e "${BLUE}Waiting for platform services to be ready...${NC}"
if [ "$MODE" = "preview" ]; then
    "$SCRIPT_DIR/wait/13-wait-service-dependencies.sh" --timeout 300 --preview-mode
else
    "$SCRIPT_DIR/wait/13-wait-service-dependencies.sh" --timeout 300
fi

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
    if [[ -z "$CI" ]]; then
        echo -e "  Password: ${YELLOW}$ARGOCD_PASSWORD${NC}"
    else
        echo -e "  Password: ${YELLOW}***MASKED*** (saved to credentials file)${NC}"
    fi
    echo ""
fi

if [ "$MODE" = "production" ]; then
    # Configure repository credentials
    step "Configuring repository credentials..."
    "$SCRIPT_DIR/install/13-configure-repo-credentials.sh" --auto || {
        echo -e "${YELLOW}⚠️  Repository credentials configuration had issues${NC}"
        echo -e "${BLUE}ℹ  You can configure manually: ./scripts/bootstrap/install/13-configure-repo-credentials.sh --auto${NC}"
    }

    "$SCRIPT_DIR/helpers/add-credentials.sh" "$CREDENTIALS_FILE" "ARGOCD REPOSITORY CREDENTIALS" "Repository credentials managed via ExternalSecrets from AWS SSM

Verify:
  kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository
  kubectl get externalsecret -n argocd"
else
    skip_step "Repository credentials configuration (preview mode)"
fi

# Final cluster validation
if [ "$MODE" = "production" ]; then
    echo -e "${YELLOW}Running final cluster validation...${NC}"
else
    echo -e "${BLUE}Skipping final cluster validation (preview mode)${NC}"
fi
"$SCRIPT_DIR/validation/99-validate-cluster.sh" || {
    echo -e "${YELLOW}⚠️  Cluster validation found issues${NC}"
    echo -e "${BLUE}ℹ  Check ArgoCD applications: kubectl get applications -n argocd${NC}"
}

# ============================================================================
# BOOTSTRAP COMPLETE
# ============================================================================

"$SCRIPT_DIR/99-bootstrap-complete.sh" "$MODE" "${CREDENTIALS_FILE:-}" "${SERVER_IP:-}" "${WORKER_NODES:-}"

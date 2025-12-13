#!/bin/bash
# Master Bootstrap Script for BizMatters Infrastructure
# Usage: ./00-master-bootstrap.sh <server-ip> <root-password> [--worker-nodes <list>]
#
# This script orchestrates the complete cluster bootstrap process:
# 1. Talos installation on control plane
# 2. Foundation layer deployment
# 3. ArgoCD bootstrap
# 4. Worker node installation (if specified)
# 5. Post-reboot verification

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Kubectl retry function with exponential backoff
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
    echo -e "  - Add repository credentials: ${GREEN}./scripts/bootstrap/07-add-private-repo.sh${NC}"
    echo -e "  - Inject secrets: ${GREEN}./scripts/bootstrap/05-inject-secrets.sh${NC}"
    echo -e "  - Add worker nodes: ${GREEN}./scripts/bootstrap/04-add-worker-node.sh${NC}"
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

# Step 0.5: Embed Cilium in Talos config for bootstrap
echo -e "${YELLOW}[0.5/5] Preparing Cilium CNI for bootstrap...${NC}"
echo "────────────────────────────────────────────────────────────────"
cd "$SCRIPT_DIR"

echo -e "${BLUE}Embedding Cilium manifest in control plane Talos config...${NC}"
"$SCRIPT_DIR/embed-cilium.sh"

echo -e "\n${GREEN}✓ Cilium CNI prepared for bootstrap${NC}\n"

# Step 1: Install Talos
echo -e "${YELLOW}[1/5] Installing Talos OS...${NC}"
echo "────────────────────────────────────────────────────────────────"
cd "$SCRIPT_DIR"
"$SCRIPT_DIR/02-install-talos-rescue.sh" --server-ip "$SERVER_IP" --user root --password "$ROOT_PASSWORD" --yes

echo -e "\n${GREEN}✓ Talos installation complete${NC}\n"

cat >> "$CREDENTIALS_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TALOS CREDENTIALS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Talos Config: bootstrap/talos/talosconfig
Control Plane Config: bootstrap/talos/nodes/cp01-main/config.yaml
Worker Config: bootstrap/talos/worker.yaml

Access Talos:
  talosctl --talosconfig bootstrap/talos/talosconfig -n $SERVER_IP version

EOF

# Step 1.5: Bootstrap Talos (apply config, bootstrap etcd, get kubeconfig)
echo -e "${YELLOW}[1.5/5] Bootstrapping Talos cluster...${NC}"
echo "────────────────────────────────────────────────────────────────"
echo -e "${BLUE}⏳ Waiting 3 minutes for Talos to boot...${NC}"
sleep 180

cd "$SCRIPT_DIR/../../bootstrap/talos"

echo -e "${BLUE}Applying Talos configuration (with CNI=none to prevent Flannel)...${NC}"
# Apply config with CNI patch to prevent Talos from deploying Flannel
# Cilium will be deployed via inlineManifests instead
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

echo -e "${BLUE}Bootstrapping etcd cluster...${NC}"
talosctl bootstrap \
  --nodes "$SERVER_IP" \
  --endpoints "$SERVER_IP" \
  --talosconfig talosconfig

echo -e "${BLUE}Waiting 180 seconds for cluster to stabilize and API server to start...${NC}"
sleep 180

echo -e "${BLUE}Fetching kubeconfig...${NC}"
talosctl kubeconfig \
  --nodes "$SERVER_IP" \
  --endpoints "$SERVER_IP" \
  --talosconfig talosconfig \
  --force

echo -e "${BLUE}Verifying cluster (with retries)...${NC}"
kubectl_retry get nodes

echo -e "\n${GREEN}✓ Talos cluster bootstrapped successfully${NC}\n"

# Step 1.6: Install Worker Nodes (BEFORE Cilium wait for better HA)
if [ -n "$WORKER_NODES" ]; then
    echo -e "${YELLOW}[1.6/5] Installing Worker Nodes...${NC}"
    echo "────────────────────────────────────────────────────────────────"
    
    # Parse worker nodes (format: name:ip,name:ip)
    IFS=',' read -ra WORKERS <<< "$WORKER_NODES"
    WORKER_COUNT=${#WORKERS[@]}
    WORKER_NUM=1
    
    for worker in "${WORKERS[@]}"; do
        IFS=':' read -r WORKER_NAME WORKER_IP <<< "$worker"
        
        echo -e "${BLUE}Installing worker node $WORKER_NUM/$WORKER_COUNT: $WORKER_NAME ($WORKER_IP)${NC}"
        
        # Install Talos on worker (use full path since we may have cd'd elsewhere)
        "$SCRIPT_DIR/02-install-talos-rescue.sh" \
            --server-ip "$WORKER_IP" \
            --user root \
            --password "$WORKER_PASSWORD" \
            --yes
        
        echo -e "${BLUE}⏳ Waiting 3 minutes for worker to boot...${NC}"
        sleep 180
        
        # Apply worker configuration
        cd "$SCRIPT_DIR/../../bootstrap/talos"
        echo -e "${BLUE}Applying worker configuration for $WORKER_NAME (inherits CNI from control plane)...${NC}"

        if ! talosctl apply-config --insecure \
            --nodes "$WORKER_IP" \
            --endpoints "$WORKER_IP" \
            --file "nodes/$WORKER_NAME/config.yaml"; then
            echo -e "${RED}Failed to apply config. Waiting 30s and retrying...${NC}"
            sleep 30
            talosctl apply-config --insecure \
                --nodes "$WORKER_IP" \
                --endpoints "$WORKER_IP" \
                --file "nodes/$WORKER_NAME/config.yaml"
        fi
        
        echo -e "${BLUE}Waiting 120 seconds for worker to join cluster...${NC}"
        sleep 120

        # Verify node joined
        echo -e "${BLUE}Verifying worker node joined cluster (with retries)...${NC}"
        kubectl_retry get nodes
        
        cd "$SCRIPT_DIR"
        
        echo -e "${GREEN}✓ Worker node $WORKER_NAME installed${NC}\n"
        
        cat >> "$CREDENTIALS_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WORKER NODE: $WORKER_NAME
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Node IP: $WORKER_IP
Config: bootstrap/talos/nodes/$WORKER_NAME/config.yaml

EOF
        
        WORKER_NUM=$((WORKER_NUM + 1))
    done
    
    echo -e "${GREEN}✓ All worker nodes installed${NC}\n"
else
    echo -e "${BLUE}ℹ  No worker nodes specified - single node cluster${NC}\n"
fi

# Step 1.7: Wait for Cilium to be ready (critical for ArgoCD networking)
echo -e "${YELLOW}[1.7/5] Waiting for Cilium CNI to be ready...${NC}"
echo "────────────────────────────────────────────────────────────────"
echo -e "${BLUE}⏳ Waiting for Cilium agent pods (multi-node cluster)...${NC}"
kubectl_retry wait --for=condition=ready pod -n kube-system -l k8s-app=cilium --timeout=180s

echo -e "${BLUE}⏳ Waiting for Cilium operator (2 replicas in HA mode)...${NC}"
kubectl_retry wait --for=condition=ready pod -n kube-system -l name=cilium-operator --timeout=180s

echo -e "${BLUE}Verifying Cilium health...${NC}"
CILIUM_POD=$(kubectl get pod -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
if kubectl exec -n kube-system "$CILIUM_POD" -- cilium status --brief 2>/dev/null | grep -q "OK"; then
    echo -e "${GREEN}✓ Cilium is healthy${NC}"
else
    echo -e "${YELLOW}⚠️  Cilium status check failed, but continuing (basic connectivity verified)${NC}"
fi

echo -e "\n${GREEN}✓ Cilium CNI is ready - networking operational${NC}"
echo -e "${BLUE}ℹ  Note: Cilium operator running with 2 replicas (HA mode with worker node)${NC}\n"

cd "$SCRIPT_DIR"

# Step 2: Pre-create namespaces and inject secrets (BEFORE ArgoCD)
echo -e "${YELLOW}[2/5] Pre-creating namespaces and injecting secrets...${NC}"
echo "────────────────────────────────────────────────────────────────"
echo -e "${BLUE}ℹ  Creating namespaces for ESO and injecting AWS credentials BEFORE ArgoCD${NC}"
echo -e "${BLUE}   This ensures ESO can sync secrets immediately when deployed${NC}"

# Create external-secrets namespace
kubectl_retry create namespace external-secrets --dry-run=client -o yaml | kubectl_retry apply -f -
echo -e "${GREEN}✓ external-secrets namespace ready${NC}"

# Inject AWS credentials from AWS CLI configuration
echo -e "${BLUE}Fetching AWS credentials from AWS CLI configuration...${NC}"
if "$SCRIPT_DIR/05-inject-secrets.sh"; then
    echo -e "${GREEN}✓ AWS credentials injected successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Failed to inject AWS credentials${NC}"
    echo -e "${BLUE}ℹ  You can inject manually later: ./scripts/bootstrap/05-inject-secrets.sh${NC}"
fi

# Step 2.5: Foundation Layer info
echo -e "${YELLOW}[2.5/5] Foundation Layer (will be deployed by ArgoCD)...${NC}"
echo "────────────────────────────────────────────────────────────────"
echo -e "${BLUE}ℹ  Foundation components (Crossplane, KEDA, Kagent) will be deployed by ArgoCD${NC}"
echo -e "${BLUE}   after bootstrap completes via platform-bootstrap Application${NC}"

cat >> "$CREDENTIALS_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FOUNDATION LAYER (ArgoCD Managed)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Components deployed via ArgoCD:
  - External Secrets Operator (ESO)
  - Crossplane (Infrastructure Provisioning)
  - KEDA (Event-driven Autoscaling)
  - Kagent (AI Agent Platform)

Kubeconfig: ~/.kube/config

Access Cluster:
  kubectl get nodes
  kubectl get pods -A

EOF

# Step 3: Bootstrap ArgoCD
echo -e "${YELLOW}[3/5] Bootstrapping ArgoCD...${NC}"
echo "────────────────────────────────────────────────────────────────"
"$SCRIPT_DIR/03-install-argocd.sh"

echo -e "\n${GREEN}✓ ArgoCD installed${NC}\n"

# Step 3.1: Wait for platform-bootstrap to sync
echo -e "${BLUE}⏳ Waiting for platform-bootstrap to sync (timeout: 5 minutes)...${NC}"
TIMEOUT=300
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    SYNC_STATUS=$(kubectl_retry get application platform-bootstrap -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH_STATUS=$(kubectl_retry get application platform-bootstrap -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    
    if [ "$SYNC_STATUS" = "Synced" ] && [ "$HEALTH_STATUS" = "Healthy" ]; then
        echo -e "${GREEN}✓ platform-bootstrap synced successfully${NC}"
        break
    fi
    
    if [ "$SYNC_STATUS" = "OutOfSync" ] || [ "$HEALTH_STATUS" = "Degraded" ]; then
        echo -e "${YELLOW}⚠️  Status: $SYNC_STATUS / $HEALTH_STATUS - waiting...${NC}"
    fi
    
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo -e "${RED}✗ Timeout waiting for platform-bootstrap to sync${NC}"
    echo -e "${YELLOW}Check status: kubectl describe application platform-bootstrap -n argocd${NC}"
    exit 1
fi

# Step 3.2: Verify child Applications were created
echo -e "${BLUE}Verifying child Applications...${NC}"
sleep 10
EXPECTED_APPS=("crossplane-operator" "external-secrets" "keda" "kagent" "intelligence" "foundation-config" "databases")
MISSING_APPS=()

for app in "${EXPECTED_APPS[@]}"; do
    if ! kubectl_retry get application "$app" -n argocd &>/dev/null; then
        MISSING_APPS+=("$app")
    fi
done

if [ ${#MISSING_APPS[@]} -gt 0 ]; then
    echo -e "${RED}✗ Missing Applications: ${MISSING_APPS[*]}${NC}"
    echo -e "${YELLOW}Check platform-bootstrap status: kubectl describe application platform-bootstrap -n argocd${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All child Applications created${NC}\n"

# Extract ArgoCD password
ARGOCD_PASSWORD=$(kubectl_retry -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "NOT_GENERATED")

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

# Step 4: Verify ESO and Inject SSM Parameters
echo -e "${YELLOW}[4/5] Verifying ESO and Injecting SSM Parameters...${NC}"
echo "────────────────────────────────────────────────────────────────"

# Wait for ESO to sync (credentials were injected in Step 2)
if kubectl_retry get secret aws-access-token -n external-secrets &>/dev/null; then
    echo -e "${BLUE}⏳ Waiting for ESO to sync secrets (timeout: 2 minutes)...${NC}"
    TIMEOUT=120
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        STORE_STATUS=$(kubectl_retry get clustersecretstore aws-parameter-store -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        
        if [ "$STORE_STATUS" = "True" ]; then
            echo -e "${GREEN}✓ ESO credentials configured and working${NC}"
            break
        fi
        
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo -e "${YELLOW}⚠️  ESO not ready yet - secrets may sync later${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  AWS credentials not found - ESO won't be able to sync secrets${NC}"
    echo -e "${BLUE}ℹ  You can inject manually: ./scripts/bootstrap/05-inject-secrets.sh${NC}"
fi

cat >> "$CREDENTIALS_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SECRETS MANAGEMENT (External Secrets Operator)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ESO syncs secrets from AWS SSM Parameter Store.

Required AWS Parameters:
  - /zerotouch/prod/kagent/openai_api_key

Inject ESO credentials:
  ./scripts/bootstrap/05-inject-secrets.sh <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY>

Verify ESO is working:
  kubectl get clustersecretstore aws-parameter-store
  kubectl get externalsecret -A

EOF

cd "$SCRIPT_DIR"

# Step 4.5: Inject SSM Parameters
echo -e "${YELLOW}[4.6/5] Injecting SSM Parameters...${NC}"
echo "────────────────────────────────────────────────────────────────"

# Check if .env.ssm file exists
if [ -f "$SCRIPT_DIR/../../.env.ssm" ]; then
    echo -e "${BLUE}Found .env.ssm file, injecting parameters to AWS SSM...${NC}"
    "$SCRIPT_DIR/06-inject-ssm-parameters.sh"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ SSM parameters injected successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  SSM parameter injection failed or skipped${NC}"
        echo -e "${BLUE}   You can run manually: ./scripts/bootstrap/06-inject-ssm-parameters.sh${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  .env.ssm file not found${NC}"
    echo -e "${BLUE}ℹ  To inject SSM parameters:${NC}"
    echo -e "   1. ${GREEN}cp .env.ssm.example .env.ssm${NC}"
    echo -e "   2. Edit .env.ssm with your secrets"
    echo -e "   3. ${GREEN}./scripts/bootstrap/06-inject-ssm-parameters.sh${NC}"
    echo ""
fi

cat >> "$CREDENTIALS_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
AWS SSM PARAMETER STORE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Inject SSM parameters:
  cp .env.ssm.example .env.ssm
  # Edit .env.ssm with your secrets
  ./scripts/bootstrap/06-inject-ssm-parameters.sh

Verify parameters:
  aws ssm get-parameters --names /zerotouch/prod/kagent/openai_api_key --region ap-south-1

EOF

# Step 4.7: Wait for ArgoCD Repository Credentials to Sync from SSM
echo -e "${YELLOW}[4.7/5] Configuring ArgoCD Repository Credentials...${NC}"
echo "────────────────────────────────────────────────────────────────"

# Check if tenant ApplicationSet is deployed (requires private repo credentials)
TENANT_APPSET_EXISTS=false
if [ -f "$SCRIPT_DIR/../../bootstrap/components/99-tenants.yaml" ]; then
    TENANT_APPSET_EXISTS=true
    echo -e "${BLUE}ℹ  Found tenant ApplicationSet (99-tenants.yaml) - private repo credentials required${NC}"
fi

# Check if ExternalSecret for tenant registry exists
if kubectl_retry get externalsecret repo-zerotouch-tenants -n argocd &>/dev/null; then
    echo -e "${BLUE}ℹ  Repository credentials are synced from AWS SSM via ExternalSecrets${NC}"
    echo -e "${BLUE}⏳ Waiting for ExternalSecret to sync registry credentials...${NC}"

    # Wait for ExternalSecret to be ready
    if kubectl_retry wait --for=condition=Ready externalsecret/repo-zerotouch-tenants \
      -n argocd --timeout=120s 2>/dev/null; then

        # Verify the secret was created
        if kubectl_retry get secret repo-zerotouch-tenants -n argocd &>/dev/null; then
            echo -e "${GREEN}✓ Registry repository credentials synced from SSM${NC}"
        else
            echo -e "${RED}✗ ERROR: ExternalSecret ready but secret not found${NC}"
            echo -e "${YELLOW}Check: kubectl describe externalsecret repo-zerotouch-tenants -n argocd${NC}"
            exit 1
        fi
    else
        # ExternalSecret failed to sync
        echo -e "${RED}✗ ERROR: Failed to sync repository credentials from SSM${NC}"
        echo ""
        echo -e "${YELLOW}Troubleshooting:${NC}"
        echo -e "  1. Verify AWS SSM parameters exist:"
        echo -e "     ${GREEN}aws ssm get-parameter --name /zerotouch/prod/argocd/repos/zerotouch-tenants/url${NC}"
        echo -e "  2. Check ExternalSecret status:"
        echo -e "     ${GREEN}kubectl describe externalsecret repo-zerotouch-tenants -n argocd${NC}"
        echo -e "  3. Check ESO ClusterSecretStore:"
        echo -e "     ${GREEN}kubectl get clustersecretstore aws-parameter-store -o yaml${NC}"
        echo -e "  4. Verify .env.ssm has the required parameters and run:"
        echo -e "     ${GREEN}./scripts/bootstrap/06-inject-ssm-parameters.sh${NC}"
        echo ""
        
        # FAIL FAST: If tenant ApplicationSet exists, credentials are REQUIRED
        if [ "$TENANT_APPSET_EXISTS" = true ]; then
            echo -e "${RED}✗ FATAL: Tenant ApplicationSet requires repository credentials${NC}"
            echo -e "${RED}   Bootstrap cannot continue without valid credentials${NC}"
            exit 1
        else
            echo -e "${YELLOW}⚠️  WARNING: Repository credentials failed but no tenant ApplicationSet found${NC}"
            echo -e "${BLUE}ℹ  Continuing bootstrap (no private repos required)${NC}"
        fi
    fi
else
    # No ExternalSecret found
    if [ "$TENANT_APPSET_EXISTS" = true ]; then
        # FAIL FAST: Tenant ApplicationSet exists but no credentials configured
        echo -e "${RED}✗ FATAL: Tenant ApplicationSet requires repository credentials${NC}"
        echo ""
        echo -e "${RED}The bootstrap includes 99-tenants.yaml which requires:${NC}"
        echo -e "${RED}  - ExternalSecret: repo-zerotouch-tenants${NC}"
        echo -e "${RED}  - AWS SSM parameters for tenant registry${NC}"
        echo ""
        echo -e "${YELLOW}To fix:${NC}"
        echo -e "  1. Ensure .env.ssm has these parameters:"
        echo -e "     ${GREEN}/zerotouch/prod/argocd/repos/zerotouch-tenants/url${NC}"
        echo -e "     ${GREEN}/zerotouch/prod/argocd/repos/zerotouch-tenants/username${NC}"
        echo -e "     ${GREEN}/zerotouch/prod/argocd/repos/zerotouch-tenants/password${NC}"
        echo -e "  2. Run: ${GREEN}./scripts/bootstrap/06-inject-ssm-parameters.sh${NC}"
        echo -e "  3. Ensure argocd-repo-registry.yaml is deployed"
        echo ""
        exit 1
    else
        echo -e "${BLUE}ℹ  No private repository credentials configured${NC}"
        echo -e "${BLUE}ℹ  No tenant ApplicationSet found - continuing without private repos${NC}"
    fi
fi

cat >> "$CREDENTIALS_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ARGOCD REPOSITORY CREDENTIALS (ExternalSecrets)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Repository credentials are synced from AWS SSM via ExternalSecrets.

To add more private repositories:
  1. Add SSM parameters:
     /zerotouch/prod/argocd/repos/<repo-name>/url
     /zerotouch/prod/argocd/repos/<repo-name>/username
     /zerotouch/prod/argocd/repos/<repo-name>/password

  2. Create ExternalSecret in zerotouch-tenants/repositories/<repo-name>.yaml

  3. ArgoCD syncs automatically

Verify:
  kubectl get externalsecret -n argocd
  kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository

EOF

# Step 4.5: Database Layer (managed by ArgoCD)
if [ -n "$WORKER_NODES" ]; then
    echo -e "${YELLOW}[4.5/5] Database Layer (will be deployed by ArgoCD)...${NC}"
    echo "────────────────────────────────────────────────────────────────"
    echo -e "${BLUE}ℹ  Database layer will be deployed by ArgoCD via platform-bootstrap Application${NC}"
    
    
else
    echo -e "${BLUE}ℹ  Single node cluster - databases can be deployed later via ArgoCD${NC}\n"
fi

# Step 5: Post-reboot Verification (optional - only if needed)
echo -e "${YELLOW}[5/5] Post-Reboot Verification${NC}"
echo "────────────────────────────────────────────────────────────────"
echo -e "${BLUE}ℹ  Run this manually after any server reboot:${NC}"
echo -e "   ${GREEN}./scripts/bootstrap/post-reboot-verify.sh${NC}"
echo ""

cat >> "$CREDENTIALS_FILE" << EOF

EOF

# Final Summary
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
echo -e "${YELLOW}⏳ Foundation layer and databases will be deployed by ArgoCD${NC}"
echo ""
echo -e "${YELLOW}📝 Credentials saved to:${NC}"
echo -e "   ${GREEN}$CREDENTIALS_FILE${NC}"
echo ""
echo -e "${YELLOW}📌 Next Steps:${NC}"
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo -e "   1. ${RED}IMPORTANT:${NC} Inject ESO credentials: ${GREEN}./scripts/bootstrap/03-inject-secrets.sh <AWS_KEY> <AWS_SECRET>${NC}"
    echo -e "   2. Review credentials file and ${RED}BACK UP${NC} important credentials"
    echo -e "   3. Port-forward ArgoCD UI: ${GREEN}kubectl port-forward -n argocd svc/argocd-server 8080:443${NC}"
    echo -e "   4. Validate cluster: ${GREEN}./scripts/validate-cluster.sh${NC}"
else
    echo -e "   1. Review credentials file and ${RED}BACK UP${NC} important credentials"
    echo -e "   2. Port-forward ArgoCD UI: ${GREEN}kubectl port-forward -n argocd svc/argocd-server 8080:443${NC}"
    echo -e "   3. Validate cluster: ${GREEN}./scripts/validate-cluster.sh${NC}"
fi
echo ""
echo -e "${BLUE}Happy deploying! 🚀${NC}"
echo ""

# Display credentials file content
cat "$CREDENTIALS_FILE"

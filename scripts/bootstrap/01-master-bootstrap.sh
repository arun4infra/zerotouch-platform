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

# Step 1: Install Talos
echo -e "${YELLOW}[1/5] Installing Talos OS...${NC}"
echo "────────────────────────────────────────────────────────────────"
cd "$SCRIPT_DIR"
./02-install-talos-rescue.sh --server-ip "$SERVER_IP" --user root --password "$ROOT_PASSWORD" --yes

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

echo -e "${BLUE}Applying Talos configuration...${NC}"
if ! talosctl apply-config --insecure \
  --nodes "$SERVER_IP" \
  --endpoints "$SERVER_IP" \
  --file nodes/cp01-main/config.yaml; then
    echo -e "${RED}Failed to apply Talos config. Waiting 30s and retrying...${NC}"
    sleep 30
    talosctl apply-config --insecure \
      --nodes "$SERVER_IP" \
      --endpoints "$SERVER_IP" \
      --file nodes/cp01-main/config.yaml
fi

echo -e "${BLUE}Waiting 30 seconds for config to apply...${NC}"
sleep 30

echo -e "${BLUE}Bootstrapping etcd cluster...${NC}"
talosctl bootstrap \
  --nodes "$SERVER_IP" \
  --endpoints "$SERVER_IP" \
  --talosconfig talosconfig

echo -e "${BLUE}Waiting 60 seconds for cluster to stabilize...${NC}"
sleep 60

echo -e "${BLUE}Fetching kubeconfig...${NC}"
talosctl kubeconfig \
  --nodes "$SERVER_IP" \
  --endpoints "$SERVER_IP" \
  --talosconfig talosconfig \
  --force

echo -e "${BLUE}Verifying cluster...${NC}"
kubectl get nodes

echo -e "\n${GREEN}✓ Talos cluster bootstrapped successfully${NC}\n"

cd "$SCRIPT_DIR"

# Step 2: Foundation Layer (managed by ArgoCD)
echo -e "${YELLOW}[2/5] Foundation Layer (will be deployed by ArgoCD)...${NC}"
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
./03-install-argocd.sh

echo -e "\n${GREEN}✓ ArgoCD bootstrap complete${NC}\n"

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

# Step 3.5: Install Worker Nodes (if specified)
if [ -n "$WORKER_NODES" ]; then
    echo -e "${YELLOW}[3.5/5] Installing Worker Nodes...${NC}"
    echo "────────────────────────────────────────────────────────────────"
    
    # Parse worker nodes (format: name:ip,name:ip)
    IFS=',' read -ra WORKERS <<< "$WORKER_NODES"
    WORKER_COUNT=${#WORKERS[@]}
    WORKER_NUM=1
    
    for worker in "${WORKERS[@]}"; do
        IFS=':' read -r WORKER_NAME WORKER_IP <<< "$worker"
        
        echo -e "${BLUE}Installing worker node $WORKER_NUM/$WORKER_COUNT: $WORKER_NAME ($WORKER_IP)${NC}"
        
        # Install Talos on worker
        ./02-install-talos-rescue.sh \
            --server-ip "$WORKER_IP" \
            --user root \
            --password "$WORKER_PASSWORD" \
            --yes
        
        echo -e "${BLUE}⏳ Waiting 3 minutes for worker to boot...${NC}"
        sleep 180
        
        # Apply worker configuration
        cd "$SCRIPT_DIR/../../bootstrap/talos"
        echo -e "${BLUE}Applying worker configuration for $WORKER_NAME...${NC}"
        
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
        
        echo -e "${BLUE}Waiting 60 seconds for worker to join cluster...${NC}"
        sleep 60
        
        # Verify node joined
        echo -e "${BLUE}Verifying worker node joined cluster...${NC}"
        kubectl get nodes
        
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

# Step 4: Inject ESO Bootstrap Secret
echo -e "${YELLOW}[4/5] Injecting ESO Bootstrap Secret...${NC}"
echo "────────────────────────────────────────────────────────────────"
echo -e "${BLUE}ℹ  You need to manually inject AWS credentials for External Secrets Operator${NC}"
echo -e "${BLUE}   Run: ./scripts/bootstrap/03-inject-secrets.sh <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY>${NC}"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: ESO needs AWS credentials to sync secrets from Parameter Store${NC}"
echo ""

cat >> "$CREDENTIALS_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SECRETS MANAGEMENT (External Secrets Operator)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ESO syncs secrets from AWS SSM Parameter Store.

Required AWS Parameters:
  - /zerotouch/prod/kagent/openai_api_key

Inject ESO credentials:
  ./scripts/bootstrap/03-inject-secrets.sh <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY>

Verify ESO is working:
  kubectl get clustersecretstore aws-parameter-store
  kubectl get externalsecret -A

EOF

cd "$SCRIPT_DIR"

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
echo -e "   1. Review credentials file and ${RED}BACK UP${NC} important credentials"
echo -e "   2. Inject ESO credentials: ${GREEN}./scripts/bootstrap/03-inject-secrets.sh <AWS_KEY> <AWS_SECRET>${NC}"
echo -e "   3. Port-forward ArgoCD UI: ${GREEN}kubectl port-forward -n argocd svc/argocd-server 8080:443${NC}"
echo -e "   4. Wait for ArgoCD to deploy all applications (check with: ${GREEN}kubectl get applications -n argocd${NC})"
echo -e "   5. Validate cluster: ${GREEN}./scripts/validate-cluster.sh${NC}"
echo ""
echo -e "${BLUE}Happy deploying! 🚀${NC}"
echo ""

# Display credentials file content
cat "$CREDENTIALS_FILE"

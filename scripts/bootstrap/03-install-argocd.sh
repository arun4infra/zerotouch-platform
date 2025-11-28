#!/bin/bash
set -e

# ArgoCD Bootstrap Script
# Installs ArgoCD and kicks off GitOps deployment
# Prerequisites: Talos cluster must be running and kubectl configured

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ARGOCD_VERSION="v3.2.0"  # Latest stable as of 2024-11-24
ARGOCD_NAMESPACE="argocd"
ROOT_APP_PATH="bootstrap/root.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}==>${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
log_info "════════════════════════════════════════════════════════"
log_info "ArgoCD Bootstrap Script"
log_info "════════════════════════════════════════════════════════"

log_step "Checking prerequisites..."

if ! command_exists kubectl; then
    log_error "kubectl is not installed"
    exit 1
fi

if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot connect to Kubernetes cluster. Is kubectl configured?"
    exit 1
fi

log_info "✓ kubectl configured and cluster accessible"

# Display cluster info
CLUSTER_NAME=$(kubectl config current-context)
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')

log_info "Cluster: $CLUSTER_NAME"
log_info "Nodes: $NODE_COUNT"

# Step 1: Install ArgoCD
log_info ""
log_step "Step 1/5: Installing ArgoCD..."

if kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
    log_warn "ArgoCD namespace already exists"
else
    log_info "Creating ArgoCD namespace..."
    kubectl create namespace "$ARGOCD_NAMESPACE"
fi

log_info "Applying ArgoCD manifests (version: $ARGOCD_VERSION)..."
kubectl apply -n "$ARGOCD_NAMESPACE" -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml"

log_info "✓ ArgoCD manifests applied"

# Step 2: Wait for ArgoCD to be ready
log_info ""
log_step "Step 2/5: Waiting for ArgoCD to be ready..."

# Give Kubernetes a moment to create the pods
log_info "Waiting for pods to be created..."
sleep 10

log_info "Waiting for ArgoCD pods (timeout: 5 minutes)..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=argocd-server \
    -n "$ARGOCD_NAMESPACE" \
    --timeout=300s

log_info "✓ ArgoCD is ready"

# Step 2.5: Grant ArgoCD cluster-admin permissions
log_info ""
log_step "Step 2.5/6: Granting ArgoCD cluster-admin permissions..."

log_info "Applying cluster-admin RBAC patch..."
kubectl apply -f "$REPO_ROOT/bootstrap/argocd-admin-patch.yaml"

log_info "✓ ArgoCD has cluster-admin permissions (required for namespace creation)"

# Step 3: Configure repository credentials
log_info ""
log_step "Step 3/7: Configuring repository credentials..."

# GitHub credentials - use public repo (no auth needed for public repos)
GITHUB_REPO_URL="https://github.com/arun4infra/zerotouch-infra.git"
GITHUB_USERNAME="arun4infra"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"  # Optional: set via environment variable if needed

if kubectl get secret repo-credentials -n "$ARGOCD_NAMESPACE" &>/dev/null; then
    log_warn "Repository credentials already exist, skipping..."
else
    log_info "Creating repository credentials secret..."
    kubectl create secret generic repo-credentials -n "$ARGOCD_NAMESPACE" \
        --from-literal=url="$GITHUB_REPO_URL" \
        --from-literal=username="$GITHUB_USERNAME" \
        --from-literal=password="$GITHUB_TOKEN" \
        --from-literal=type=git \
        --from-literal=project=default

    kubectl label secret repo-credentials -n "$ARGOCD_NAMESPACE" \
        argocd.argoproj.io/secret-type=repository

    log_info "✓ Repository credentials configured"
fi

# Step 4: Get initial admin password
log_info ""
log_step "Step 4/7: Retrieving ArgoCD credentials..."

ARGOCD_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

if [[ -z "$ARGOCD_PASSWORD" ]]; then
    log_warn "Could not retrieve ArgoCD password (might be using external auth)"
else
    log_info "✓ ArgoCD credentials retrieved"
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "ArgoCD Login Credentials:"
    echo -e "  ${YELLOW}Username:${NC} admin"
    echo -e "  ${YELLOW}Password:${NC} $ARGOCD_PASSWORD"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi

# Step 5: Deploy root application
log_info ""
log_step "Step 5/7: Deploying root application (GitOps)..."

if [[ ! -f "$REPO_ROOT/$ROOT_APP_PATH" ]]; then
    log_error "Root application not found at: $REPO_ROOT/$ROOT_APP_PATH"
    exit 1
fi

log_info "Applying root application..."
kubectl apply --server-side -f "$REPO_ROOT/$ROOT_APP_PATH"

log_info "✓ Root application deployed"

# Step 6: Wait for initial sync
log_info ""
log_step "Step 6/7: Waiting for initial sync..."

sleep 5  # Give ArgoCD time to detect the application

log_info "Checking ArgoCD applications..."
kubectl get applications -n "$ARGOCD_NAMESPACE"

log_info ""
log_info "✓ GitOps deployment initiated!"

# Final instructions
cat << EOF

${GREEN}════════════════════════════════════════════════════════${NC}
${GREEN}✓ ArgoCD Bootstrap Completed Successfully!${NC}
${GREEN}════════════════════════════════════════════════════════${NC}

${YELLOW}What's Happening Now:${NC}
- ArgoCD is syncing the platform from Git
- Foundation layer (Cilium, Crossplane, KEDA, Kagent) will deploy first
- Intelligence layer (Qdrant, docs-mcp, Librarian Agent) will deploy next
- Observability and APIs layers are DISABLED (as configured)

${YELLOW}Monitor Deployment:${NC}

1. ${BLUE}Watch ArgoCD applications:${NC}
   kubectl get applications -n argocd -w

2. ${BLUE}Access ArgoCD UI:${NC}
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   
   Then open: https://localhost:8080
   Username: admin
   Password: $ARGOCD_PASSWORD

3. ${BLUE}Check specific layers:${NC}
   # Foundation layer
   kubectl get pods -n kube-system
   kubectl get pods -n crossplane-system
   kubectl get pods -n kagent
   
   # Intelligence layer
   kubectl get pods -n intelligence

4. ${BLUE}View ArgoCD sync status:${NC}
   kubectl get applications -n argocd
   
   # Expected applications:
   # - platform-root (root app-of-apps)
   # - foundation
   # - intelligence

${YELLOW}Troubleshooting:${NC}
- If applications show "OutOfSync", they may be syncing
- If applications show "Degraded", check pod status
- View application details: kubectl describe application <name> -n argocd
- View ArgoCD logs: kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

${YELLOW}Next Steps:${NC}
1. Wait 5-10 minutes for all components to sync and become healthy
2. Verify foundation layer is running
3. Verify intelligence layer components are deployed
4. Create required secrets (GitHub token, OpenAI key) for intelligence layer

${GREEN}Documentation:${NC}
- ArgoCD: https://argo-cd.readthedocs.io/
- Platform walkthrough: See walkthrough.md artifact

EOF

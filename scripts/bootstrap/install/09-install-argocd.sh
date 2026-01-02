#!/bin/bash
set -e

# ArgoCD Bootstrap Script
# Installs ArgoCD and kicks off GitOps deployment
# Prerequisites: Talos cluster must be running and kubectl configured
# Usage: ./09-install-argocd.sh [MODE]
#   MODE: "production" or "preview" (optional, defaults to auto-detection)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ARGOCD_VERSION="v3.2.0"  # Latest stable as of 2024-11-24
ARGOCD_NAMESPACE="argocd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Find repository root by looking for .git directory
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR" && while [[ ! -d .git && $(pwd) != "/" ]]; do cd ..; done; pwd))"

# Parse mode parameter (first arg) and environment (second arg)
MODE="${1:-auto}"
ENVIRONMENT="${2:-dev}"

# Root application path - now using environment-specific overlays
if [ "$MODE" = "preview" ]; then
    ROOT_APP_OVERLAY="bootstrap/argocd/overlays/preview"
else
    # Use environment-specific overlay inside main (dev, staging, production)
    ROOT_APP_OVERLAY="bootstrap/argocd/overlays/main/$ENVIRONMENT"
fi

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

# Determine deployment mode
if [ "$MODE" = "preview" ]; then
    log_info "Applying ArgoCD manifests for preview mode (Kind cluster, version: $ARGOCD_VERSION)..."
    kubectl apply -k "$REPO_ROOT/bootstrap/argocd/install/preview"
elif [ "$MODE" = "production" ]; then
    log_info "Applying ArgoCD manifests for production mode (Talos cluster, version: $ARGOCD_VERSION)..."
    kubectl apply -k "$REPO_ROOT/bootstrap/argocd/install"
else
    # Auto-detection fallback
    log_info "Auto-detecting cluster type..."
    if kubectl get nodes -o jsonpath='{.items[*].spec.taints[?(@.key=="node-role.kubernetes.io/control-plane")]}' | grep -q "control-plane"; then
        log_info "Detected Talos cluster - applying ArgoCD manifests with control-plane tolerations (version: $ARGOCD_VERSION)..."
        kubectl apply -k "$REPO_ROOT/bootstrap/argocd/install"
    else
        log_info "Detected Kind cluster - applying ArgoCD manifests for preview mode (version: $ARGOCD_VERSION)..."
        kubectl apply -k "$REPO_ROOT/bootstrap/argocd/install/preview"
    fi
fi

log_info "✓ ArgoCD manifests applied successfully"

# Step 2: Wait for ArgoCD to be ready
log_info ""
log_step "Step 2/5: Waiting for ArgoCD to be ready..."

# Step 2a: Wait for ArgoCD pods
if ! "$REPO_ROOT/scripts/bootstrap/wait/09a-wait-argocd-pods.sh" --timeout 300 --namespace "$ARGOCD_NAMESPACE"; then
    log_error "ArgoCD pods failed to become ready"
    exit 1
fi

# Step 2b: Wait for repo server to be responsive
if ! "$REPO_ROOT/scripts/bootstrap/wait/09b-wait-argocd-repo-server.sh" --timeout 120 --namespace "$ARGOCD_NAMESPACE"; then
    log_error "ArgoCD repo server failed to become responsive"
    exit 1
fi

log_info "✓ ArgoCD is ready"

# Step 2.5: Grant ArgoCD cluster-admin permissions
log_info ""
log_step "Step 2.5/6: Granting ArgoCD cluster-admin permissions..."

log_info "Applying cluster-admin RBAC patch..."
kubectl apply -f "$REPO_ROOT/bootstrap/argocd/bootstrap-files/argocd-admin-patch.yaml"

log_info "✓ ArgoCD has cluster-admin permissions (required for namespace creation)"

# Step 3: Configure repository credentials
log_info ""
log_step "Step 3/7: Configuring repository credentials..."

# GitHub credentials - use BOT_GITHUB_* environment variables
if [[ -z "$BOT_GITHUB_USERNAME" ]]; then
    log_error "BOT_GITHUB_USERNAME environment variable is required"
    exit 1
fi
GITHUB_REPO_URL="https://github.com/${BOT_GITHUB_USERNAME}/zerotouch-platform.git"
GITHUB_USERNAME="${BOT_GITHUB_USERNAME}"
GITHUB_TOKEN="${BOT_GITHUB_TOKEN:-}"

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
    if [[ -z "$CI" ]]; then
        echo -e "  ${YELLOW}Password:${NC} $ARGOCD_PASSWORD"
    else
        echo -e "  ${YELLOW}Password:${NC} ***MASKED*** (CI mode)"
    fi
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi

# Step 4.5: Skipped - NATS will be created by ArgoCD with default storage class

# Step 5: Deploy root application using overlays
log_info ""
log_step "Step 5/7: Deploying platform via Kustomize overlay..."

if [[ ! -d "$REPO_ROOT/$ROOT_APP_OVERLAY" ]]; then
    log_error "Root application overlay not found at: $REPO_ROOT/$ROOT_APP_OVERLAY"
    exit 1
fi

if [ "$MODE" = "preview" ]; then
    log_info "Applying PREVIEW configuration (No Cilium, Local URLs)..."
else
    log_info "Applying PRODUCTION configuration (With Cilium, GitHub URLs)..."
fi

# Debug: Log overlay contents before applying
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "DEBUG: Verifying overlay configuration"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "Using overlay: $ROOT_APP_OVERLAY"

# Test the kustomization
log_info "Testing kustomization build..."
kubectl kustomize "$REPO_ROOT/$ROOT_APP_OVERLAY" > /tmp/kustomize-output.yaml
KUSTOMIZE_APPS=$(grep -c "kind: Application" /tmp/kustomize-output.yaml || echo "0")
log_info "  Generated $KUSTOMIZE_APPS Application resources"

if [ "$MODE" = "preview" ]; then
    LOCAL_COUNT=$(grep -c "file:///repo" /tmp/kustomize-output.yaml || echo "0")
    CILIUM_EXCLUDED=$(grep -c "exclude.*cilium" /tmp/kustomize-output.yaml || echo "0")
    log_info "  Local file URLs: $LOCAL_COUNT"
    log_info "  Cilium exclusions: $CILIUM_EXCLUDED"
else
    GITHUB_COUNT=$(grep -c "github.com" /tmp/kustomize-output.yaml || echo "0")
    CILIUM_APPS=$(grep -c "name: cilium" /tmp/kustomize-output.yaml || echo "0")
    log_info "  GitHub URLs: $GITHUB_COUNT"
    log_info "  Cilium applications: $CILIUM_APPS"
fi

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "Applying root application..."
kubectl apply --server-side -f "$REPO_ROOT/$ROOT_APP_OVERLAY/root.yaml"

log_info "✓ Platform definitions applied"

# Step 6: Wait for initial sync
log_info ""
log_step "Step 6/7: Waiting for initial sync..."

# Give ArgoCD time to detect and process the application
sleep 5

log_info "Checking ArgoCD applications..."
kubectl get applications -n "$ARGOCD_NAMESPACE"

log_info ""
log_info "✓ GitOps deployment initiated!"

# Final instructions
cat << EOF

${GREEN}════════════════════════════════════════════════════════${NC}
${GREEN}✓ ArgoCD Installation and Application Creation Completed!${NC}
${GREEN}════════════════════════════════════════════════════════${NC}

${YELLOW}What's Happening Now:${NC}
- ArgoCD applications have been created but are still syncing
- Applications may show "Unknown" status initially - this is normal
- Foundation layer (Cilium, Crossplane, KEDA, Kagent) will deploy first

${YELLOW}⚠️  Note: Applications are NOT yet synced - use the monitoring commands below${NC}

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

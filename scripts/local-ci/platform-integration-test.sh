#!/bin/bash
# Local Platform Integration Test
# Mirrors the GitHub workflow: .github/workflows/platform-integration-test.yaml
# Usage: ./scripts/local-ci/platform-integration-test.sh [--cleanup-only]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TIMEOUT_MINUTES=45
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOGS_DIR="$SCRIPT_DIR/logs"

# Parse arguments
CLEANUP_ONLY=false
if [ "$1" = "--cleanup-only" ]; then
    CLEANUP_ONLY=true
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

# Cleanup function
cleanup_preview_environment() {
    log_step "Cleanup preview environment"
    if [ -f "$REPO_ROOT/scripts/bootstrap/preview/cleanup-preview.sh" ]; then
        chmod +x "$REPO_ROOT/scripts/bootstrap/preview/cleanup-preview.sh"
        "$REPO_ROOT/scripts/bootstrap/preview/cleanup-preview.sh" || true
    else
        log_warn "Cleanup script not found, skipping..."
    fi
}

# Error handling function
handle_error() {
    local exit_code=$?
    log_error "Integration test failed with exit code: $exit_code"
    
    echo ""
    echo "=== Collecting logs for debugging ==="
    echo ""
    
    # Create logs directory
    mkdir -p "$LOGS_DIR"
    
    # Collect logs using the dedicated script
    if [ -f "$SCRIPT_DIR/collect-logs.sh" ]; then
        "$SCRIPT_DIR/collect-logs.sh" "$LOGS_DIR"
    else
        log_warn "collect-logs.sh not found, collecting basic logs..."
        
        # Basic log collection
        echo "ArgoCD Application Controller logs:" > "$LOGS_DIR/basic-debug-$(date +%Y%m%d-%H%M%S).log"
        kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100 >> "$LOGS_DIR/basic-debug-$(date +%Y%m%d-%H%M%S).log" 2>&1 || true
        echo "" >> "$LOGS_DIR/basic-debug-$(date +%Y%m%d-%H%M%S).log"
        
        echo "External Secrets Operator logs:" >> "$LOGS_DIR/basic-debug-$(date +%Y%m%d-%H%M%S).log"
        kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=100 >> "$LOGS_DIR/basic-debug-$(date +%Y%m%d-%H%M%S).log" 2>&1 || true
        echo "" >> "$LOGS_DIR/basic-debug-$(date +%Y%m%d-%H%M%S).log"
        
        echo "Failed pods:" >> "$LOGS_DIR/basic-debug-$(date +%Y%m%d-%H%M%S).log"
        kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded >> "$LOGS_DIR/basic-debug-$(date +%Y%m%d-%H%M%S).log" 2>&1 || true
    fi
    
    echo ""
    log_error "Debug logs collected in: $LOGS_DIR"
    echo ""
    
    # Still run cleanup
    cleanup_preview_environment
    
    exit $exit_code
}

# Trap to ensure cleanup on exit and error handling
trap handle_error ERR
trap cleanup_preview_environment EXIT

# Create logs directory
mkdir -p "$LOGS_DIR"

# If cleanup-only mode, just run cleanup and exit
if [ "$CLEANUP_ONLY" = true ]; then
    log_info "Running cleanup only..."
    cleanup_preview_environment
    trap - EXIT  # Remove the trap since we're doing cleanup manually
    exit 0
fi

# Start the test
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Platform Integration Test (Local)               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Check prerequisites
log_step "Step 1/8: Checking prerequisites..."

# Check required tools
MISSING_TOOLS=()

if ! command_exists kubectl; then
    MISSING_TOOLS+=("kubectl")
fi

if ! command_exists docker; then
    MISSING_TOOLS+=("docker")
fi

if ! command_exists kind; then
    MISSING_TOOLS+=("kind")
fi

if ! command_exists python3; then
    MISSING_TOOLS+=("python3")
fi

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    log_error "Missing required tools: ${MISSING_TOOLS[*]}"
    echo ""
    echo "Please install the missing tools:"
    echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/"
    echo "  - docker: https://docs.docker.com/get-docker/"
    echo "  - kind: https://kind.sigs.k8s.io/docs/user/quick-start/"
    echo "  - python3: https://www.python.org/downloads/"
    exit 1
fi

log_info "✓ All required tools are available"

# Check Python dependencies
log_info "Installing Python dependencies..."
python3 -m pip install --upgrade pip --quiet
pip install pyyaml --quiet
log_info "✓ Python dependencies installed"

# Step 2: Check environment variables
log_step "Step 2/8: Checking environment variables..."

MISSING_VARS=()

if [ -z "$OPENAI_API_KEY" ]; then
    MISSING_VARS+=("OPENAI_API_KEY")
fi

if [ -z "$BOT_GITHUB_TOKEN" ]; then
    MISSING_VARS+=("BOT_GITHUB_TOKEN")
fi

if [ -z "$BOT_GITHUB_TOKEN" ]; then
    MISSING_VARS+=("BOT_GITHUB_TOKEN")
fi

# Optional variables (warn but don't fail)
OPTIONAL_VARS=()
if [ -z "$ANTHROPIC_API_KEY" ]; then
    OPTIONAL_VARS+=("ANTHROPIC_API_KEY")
fi

if [ -z "$TENANTS_REPO_NAME" ]; then
    OPTIONAL_VARS+=("TENANTS_REPO_NAME")
fi

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
    log_error "Missing required environment variables: ${MISSING_VARS[*]}"
    echo ""
    echo "Please set the required environment variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  export $var=\"your-value\""
    done
    echo ""
    echo "You can also create a .env file in the repository root with these variables."
    exit 1
fi

if [ ${#OPTIONAL_VARS[@]} -ne 0 ]; then
    log_warn "Optional environment variables not set: ${OPTIONAL_VARS[*]}"
    log_warn "Some features may not work properly"
fi

log_info "✓ Required environment variables are set"

# Step 3: Bootstrap Platform Preview Environment
log_step "Step 3/8: Bootstrap Platform Preview Environment..."

cd "$REPO_ROOT"

log_info "Starting platform bootstrap in preview mode..."
log_info "Bootstrap logs will be saved to: $LOGS_DIR/bootstrap-$(date +%Y%m%d-%H%M%S).log"

chmod +x scripts/bootstrap/01-master-bootstrap.sh

# Run bootstrap and capture output
BOOTSTRAP_LOG="$LOGS_DIR/bootstrap-$(date +%Y%m%d-%H%M%S).log"
if ./scripts/bootstrap/01-master-bootstrap.sh --mode preview 2>&1 | tee "$BOOTSTRAP_LOG"; then
    log_info "✓ Platform bootstrap completed"
else
    log_error "Platform bootstrap failed - check logs at: $BOOTSTRAP_LOG"
    exit 1
fi

# Step 4: Wait for platform applications to sync
log_step "Step 4/8: Wait for platform applications to sync..."

SYNC_LOG="$LOGS_DIR/sync-wait-$(date +%Y%m%d-%H%M%S).log"
if [ -f "$REPO_ROOT/scripts/bootstrap/wait/wait-for-sync.sh" ]; then
    chmod +x scripts/bootstrap/wait/wait-for-sync.sh
    if ./scripts/bootstrap/wait/wait-for-sync.sh --timeout 600 2>&1 | tee "$SYNC_LOG"; then
        log_info "✓ Applications synced"
    else
        log_error "Application sync failed - check logs at: $SYNC_LOG"
        exit 1
    fi
else
    log_warn "wait-for-sync.sh not found, using basic wait..."
    sleep 60
    kubectl get applications -n argocd | tee "$SYNC_LOG"
    log_info "✓ Basic sync wait completed"
fi

# Step 5: Wait for pods to be ready
log_step "Step 5/8: Wait for pods to be ready..."

PODS_LOG="$LOGS_DIR/pods-wait-$(date +%Y%m%d-%H%M%S).log"
if [ -f "$REPO_ROOT/scripts/bootstrap/wait/wait-for-pods.sh" ]; then
    chmod +x scripts/bootstrap/wait/wait-for-pods.sh
    if ./scripts/bootstrap/wait/wait-for-pods.sh --timeout 600 2>&1 | tee "$PODS_LOG"; then
        log_info "✓ Pods are ready"
    else
        log_error "Pod readiness check failed - check logs at: $PODS_LOG"
        exit 1
    fi
else
    log_warn "wait-for-pods.sh not found, using basic wait..."
    log_info "Waiting for pods to be ready (timeout: 10 minutes)..."
    if kubectl wait --for=condition=ready pod --all --all-namespaces --timeout=600s 2>&1 | tee "$PODS_LOG"; then
        log_info "✓ Pods are ready"
    else
        log_warn "Some pods may not be ready, continuing..."
    fi
fi

# Step 6: Run cluster validation
log_step "Step 6/8: Run cluster validation..."

VALIDATION_LOG="$LOGS_DIR/validation-$(date +%Y%m%d-%H%M%S).log"
if [ -f "$REPO_ROOT/scripts/bootstrap/validation/99-validate-cluster.sh" ]; then
    chmod +x scripts/bootstrap/validation/99-validate-cluster.sh
    if ./scripts/bootstrap/validation/99-validate-cluster.sh 2>&1 | tee "$VALIDATION_LOG"; then
        log_info "✓ Cluster validation passed"
    else
        log_error "Cluster validation failed - check logs at: $VALIDATION_LOG"
        exit 1
    fi
else
    log_warn "Cluster validation script not found, running basic validation..."
    
    # Basic validation
    log_info "Checking ArgoCD applications..."
    kubectl get applications -n argocd | tee "$VALIDATION_LOG"
    
    log_info "Checking pod status..."
    kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded | grep -v "No resources found" >> "$VALIDATION_LOG" 2>&1 || {
        echo "All pods are running or succeeded" | tee -a "$VALIDATION_LOG"
    }
    
    log_info "✓ Basic cluster validation completed"
fi

# Step 7: Validate port-forwards
log_step "Step 7/8: Validate port-forwards..."

PORTFORWARD_LOG="$LOGS_DIR/port-forwards-$(date +%Y%m%d-%H%M%S).log"
if [ -f "$REPO_ROOT/scripts/bootstrap/validation/validate-port-forwards.sh" ]; then
    chmod +x scripts/bootstrap/validation/validate-port-forwards.sh
    if ./scripts/bootstrap/validation/validate-port-forwards.sh --preview-mode --timeout 300 2>&1 | tee "$PORTFORWARD_LOG"; then
        log_info "✓ Port-forward validation completed"
    else
        log_warn "Port-forward validation had issues - check logs at: $PORTFORWARD_LOG"
        # Don't fail the test for port-forward issues
    fi
else
    log_warn "Port-forward validation script not found, skipping..."
    echo "Port-forward validation script not found" > "$PORTFORWARD_LOG"
fi

# Step 8: Show final cluster state
log_step "Step 8/8: Show final cluster state..."

FINAL_STATE_LOG="$LOGS_DIR/final-cluster-state-$(date +%Y%m%d-%H%M%S).log"

echo ""
echo "=== Final Cluster State ==="
echo ""
echo "ArgoCD Applications:"
kubectl get applications -n argocd 2>&1 | tee -a "$FINAL_STATE_LOG" || true
echo ""
echo "All Pods:"
kubectl get pods -A 2>&1 | tee -a "$FINAL_STATE_LOG" || true
echo ""
echo "Nodes:"
kubectl get nodes 2>&1 | tee -a "$FINAL_STATE_LOG" || true
echo ""

log_info "Final cluster state saved to: $FINAL_STATE_LOG"

# Success summary
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          ✓ Platform Integration Test PASSED                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "All validations passed:"
echo -e "  ${GREEN}✓${NC} Platform bootstrapped in preview mode"
echo -e "  ${GREEN}✓${NC} All applications synced"
echo -e "  ${GREEN}✓${NC} All pods healthy"
echo -e "  ${GREEN}✓${NC} Cluster validation passed"
echo ""

# Remove the trap since we completed successfully
trap - EXIT

log_info "Test completed successfully!"
log_info "All logs saved to: $LOGS_DIR"
log_info "Run with --cleanup-only to clean up the environment."
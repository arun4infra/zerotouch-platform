#!/bin/bash
set -euo pipefail

# ==============================================================================
# Patch 01: Disable ArgoCD Auto-Sync
# ==============================================================================
# Purpose: Disable ArgoCD auto-sync to prevent conflicts during patching
# This allows manual control over when applications sync during CI/preview environments
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[PATCH-01]${NC} $*"; }
log_success() { echo -e "${GREEN}[PATCH-01]${NC} $*"; }
log_error() { echo -e "${RED}[PATCH-01]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[PATCH-01]${NC} $*"; }

main() {
    log_info "Disabling ArgoCD auto-sync for stable patching..."
    
    # Check if ArgoCD namespace exists
    if ! kubectl get namespace argocd &>/dev/null; then
        log_warn "ArgoCD namespace not found - skipping auto-sync disable"
        return 0
    fi
    
    # Check if ConfigMap exists
    if ! kubectl get configmap argocd-cm -n argocd &>/dev/null; then
        log_warn "ArgoCD ConfigMap not found - skipping auto-sync disable"
        return 0
    fi
    
    # Check if already patched
    if kubectl get configmap argocd-cm -n argocd -o yaml | grep -q "application.instanceLabelKey" 2>/dev/null; then
        log_warn "ArgoCD auto-sync already disabled, skipping..."
        return 0
    fi
    
    log_info "Applying ArgoCD auto-sync disable configuration..."
    
    # Create the patch using kubectl patch - only add auto-sync disable
    # Resource exclusions are already handled at installation time via kustomization.yaml
    kubectl patch configmap argocd-cm -n argocd --type merge -p '{
        "data": {
            "application.instanceLabelKey": "argocd.argoproj.io/instance"
        }
    }'
    
    # Verify the patch was applied
    if kubectl get configmap argocd-cm -n argocd -o yaml | grep -q "application.instanceLabelKey"; then
        log_success "✓ ArgoCD auto-sync disabled successfully"
        log_info "ArgoCD applications will now require manual sync"
    else
        log_error "✗ ArgoCD auto-sync disable verification failed"
        exit 1
    fi
}

main "$@"
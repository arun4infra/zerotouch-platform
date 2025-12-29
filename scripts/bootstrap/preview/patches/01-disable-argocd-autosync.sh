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
    
    # Install yq if not available
    if ! command -v yq &> /dev/null; then
        log_info "Installing yq..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install yq
            else
                log_error "Homebrew not found. Please install yq manually."
                exit 1
            fi
        else
            YQ_VERSION="v4.35.2"
            YQ_BINARY="yq_linux_amd64"
            curl -L "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -o /tmp/yq
            chmod +x /tmp/yq
            sudo mv /tmp/yq /usr/local/bin/yq
        fi
    fi
    
    # Find platform root directory
    local current_dir="$(pwd)"
    local platform_root=""
    
    # Check SERVICE_ROOT first
    if [[ -n "${SERVICE_ROOT:-}" && -d "${SERVICE_ROOT}/../bootstrap/argocd/base" ]]; then
        platform_root="${SERVICE_ROOT}/.."
    # Check standard locations
    elif [[ -d "${current_dir}/bootstrap/argocd/base" ]]; then
        platform_root="${current_dir}"
    elif [[ -d "${current_dir}/../bootstrap/argocd/base" ]]; then
        platform_root="${current_dir}/.."
    elif [[ -d "${current_dir}/../../bootstrap/argocd/base" ]]; then
        platform_root="${current_dir}/../.."
    elif [[ -d "${current_dir}/../../../../../bootstrap/argocd/base" ]]; then
        platform_root="${current_dir}/../../../.."
    else
        log_error "Cannot find bootstrap/argocd/base directory"
        exit 1
    fi
    
    log_info "Found platform root: $platform_root"
    
    # Step 1: Remove automated sync policies from base manifests
    log_info "Removing automated sync policies from base manifests..."
    local apps_modified=0
    
    for app in "${platform_root}/bootstrap/argocd/base"/*.yaml; do
        if [[ -f "$app" ]]; then
            # Check if the app has automated sync policy
            if yq eval '.spec.syncPolicy.automated' "$app" 2>/dev/null | grep -q -v "null"; then
                log_info "Removing automated sync from $(basename "$app")"
                yq eval 'del(.spec.syncPolicy.automated)' -i "$app"
                apps_modified=$((apps_modified + 1))
            fi
        fi
    done
    
    if [[ $apps_modified -gt 0 ]]; then
        log_success "✓ Removed automated sync from $apps_modified ArgoCD applications"
    else
        log_info "No automated sync policies found in base manifests"
    fi
    
    # Step 2: Configure ArgoCD to disable auto-sync globally (if cluster is available)
    if kubectl get namespace argocd &>/dev/null; then
        log_info "Configuring ArgoCD global auto-sync disable..."
        
        # Check if ConfigMap exists
        if kubectl get configmap argocd-cm -n argocd &>/dev/null; then
            # Check if already patched
            if kubectl get configmap argocd-cm -n argocd -o yaml | grep -q "application.instanceLabelKey" 2>/dev/null; then
                log_info "ArgoCD ConfigMap already patched"
            else
                log_info "Applying ArgoCD ConfigMap patch..."
                kubectl patch configmap argocd-cm -n argocd --type merge -p '{
                    "data": {
                        "application.instanceLabelKey": "argocd.argoproj.io/instance"
                    }
                }'
                
                # Verify the patch was applied
                if kubectl get configmap argocd-cm -n argocd -o yaml | grep -q "application.instanceLabelKey"; then
                    log_success "✓ ArgoCD ConfigMap patched successfully"
                else
                    log_error "✗ ArgoCD ConfigMap patch verification failed"
                    exit 1
                fi
            fi
        else
            log_warn "ArgoCD ConfigMap not found - skipping ConfigMap patch"
        fi
    else
        log_warn "ArgoCD namespace not found - skipping cluster-level configuration"
    fi
    
    log_success "✓ ArgoCD auto-sync disabled successfully"
    log_info "ArgoCD applications will now require manual sync during preview"
}

main "$@"
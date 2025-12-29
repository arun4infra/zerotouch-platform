#!/bin/bash
set -euo pipefail

# ==============================================================================
# Sync Platform Components Script
# ==============================================================================
# Purpose: Synchronize required platform components after patches are applied
# Usage: ./sync-platform-components.sh
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[SYNC-PLATFORM]${NC} $*"; }
log_success() { echo -e "${GREEN}[SYNC-PLATFORM]${NC} $*"; }
log_error() { echo -e "${RED}[SYNC-PLATFORM]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[SYNC-PLATFORM]${NC} $*"; }

# Kubectl retry function
kubectl_retry() {
    local max_attempts=3
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if timeout 10 kubectl "$@" 2>/dev/null; then
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    return 1
}

# Get platform dependencies from service config
get_platform_dependencies() {
    local config_file="${SERVICE_ROOT:-$(pwd)}/ci/config.yaml"
    
    if [[ ! -f "$config_file" ]]; then
        echo ""
        return
    fi
    
    if command -v yq &> /dev/null; then
        yq eval '.dependencies.platform[]' "$config_file" 2>/dev/null | tr '\n' ' ' || echo ""
    else
        log_error "yq is required but not installed"
        exit 1
    fi
}

# Clear corrupted ArgoCD state
clear_argocd_state() {
    log_info "Clearing corrupted ArgoCD state..."
    
    # Get all applications and clear their operation state
    local apps=$(kubectl_retry get applications -n argocd -o name 2>/dev/null || echo "")
    local cleared_count=0
    
    if [[ -n "$apps" ]]; then
        while IFS= read -r app; do
            if [[ -n "$app" ]]; then
                if kubectl patch "$app" -n argocd --type merge -p '{"status":{"operationState":null}}' 2>/dev/null; then
                    cleared_count=$((cleared_count + 1))
                fi
            fi
        done <<< "$apps"
        
        log_success "Cleared operation state for $cleared_count applications"
    else
        log_warn "No ArgoCD applications found to clear"
    fi
}

# Trigger root sync with pruning
trigger_root_sync() {
    log_info "Triggering root sync to prune undeclared services..."
    
    if kubectl_retry get application platform-bootstrap -n argocd >/dev/null 2>&1; then
        if kubectl patch application platform-bootstrap -n argocd --type merge \
            -p '{"operation":{"sync":{"prune":true}}}' 2>/dev/null; then
            log_success "Root sync triggered successfully"
        else
            log_warn "Failed to trigger root sync - ArgoCD may not be ready yet"
        fi
    else
        log_warn "platform-bootstrap application not found - skipping root sync"
    fi
}

# Sync required platform dependencies
sync_platform_dependencies() {
    local platform_deps=$(get_platform_dependencies)
    
    if [[ -z "$platform_deps" ]]; then
        log_info "No platform dependencies declared - skipping dependency sync"
        return 0
    fi
    
    log_info "Service dependencies: $platform_deps"
    
    local sync_count=0
    local failed_syncs=()
    
    for dep in $platform_deps; do
        if [[ -n "$dep" ]]; then
            log_info "Manual sync trigger for required dependency: $dep"
            
            if kubectl_retry get application "$dep" -n argocd >/dev/null 2>&1; then
                if kubectl patch application "$dep" -n argocd --type merge \
                    -p '{"operation":{"sync":{"prune":true, "syncOptions":["ServerSideApply=true"]}}}' 2>/dev/null; then
                    sync_count=$((sync_count + 1))
                    log_success "Sync triggered for $dep"
                else
                    failed_syncs+=("$dep")
                    log_warn "Failed to trigger sync for $dep"
                fi
            else
                failed_syncs+=("$dep")
                log_warn "Application $dep not found - may not be deployed yet"
            fi
        fi
    done
    
    # Summary
    if [[ ${#failed_syncs[@]} -eq 0 ]]; then
        log_success "Successfully triggered sync for all $sync_count dependencies"
    else
        log_warn "Triggered sync for $sync_count dependencies, ${#failed_syncs[@]} failed:"
        for failed_dep in "${failed_syncs[@]}"; do
            log_warn "  - $failed_dep"
        done
    fi
}

# Main execution
main() {
    log_info "Synchronizing required platform components..."
    
    # Validate environment
    if [[ -z "${SERVICE_ROOT:-}" ]]; then
        log_error "SERVICE_ROOT environment variable not set"
        exit 1
    fi
    
    if [[ ! -f "${SERVICE_ROOT}/ci/config.yaml" ]]; then
        log_error "ci/config.yaml not found at: ${SERVICE_ROOT}/ci/config.yaml"
        exit 1
    fi
    
    # Step 1: Clear corrupted ArgoCD state
    clear_argocd_state
    
    # Step 2: Trigger root sync with pruning
    trigger_root_sync
    
    # Step 3: Sync required platform dependencies
    sync_platform_dependencies
    
    log_success "Platform component synchronization completed"
}

main "$@"
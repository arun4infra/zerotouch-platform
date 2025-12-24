#!/bin/bash
set -euo pipefail

# ==============================================================================
# Platform Readiness Check Script
# ==============================================================================
# Purpose: Check if declared platform dependencies are ready
# Usage: ./check-platform-readiness.sh
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[PLATFORM-READINESS]${NC} $*"; }
log_success() { echo -e "${GREEN}[PLATFORM-READINESS]${NC} $*"; }
log_error() { echo -e "${RED}[PLATFORM-READINESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[PLATFORM-READINESS]${NC} $*"; }

# Get platform dependencies from service config
get_platform_dependencies() {
    # Look for ci/config.yaml in service directory (one level up from platform)
    local config_file="../ci/config.yaml"
    
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

# Generic platform dependency validation
check_platform_dependency() {
    local dep="$1"
    
    # Generic validation: check if the ArgoCD application exists and is healthy
    log_info "Validating platform service: $dep"
    
    # Check if ArgoCD application exists and is synced/healthy
    if kubectl get application "$dep" -n argocd >/dev/null 2>&1; then
        local sync_status=$(kubectl get application "$dep" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        local health_status=$(kubectl get application "$dep" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        
        if [[ "$sync_status" == "Synced" && "$health_status" == "Healthy" ]]; then
            log_success "Platform service $dep is ready (Synced/Healthy)"
        else
            log_error "Platform service $dep is not ready (Sync: $sync_status, Health: $health_status)"
            exit 1
        fi
    else
        log_error "Platform service $dep not found (declare '$dep' in dependencies.platform to enable)"
        log_error "Available optional services are determined by sync-wave 4+ in platform ArgoCD applications"
        exit 1
    fi
}

# Main execution
main() {
    log_info "Checking platform readiness based on service requirements"
    
    local platform_deps=$(get_platform_dependencies)
    
    if [[ -n "$platform_deps" ]]; then
        for dep in $platform_deps; do
            if [[ -n "$dep" ]]; then
                log_info "Checking platform dependency: $dep"
                check_platform_dependency "$dep"
            fi
        done
        log_success "All platform dependencies are ready"
    else
        log_info "No platform dependencies specified"
    fi
}

main "$@"
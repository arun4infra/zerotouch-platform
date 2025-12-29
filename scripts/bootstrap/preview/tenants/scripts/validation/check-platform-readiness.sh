#!/bin/bash
set -euo pipefail

# ==============================================================================
# Platform Readiness Check Script
# ==============================================================================
# Purpose: Check if declared platform dependencies are ready (with optional wait)
# Usage: ./check-platform-readiness.sh [--wait] [--timeout <seconds>]
# ==============================================================================

# Get script directory for sourcing wait script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Configuration
WAIT_MODE=false
TIMEOUT=600  # 10 minutes default

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --wait)
            WAIT_MODE=true
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--wait] [--timeout <seconds>]"
            exit 1
            ;;
    esac
done

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

# Simple platform dependency validation (immediate check only)
check_platform_dependency() {
    local dep="$1"
    
    # Check if ArgoCD application exists and is synced/healthy
    if kubectl_retry get application "$dep" -n argocd >/dev/null 2>&1; then
        local sync_status=$(kubectl_retry get application "$dep" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        local health_status=$(kubectl_retry get application "$dep" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        
        if [[ "$sync_status" == "Synced" && "$health_status" == "Healthy" ]]; then
            log_success "Platform service $dep is ready (Synced/Healthy)"
        else
            log_error "Platform service $dep is not ready (Sync: $sync_status, Health: $health_status)"
            log_error "Use --wait flag for detailed diagnostics and automatic retry"
            exit 1
        fi
    else
        log_error "Platform service $dep not found"
        log_error "Declare '$dep' in dependencies.platform in ci/config.yaml to enable"
        exit 1
    fi
}

# Main execution
main() {
    log_info "Checking platform readiness based on service requirements"
    
    local platform_deps=$(get_platform_dependencies)
    
    if [[ -z "$platform_deps" ]]; then
        log_info "No platform dependencies specified"
        exit 0
    fi
    
    # If wait mode is enabled, use the wait script
    if [[ "$WAIT_MODE" == "true" ]]; then
        log_info "Wait mode enabled - using wait-for-platform-readiness.sh"
        
        local wait_script="$SCRIPT_DIR/wait/wait-for-platform-readiness.sh"
        if [[ -f "$wait_script" ]]; then
            log_info "Delegating to wait script with timeout: ${TIMEOUT}s"
            exec "$wait_script" --timeout "$TIMEOUT"
        else
            log_error "Wait script not found: $wait_script"
            log_error "Falling back to immediate check mode"
        fi
    fi
    
    # Immediate check mode (default behavior)
    log_info "Running immediate platform readiness check"
    
    for dep in $platform_deps; do
        if [[ -n "$dep" ]]; then
            log_info "Checking platform dependency: $dep"
            check_platform_dependency "$dep"
        fi
    done
    
    log_success "All platform dependencies are ready"
}

main "$@"
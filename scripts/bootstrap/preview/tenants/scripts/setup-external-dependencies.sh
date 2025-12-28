#!/bin/bash
set -euo pipefail

# ==============================================================================
# External Dependencies Setup Script
# ==============================================================================
# Purpose: Setup external service dependencies before deploying this service
# Usage: ./setup-external-dependencies.sh
# ==============================================================================

# Get script directory for finding platform root
# Check if PLATFORM_ROOT is already set by parent script
if [[ -n "${PLATFORM_ROOT:-}" ]]; then
    # Use the PLATFORM_ROOT from parent script
    log_info "Using PLATFORM_ROOT from parent: $PLATFORM_ROOT"
else
    # Fallback: calculate from script location
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[EXTERNAL-DEPS]${NC} $*"; }
log_success() { echo -e "${GREEN}[EXTERNAL-DEPS]${NC} $*"; }
log_error() { echo -e "${RED}[EXTERNAL-DEPS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[EXTERNAL-DEPS]${NC} $*"; }

# Get external dependencies from service config
get_external_dependencies() {
    local config_file="${SERVICE_ROOT:-$(pwd)}/ci/config.yaml"
    
    if [[ ! -f "$config_file" ]]; then
        echo ""
        return
    fi
    
    if command -v yq &> /dev/null; then
        yq eval '.dependencies.external[]' "$config_file" 2>/dev/null | tr '\n' ' ' || echo ""
    else
        log_error "yq is required but not installed"
        exit 1
    fi
}

# Setup specific external dependency
setup_external_dependency() {
    local dep="$1"
    case "$dep" in
        "deepagents-runtime")
            log_info "Setting up DeepAgents Runtime service"
            setup_deepagents_runtime_service
            ;;
        *)
            log_error "Unknown external dependency: $dep"
            log_error "Supported external dependencies: deepagents-runtime"
            exit 1
            ;;
    esac
}

setup_deepagents_runtime_service() {
    # Use the existing platform setup-dependencies.sh for deepagents-runtime
    local setup_deps_script="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/setup-dependencies.sh"
    if [[ -f "$setup_deps_script" ]]; then
        chmod +x "$setup_deps_script"
        "$setup_deps_script"
    else
        log_error "DeepAgents Runtime setup script not found: $setup_deps_script"
        exit 1
    fi
}

# Main execution
main() {
    log_info "Setting up external dependencies based on service requirements"
    
    local external_deps=$(get_external_dependencies)
    
    if [[ -n "$external_deps" ]]; then
        for dep in $external_deps; do
            if [[ -n "$dep" ]]; then
                log_info "Setting up external dependency: $dep"
                setup_external_dependency "$dep"
            fi
        done
        log_success "All external dependencies are set up"
    else
        log_info "No external dependencies specified"
    fi
}

main "$@"
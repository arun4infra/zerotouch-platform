#!/bin/bash
set -euo pipefail

# ==============================================================================
# PR Claims Checkout Script
# ==============================================================================
# Purpose: Checkout PR claims from tenants repository
# Usage: ./checkout-pr-claims.sh <environment> <namespace> <service_root>
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[PR-CLAIMS]${NC} $*"; }
log_success() { echo -e "${GREEN}[PR-CLAIMS]${NC} $*"; }
log_error() { echo -e "${RED}[PR-CLAIMS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[PR-CLAIMS]${NC} $*"; }

checkout_pr_claims() {
    local environment="$1"
    local namespace="$2"
    local service_root="$3"
    
    log_info "=== PR CLAIMS CHECKOUT DEBUG ==="
    log_info "Environment parameter: '$environment'"
    log_info "Namespace: '$namespace'"
    log_info "Service root: '$service_root'"
    log_info "Current working directory: $(pwd)"
    
    # Extract service name from config first, fallback to basename for compatibility
    local service_name
    if [[ -f "${service_root}/ci/config.yaml" ]]; then
        if command -v yq &> /dev/null; then
            service_name=$(yq eval '.service.name' "${service_root}/ci/config.yaml" 2>/dev/null || echo "")
            log_info "Service name from config: '$service_name'"
        else
            log_warn "yq not available, using basename fallback"
            service_name=""
        fi
    else
        log_warn "Config file not found: ${service_root}/ci/config.yaml"
    fi
    
    # Fallback to basename if config fails (preserves local behavior)
    if [[ -z "$service_name" ]]; then
        service_name=$(basename "$service_root")
        log_info "Service name from basename fallback: '$service_name'"
    fi
    
    log_info "Final service name: '$service_name'"
    
    if [[ "$environment" == "pr" || "$environment" == "preview" ]]; then
        log_info "Checking out PR claims for service: $service_name, namespace: $namespace"
        
        # Checkout zerotouch-tenants repository
        local tenants_repo="git@github.com:arun4infra/zerotouch-tenants.git"
        local tenants_dir="platform/tenants-temp"
        
        # Detect current branch for checkout
        local current_branch=$(git branch --show-current 2>/dev/null || echo "main")
        log_info "Current branch detected: $current_branch"
        
        log_info "Cloning tenants repository: $tenants_repo"
        log_info "Target directory: $tenants_dir"
        
        # Remove existing temp directory if it exists
        if [[ -d "$tenants_dir" ]]; then
            log_info "Removing existing temp directory: $tenants_dir"
            rm -rf "$tenants_dir"
        fi
        
        # Create platform directory if it doesn't exist
        mkdir -p platform
        log_info "Created platform directory"
        
        # Clone the repository and checkout the same branch
        # Try SSH first (works locally), fallback to HTTPS (works in CI)
        local clone_success=false
        
        log_info "Attempting SSH clone with branch: $current_branch"
        if git clone -b "$current_branch" "$tenants_repo" "$tenants_dir" 2>/dev/null; then
            log_success "SSH clone successful, checked out branch: $current_branch"
            clone_success=true
        elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
            log_info "SSH failed, trying HTTPS with GitHub token..."
            local https_repo="https://${GITHUB_TOKEN}@github.com/arun4infra/zerotouch-tenants.git"
            if git clone -b "$current_branch" "$https_repo" "$tenants_dir" 2>/dev/null; then
                log_success "HTTPS clone successful, checked out branch: $current_branch"
                clone_success=true
            else
                log_warn "Branch $current_branch not found in tenants repo, falling back to main"
                if git clone -b main "$https_repo" "$tenants_dir" 2>/dev/null; then
                    log_success "HTTPS clone successful, checked out main branch"
                    clone_success=true
                fi
            fi
        else
            log_info "SSH failed and no GITHUB_TOKEN available, trying branch fallback with SSH..."
            if git clone -b main "$tenants_repo" "$tenants_dir" 2>/dev/null; then
                log_success "SSH clone successful with main branch"
                clone_success=true
            fi
        fi
        
        if [[ "$clone_success" != "true" ]]; then
            log_error "All clone attempts failed. Check repository access and authentication."
            log_error "Attempted methods:"
            log_error "  1. SSH with branch: $current_branch"
            if [[ -n "${GITHUB_TOKEN:-}" ]]; then
                log_error "  2. HTTPS with GitHub token and branch: $current_branch"
                log_error "  3. HTTPS with GitHub token and main branch"
            else
                log_error "  2. SSH with main branch (no GITHUB_TOKEN available)"
            fi
            exit 1
        fi
        
        # Path to service directory
        local service_path="$tenants_dir/tenants/$service_name"
        local target_path="${service_root}/platform/${service_name}"
        
        log_info "Looking for service directory at: $service_path"
        
        if [[ -d "$service_path" ]]; then
            log_success "Found service directory at: $service_path"
            
            # Create platform directory if it doesn't exist
            mkdir -p "${service_root}/platform"
            log_info "Created service platform directory: ${service_root}/platform"
            
            # Copy only the service directory to platform/
            if [[ -d "$target_path" ]]; then
                log_info "Removing existing target directory: $target_path"
                rm -rf "$target_path"
            fi
            
            cp -r "$service_path" "$target_path"
            log_success "Service directory copied to: $target_path"
            
            # Remove the temp directory
            rm -rf "$tenants_dir"
            log_info "Cleaned up temp directory: $tenants_dir"
            
            # Path to PR claims
            local claims_path="$target_path/overlays/pr"
            
            log_info "Looking for PR claims at: $claims_path"
            
            if [[ -d "$claims_path" ]]; then
                log_success "Found PR claims at: $claims_path"
                
                # Post-checkout verification
                log_info "=== POST-CHECKOUT VERIFICATION ==="
                log_info "Service platform directory exists: $target_path"
                
                local manifest_count=0
                while IFS= read -r -d '' file; do
                    log_info "Found manifest: $(basename "$file")"
                    ((manifest_count++))
                done < <(find "$target_path" -name "*.yaml" -o -name "*.yml" -print0 2>/dev/null | head -z -10)
                
                log_info "Total manifests found: $manifest_count"
                log_success "PR claims checked out successfully"
            else
                log_error "PR claims directory not found: $claims_path"
                log_error "Available directories in $target_path:"
                if [[ -d "$target_path" ]]; then
                    find "$target_path" -type d | head -10 | while read -r dir; do
                        log_error "  - $dir"
                    done
                fi
                exit 1
            fi
        else
            log_error "Service directory not found: $service_path"
            log_error "Available services in tenants directory:"
            if [[ -d "$tenants_dir/tenants" ]]; then
                find "$tenants_dir/tenants" -maxdepth 1 -type d | head -10 | while read -r dir; do
                    log_error "  - $(basename "$dir")"
                done
            fi
            rm -rf "$tenants_dir"
            exit 1
        fi
    else
        log_info "Environment is '$environment' - skipping PR claims checkout"
    fi
    
    log_info "=== PR CLAIMS CHECKOUT DEBUG END ==="
}

# Main execution
if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <environment> <namespace> <service_root>"
    echo "Example: $0 pr intelligence-orchestrator /path/to/service"
    exit 1
fi

ENVIRONMENT="$1"
NAMESPACE="$2"
SERVICE_ROOT="$3"

checkout_pr_claims "$ENVIRONMENT" "$NAMESPACE" "$SERVICE_ROOT"

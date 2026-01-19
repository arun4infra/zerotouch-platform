#!/bin/bash
set -euo pipefail

# ==============================================================================
# PR Claims Checkout Script
# ==============================================================================
# Purpose: Checkout PR claims from tenants repository
# Usage: ./checkout-pr-claims.sh <environment> <namespace> <service_name>
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[PR-CLAIMS]${NC} $*"; }
log_success() { echo -e "${GREEN}[PR-CLAIMS]${NC} $*"; }
log_error() { echo -e "${RED}[PR-CLAIMS]${NC} $*"; }

checkout_pr_claims() {
    local environment="$1"
    local namespace="$2"
    local service_name="$3"
    
    if [[ "$environment" == "pr" || "$environment" == "preview" ]]; then
        log_info "Checking out PR claims for service: $service_name, namespace: $namespace"
        
        # Checkout zerotouch-tenants repository
        local tenants_repo="git@github.com:arun4infra/zerotouch-tenants.git"
        local tenants_dir="platform/tenants-temp"
        
        # Detect current branch for checkout
        local current_branch=$(git branch --show-current 2>/dev/null || echo "main")
        
        log_info "Cloning tenants repository: $tenants_repo"
        log_info "Checking out branch: $current_branch"
        
        # Remove existing temp directory if it exists
        if [[ -d "$tenants_dir" ]]; then
            rm -rf "$tenants_dir"
        fi
        
        # Create platform directory if it doesn't exist
        mkdir -p platform
        
        # Clone the repository and checkout the same branch
        if git clone -b "$current_branch" "$tenants_repo" "$tenants_dir" 2>/dev/null; then
            log_success "Checked out branch: $current_branch"
        else
            log_info "Branch $current_branch not found in tenants repo, falling back to main"
            git clone -b main "$tenants_repo" "$tenants_dir"
        fi
        
        # Path to service directory
        local service_path="$tenants_dir/tenants/$service_name"
        local target_path="platform/$service_name"
        
        if [[ -d "$service_path" ]]; then
            log_info "Found service directory at: $service_path"
            
            # Copy only the service directory to platform/
            rm -rf "$target_path"
            cp -r "$service_path" "$target_path"
            log_success "Service directory copied to: $target_path"
            
            # Remove the temp directory
            rm -rf "$tenants_dir"
            
            # Path to PR claims
            local claims_path="$target_path/overlays/pr"
            
            if [[ -d "$claims_path" ]]; then
                log_info "Found PR claims at: $claims_path"
                log_success "PR claims checked out successfully"
            else
                log_error "PR claims directory not found: $claims_path"
                exit 1
            fi
        else
            log_error "Service directory not found: $service_path"
            rm -rf "$tenants_dir"
            exit 1
        fi
    else
        log_info "Environment is '$environment' - skipping PR claims checkout"
    fi
}

# Main execution
if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <environment> <namespace> <service_name>"
    echo "Example: $0 pr platform-identity identity-service"
    exit 1
fi

ENVIRONMENT="$1"
NAMESPACE="$2"
SERVICE_NAME="$3"

checkout_pr_claims "$ENVIRONMENT" "$NAMESPACE" "$SERVICE_NAME"

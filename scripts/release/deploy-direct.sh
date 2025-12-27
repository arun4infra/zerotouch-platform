#!/bin/bash
set -euo pipefail

# deploy-direct.sh - Direct GitOps deployment script
# Directly commits image tag updates to tenant repository (no PRs)
# Used for dev/staging/production deployments via GitHub Actions Environments

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Inline logging functions (lib directory removed)
log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*"; }
log_phase() { echo -e "\033[1;35m=== $* ===\033[0m"; }
init_logging() { :; }  # No-op for compatibility
log_environment() { :; }  # No-op for compatibility

# Default values
ENVIRONMENT=""
SERVICE_NAME="${SERVICE_NAME:-}"
IMAGE_TAG="${IMAGE_TAG:-}"
TENANT_REPO_TOKEN="${TENANT_REPO_TOKEN:-}"
TENANT_REPO_URL="${TENANT_REPO_URL:-https://github.com/arun4infra/zerotouch-tenants.git}"

# Usage information
usage() {
    cat << EOF
Usage: $0 <environment>

Direct GitOps deployment script that commits image tag updates to tenant repository.
No PR creation - direct commits for automatic deployment via ArgoCD.

Arguments:
  environment           Target environment (dev|staging|production)

Environment Variables:
  SERVICE_NAME          Service name (required, from GitHub repo name)
  IMAGE_TAG            Container image tag to deploy (required)
  TENANT_REPO_TOKEN    GitHub token for tenant repo access (required)
  TENANT_REPO_URL      Tenant repository URL (default: zerotouch-tenants)

Examples:
  SERVICE_NAME=deepagents-runtime IMAGE_TAG=ghcr.io/org/service:main-abc123 ./deploy-direct.sh dev
  SERVICE_NAME=deepagents-runtime IMAGE_TAG=ghcr.io/org/service:main-abc123 ./deploy-direct.sh staging

EOF
}

# Parse arguments
parse_args() {
    if [[ $# -ne 1 ]]; then
        log_error "Environment argument is required"
        usage
        exit 1
    fi
    
    ENVIRONMENT="$1"
    
    # Validate environment
    case "$ENVIRONMENT" in
        "dev"|"staging"|"production")
            log_info "Target environment: $ENVIRONMENT"
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT (must be dev, staging, or production)"
            usage
            exit 1
            ;;
    esac
}

# Validate environment variables
validate_environment() {
    log_info "Validating deployment environment"
    
    # Check required environment variables
    local required_vars=("SERVICE_NAME" "IMAGE_TAG" "TENANT_REPO_TOKEN")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable not set: $var"
            exit 1
        fi
    done
    
    # Check Git availability
    if ! command -v git &> /dev/null; then
        log_error "Git is required but not installed"
        exit 1
    fi
    
    log_info "Environment validation completed successfully"
}

# Clone tenant repository
clone_tenant_repo() {
    log_info "Cloning tenant repository"
    
    local temp_dir
    temp_dir=$(mktemp -d)
    export TENANT_REPO_DIR="$temp_dir/zerotouch-tenants"
    
    # Clone with authentication
    local auth_url="${TENANT_REPO_URL/https:\/\//https:\/\/${TENANT_REPO_TOKEN}@}"
    
    if git clone "$auth_url" "$TENANT_REPO_DIR"; then
        log_success "Tenant repository cloned to: $TENANT_REPO_DIR"
    else
        log_error "Failed to clone tenant repository"
        exit 1
    fi
    
    cd "$TENANT_REPO_DIR"
}

# Update kustomization file with new image tag
update_kustomization() {
    log_info "Updating kustomization file for $SERVICE_NAME in $ENVIRONMENT"
    
    local kustomization_file="tenants/${SERVICE_NAME}/overlays/${ENVIRONMENT}/kustomization.yaml"
    
    if [[ ! -f "$kustomization_file" ]]; then
        log_error "Kustomization file not found: $kustomization_file"
        exit 1
    fi
    
    log_info "Current kustomization file:"
    cat "$kustomization_file"
    
    # Update image tag using yq (if available) or sed fallback
    if command -v yq &> /dev/null; then
        log_info "Updating image tag using yq"
        yq eval ".images[0].newTag = \"${IMAGE_TAG##*:}\"" -i "$kustomization_file"
    else
        log_info "Updating image tag using sed (yq not available)"
        sed -i.bak "s/newTag: .*/newTag: ${IMAGE_TAG##*:}/" "$kustomization_file"
        rm -f "${kustomization_file}.bak"
    fi
    
    log_info "Updated kustomization file:"
    cat "$kustomization_file"
    
    log_success "Kustomization file updated successfully"
}

# Commit and push changes
commit_and_push() {
    log_info "Committing and pushing changes"
    
    # Configure Git user
    git config user.name "Release Pipeline Bot"
    git config user.email "release-pipeline@zerotouch.dev"
    
    # Check for changes
    if git diff --quiet; then
        log_info "No changes detected, skipping commit"
        return 0
    fi
    
    # Add changes
    git add .
    
    # Create commit message
    local commit_message="Deploy ${SERVICE_NAME} to ${ENVIRONMENT}

Image: ${IMAGE_TAG}
Environment: ${ENVIRONMENT}
Deployed by: GitHub Actions Release Pipeline
Timestamp: $(date -Iseconds)
"
    
    # Commit changes
    if git commit -m "$commit_message"; then
        log_success "Changes committed successfully"
    else
        log_error "Failed to commit changes"
        exit 1
    fi
    
    # Push to remote
    if git push origin main; then
        log_success "Changes pushed to tenant repository"
        log_info "ArgoCD will automatically sync the deployment"
    else
        log_error "Failed to push changes to tenant repository"
        exit 1
    fi
    
    # Get commit SHA for reference
    local commit_sha
    commit_sha=$(git rev-parse HEAD)
    log_info "Deployment commit SHA: $commit_sha"
    
    export DEPLOYMENT_COMMIT_SHA="$commit_sha"
}

# Cleanup temporary directory
cleanup() {
    if [[ -n "${TENANT_REPO_DIR:-}" && -d "$TENANT_REPO_DIR" ]]; then
        log_info "Cleaning up temporary directory: $TENANT_REPO_DIR"
        rm -rf "$(dirname "$TENANT_REPO_DIR")"
    fi
}

# Main deployment execution
main() {
    local start_time
    start_time=$(date +%s)
    
    log_phase "DIRECT DEPLOYMENT PHASE"
    log_info "Starting direct deployment for service: $SERVICE_NAME to $ENVIRONMENT"
    
    # Initialize logging
    init_logging "$SERVICE_NAME" "deploy-direct"
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Log environment information
    log_environment
    
    # Step 1: Validate environment
    validate_environment
    
    # Step 2: Clone tenant repository
    clone_tenant_repo
    
    # Step 3: Update kustomization file
    update_kustomization
    
    # Step 4: Commit and push changes
    commit_and_push
    
    local end_time
    local duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log_success "Direct deployment completed successfully"
    log_info "Service: $SERVICE_NAME"
    log_info "Environment: $ENVIRONMENT"
    log_info "Image: $IMAGE_TAG"
    log_info "Duration: ${duration}s"
    log_info "Commit: ${DEPLOYMENT_COMMIT_SHA:-unknown}"
}

# Check for help flag
if [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

# Parse arguments and run main function
parse_args "$@"
main
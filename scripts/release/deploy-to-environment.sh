#!/bin/bash
set -euo pipefail

# deploy-to-environment.sh - GitOps deployment orchestrator
# Handles GitOps-based deployments by updating tenant repository manifests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config-discovery.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

# Source helper modules
source "${SCRIPT_DIR}/helpers/deployment-validator.sh"
source "${SCRIPT_DIR}/helpers/repository-manager.sh"
source "${SCRIPT_DIR}/helpers/kustomize-updater.sh"
source "${SCRIPT_DIR}/helpers/pr-manager.sh"

# Default values
TENANT=""
ENVIRONMENT=""
ARTIFACT=""
DRY_RUN="false"

# Usage information
usage() {
    cat << EOF
Usage: $0 --tenant=<name> --environment=<env> --artifact=<id> [--dry-run]

GitOps deployment orchestrator that updates tenant repository manifests.
Never touches clusters directly - ArgoCD handles all cluster operations.

Arguments:
  --tenant=<name>        Tenant service name (required)
  --environment=<env>    Target environment (dev|staging|production) (required)
  --artifact=<id>        Artifact ID to deploy (required)
  --dry-run              Show what would be done without making changes

Examples:
  $0 --tenant=deepagents-runtime --environment=dev --artifact=ghcr.io/org/deepagents-runtime:main-abc123
  $0 --tenant=deepagents-runtime --environment=staging --artifact=ghcr.io/org/deepagents-runtime:main-abc123 --dry-run

Environment Variables:
  BOT_GITHUB_TOKEN       GitHub token for tenant repository access (if using remote repo)

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --tenant=*)
                TENANT="${1#*=}"
                shift
                ;;
            --environment=*)
                ENVIRONMENT="${1#*=}"
                shift
                ;;
            --artifact=*)
                ARTIFACT="${1#*=}"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$TENANT" ]]; then
        log_error "Tenant name is required (--tenant=<name>)"
        usage
        exit 1
    fi

    if [[ -z "$ENVIRONMENT" ]]; then
        log_error "Environment is required (--environment=<env>)"
        usage
        exit 1
    fi

    if [[ -z "$ARTIFACT" ]]; then
        log_error "Artifact ID is required (--artifact=<id>)"
        usage
        exit 1
    fi
}

# Main deployment orchestration
main() {
    local start_time
    start_time=$(date +%s)
    
    log_phase "GITOPS DEPLOYMENT PHASE"
    log_info "Starting GitOps deployment for tenant: $TENANT, environment: $ENVIRONMENT"
    
    # Initialize logging
    init_logging "$TENANT" "deploy-to-environment"
    
    # Log environment information
    log_environment
    
    # Discover tenant configuration
    if ! discover_tenant_config "$TENANT"; then
        log_error "Failed to discover tenant configuration"
        exit 1
    fi
    
    # Step 1: Validate deployment request
    if ! validate_deployment; then
        log_error "Deployment validation failed"
        exit 1
    fi
    
    # Step 2: Clone/prepare tenant repository
    if ! clone_tenants_repository; then
        log_error "Failed to clone zerotouch-tenants repository"
        exit 1
    fi
    
    # Step 3: Update deployment manifests
    if ! update_tenant_overlay; then
        log_error "Failed to update tenant overlay"
        exit 1
    fi
    
    # Step 4: Create deployment PR
    if ! create_deployment_pr; then
        log_error "Failed to create deployment PR"
        exit 1
    fi
    
    # Step 5: Verify deployment readiness
    if ! verify_deployment_readiness; then
        log_error "Deployment readiness verification failed"
        exit 1
    fi
    
    local end_time
    local duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log_success "GitOps deployment completed successfully"
    log_info "Tenant: $TENANT"
    log_info "Environment: $ENVIRONMENT"
    log_info "Artifact: $ARTIFACT"
    log_info "Duration: ${duration}s"
    
    # Export results for use by calling script
    export DEPLOYMENT_STATUS="SUCCESS"
    export DEPLOYMENT_DURATION="$duration"
}

# Parse arguments and run main function
parse_args "$@"
main
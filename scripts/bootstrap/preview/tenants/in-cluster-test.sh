#!/bin/bash
set -euo pipefail

# ==============================================================================
# Centralized In-Cluster Test Script (Filesystem Contract)
# ==============================================================================
# Purpose: Platform-owned CI execution using filesystem contract
# Usage: ./in-cluster-test.sh (no arguments - discovers from filesystem)
# 
# Services publish data in standard locations:
# - ci/config.yaml (required)
# - migrations/ (optional)
# - tests/integration/ (optional)
# - env/ci.env (optional)
# - platform/claims/<namespace>/ (required)
# ==============================================================================

# Configuration
CLEANUP_CLUSTER=${CLEANUP_CLUSTER:-true}   # Default: always cleanup cluster
SKIP_CACHE=${SKIP_CACHE:-false}            # Set to true to ignore cache and run full workflow

# Stage cache file location (at service root)
STAGE_CACHE_FILE=".ci-stage-cache"

# Default values - preserve environment variables if already set
SERVICE_NAME="${SERVICE_NAME:-}"
TEST_PATH="${TEST_PATH:-}"
TEST_NAME="${TEST_NAME:-}"
TIMEOUT="${TIMEOUT:-600}"
IMAGE_TAG="${IMAGE_TAG:-ci-test}"
NAMESPACE="${NAMESPACE:-}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[IN-CLUSTER-TEST]${NC} $*"; }
log_success() { echo -e "${GREEN}[IN-CLUSTER-TEST]${NC} $*"; }
log_error() { echo -e "${RED}[IN-CLUSTER-TEST]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[IN-CLUSTER-TEST]${NC} $*"; }

# Stage cache management functions
init_stage_cache() {
    if [[ "$SKIP_CACHE" == "true" ]]; then
        log_info "Cache disabled, removing existing cache file"
        rm -f "$STAGE_CACHE_FILE"
    fi
    
    if [[ ! -f "$STAGE_CACHE_FILE" ]]; then
        log_info "Initializing stage cache: $STAGE_CACHE_FILE"
        echo '{"stages":{},"cluster":"","image":""}' > "$STAGE_CACHE_FILE"
    fi
}

mark_stage_complete() {
    local stage_name="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq --arg stage "$stage_name" --arg ts "$timestamp" \
           '.stages[$stage] = $ts' "$STAGE_CACHE_FILE" > "$temp_file"
        mv "$temp_file" "$STAGE_CACHE_FILE"
        log_success "Stage '$stage_name' marked complete"
    else
        log_warn "jq not available, skipping cache update"
    fi
}

is_stage_complete() {
    local stage_name="$1"
    
    if [[ ! -f "$STAGE_CACHE_FILE" ]] || [[ "$SKIP_CACHE" == "true" ]]; then
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        local completed=$(jq -r --arg stage "$stage_name" '.stages[$stage] // empty' "$STAGE_CACHE_FILE")
        if [[ -n "$completed" ]]; then
            log_info "Stage '$stage_name' already complete (cached: $completed)"
            return 0
        fi
    fi
    
    return 1
}

save_cluster_info() {
    local cluster_name="$1"
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq --arg cluster "$cluster_name" '.cluster = $cluster' "$STAGE_CACHE_FILE" > "$temp_file"
        mv "$temp_file" "$STAGE_CACHE_FILE"
    fi
}

save_image_info() {
    local image_tag="$1"
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq --arg image "$image_tag" '.image = $image' "$STAGE_CACHE_FILE" > "$temp_file"
        mv "$temp_file" "$STAGE_CACHE_FILE"
    fi
}

get_cached_cluster() {
    if [[ -f "$STAGE_CACHE_FILE" ]] && command -v jq &> /dev/null; then
        jq -r '.cluster // empty' "$STAGE_CACHE_FILE"
    fi
}

get_cached_image() {
    if [[ -f "$STAGE_CACHE_FILE" ]] && command -v jq &> /dev/null; then
        jq -r '.image // empty' "$STAGE_CACHE_FILE"
    fi
}

clear_stage_cache() {
    if [[ -f "$STAGE_CACHE_FILE" ]]; then
        log_info "Clearing stage cache"
        rm -f "$STAGE_CACHE_FILE"
    fi
}

# Filesystem contract discovery functions
load_service_config() {
    if [[ ! -f "ci/config.yaml" ]]; then
        log_error "Required ci/config.yaml not found"
        log_error "Service must follow filesystem contract. See in-cluster-test.md"
        exit 1
    fi
    
    log_info "Loading service configuration from ci/config.yaml"
    
    # Parse YAML using yq (required)
    if ! command -v yq &> /dev/null; then
        log_error "yq is required but not installed. Please install yq."
        exit 1
    fi
    
    SERVICE_NAME=$(yq eval '.service.name' ci/config.yaml)
    NAMESPACE=$(yq eval '.service.namespace' ci/config.yaml)
    TIMEOUT=$(yq eval '.test.timeout // 600' ci/config.yaml)
    IMAGE_TAG=$(yq eval '.build.tag // "ci-test"' ci/config.yaml)
    PLATFORM_BRANCH=$(yq eval '.platform.branch // "main"' ci/config.yaml)
    
    # Load environment variables from config
    ENV_VARS=$(yq eval '.env // {}' ci/config.yaml -o json 2>/dev/null || echo "{}")
    
    # Validate required fields
    if [[ -z "$SERVICE_NAME" ]]; then
        log_error "service.name is required in ci/config.yaml"
        exit 1
    fi
    
    if [[ -z "$NAMESPACE" ]]; then
        log_error "service.namespace is required in ci/config.yaml"
        exit 1
    fi
    
    # Auto-discover test configuration (only if not already set via environment)
    if [[ -z "$TEST_PATH" && -d "tests/integration" ]]; then
        TEST_PATH="tests/integration"
        TEST_NAME="integration-tests"
        log_info "Auto-discovered tests in: $TEST_PATH"
    elif [[ -n "$TEST_PATH" ]]; then
        log_info "Using test path from environment: $TEST_PATH"
        # Set default test name if not provided
        if [[ -z "$TEST_NAME" ]]; then
            TEST_NAME="integration-tests"
        fi
    fi
    
    log_success "Service config loaded: $SERVICE_NAME -> $NAMESPACE"
}

# Helper function to check if a config flag is enabled
config_enabled() {
    local config_path="$1"
    local value=$(yq eval ".$config_path // false" ci/config.yaml 2>/dev/null)
    [[ "$value" == "true" ]]
}

# Environment detection using separate script
detect_environment() {
    local detect_script="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/detect-environment.sh"
    if [[ -f "$detect_script" ]]; then
        chmod +x "$detect_script"
        "$detect_script" | tail -1  # Get last line which contains the environment
    else
        log_error "Environment detection script not found: $detect_script"
        exit 1
    fi
}



# Helper function to get dependencies by type
get_platform_dependencies() {
    yq eval '.dependencies.platform[]' ci/config.yaml 2>/dev/null | tr '\n' ' ' || echo ""
}

get_external_dependencies() {
    yq eval '.dependencies.external[]' ci/config.yaml 2>/dev/null | tr '\n' ' ' || echo ""
}

get_internal_dependencies() {
    yq eval '.dependencies.internal[]' ci/config.yaml 2>/dev/null | tr '\n' ' ' || echo ""
}

# Legacy function for backward compatibility
get_dependencies() {
    # Combine all dependency types for legacy support
    local platform_deps=$(get_platform_dependencies)
    local external_deps=$(get_external_dependencies) 
    local internal_deps=$(get_internal_dependencies)
    echo "$platform_deps $external_deps $internal_deps" | tr -s ' '
}

# Load environment variables from config
load_environment_variables() {
    if command -v yq &> /dev/null && [[ "$ENV_VARS" != "{}" ]]; then
        log_info "Loading environment variables from ci/config.yaml"
        
        # Export environment variables from config
        while IFS="=" read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                export "$key"="$value"
                log_info "Set $key=$value"
            fi
        done < <(echo "$ENV_VARS" | jq -r 'to_entries[] | "\(.key)=\(.value)"' 2>/dev/null || echo "")
        
        log_success "Environment variables loaded from config"
    else
        log_info "No environment variables specified in config"
    fi
}

# Validate service contract compliance
validate_service_contract() {
    log_info "Validating service contract compliance..."
    
    # Basic validation - platform will handle detailed checks
    if [[ -z "$SERVICE_NAME" ]]; then
        log_error "service.name is required in ci/config.yaml"
        exit 1
    fi
    
    if [[ -z "$NAMESPACE" ]]; then
        log_error "service.namespace is required in ci/config.yaml"
        exit 1
    fi
    
    log_success "Service contract validated for: $SERVICE_NAME"
}

# Legacy argument parsing (for backward compatibility during migration)
parse_legacy_arguments() {
    if [[ $# -eq 0 ]]; then
        return 0  # No arguments - use filesystem contract
    fi
    
    log_warn "Legacy argument mode detected - consider migrating to filesystem contract"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --service=*)
                SERVICE_NAME="${1#*=}"
                shift
                ;;
            --test-path=*)
                TEST_PATH="${1#*=}"
                shift
                ;;
            --test-name=*)
                TEST_NAME="${1#*=}"
                shift
                ;;
            --timeout=*)
                TIMEOUT="${1#*=}"
                shift
                ;;
            --image-tag=*)
                IMAGE_TAG="${1#*=}"
                shift
                ;;
            --namespace=*)
                NAMESPACE="${1#*=}"
                shift
                ;;
            --platform-branch=*)
                PLATFORM_BRANCH="${1#*=}"
                shift
                ;;
            *)
                log_error "Unknown argument: $1"
                echo "Usage: $0 [legacy arguments] or use filesystem contract (recommended)"
                exit 1
                ;;
        esac
    done
    
    # Validate legacy required arguments
    if [[ -z "$TEST_PATH" ]]; then
        log_error "Test path is required in legacy mode. Use --test-path=<path>"
        exit 1
    fi
    
    if [[ -z "$TEST_NAME" ]]; then
        log_error "Test name is required in legacy mode. Use --test-name=<name>"
        exit 1
    fi
}

# Get script directory and determine paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Platform root will be determined after checkout
PLATFORM_ROOT=""

# Main execution flow
main() {
    # Initialize stage cache
    init_stage_cache
    
    # Step 1: Parse arguments (legacy support) or use filesystem contract
    parse_legacy_arguments "$@"
    
    # Step 2: Load service configuration from filesystem contract
    if [[ $# -eq 0 ]]; then
        load_service_config
        validate_service_contract
        load_environment_variables
    fi
    
    # Step 2.5: Set platform root path early (needed for detect_environment)
    if [[ -d "../zerotouch-platform" ]]; then
        PLATFORM_ROOT="$(cd ../zerotouch-platform && pwd)"
    elif [[ -d "./zerotouch-platform" ]]; then
        PLATFORM_ROOT="$(cd ./zerotouch-platform && pwd)"
    else
        log_error "Platform directory not found. Expected ../zerotouch-platform or ./zerotouch-platform"
        exit 1
    fi
    export PLATFORM_ROOT
    
    # Step 3: Detect environment (PR vs main)
    ENVIRONMENT=$(detect_environment)
    log_info "Detected environment: $ENVIRONMENT"
    
    echo "================================================================================"
    echo "Centralized In-Cluster Test Script (Filesystem Contract)"
    echo "================================================================================"
    echo "  Service:     ${SERVICE_NAME}"
    echo "  Namespace:   ${NAMESPACE}"
    echo "  Environment: ${ENVIRONMENT}"
    echo "  Test Path:   ${TEST_PATH:-auto-discovered}"
    echo "  Test Name:   ${TEST_NAME:-auto-discovered}"
    echo "  Timeout:     ${TIMEOUT}s"
    echo "  Image Tag:   ${IMAGE_TAG}"
    echo "================================================================================"
    
    # Export environment variables for scripts
    export SERVICE_NAME="${SERVICE_NAME}"
    export IMAGE_TAG="${IMAGE_TAG}"
    export NAMESPACE="${NAMESPACE}"
    export ENVIRONMENT="${ENVIRONMENT}"
    export TEST_PATH="${TEST_PATH}"
    export TEST_NAME="${TEST_NAME}"
    export TIMEOUT="${TIMEOUT}"
    export JWT_SECRET="test-secret-key-for-ci-testing"
    
    # Continue with existing workflow steps...
    run_ci_workflow
}

run_ci_workflow() {

# Cleanup function (matches workflow cleanup step)
cleanup() {
    # Clear cache on failure
    if [[ $? -ne 0 ]]; then
        log_warn "Clearing stage cache due to failure"
        clear_stage_cache
    fi
    
    # Use dedicated cleanup script for better modularity
    CLEANUP_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/cleanup-failed-pods.sh"
    if [[ -f "$CLEANUP_SCRIPT" ]]; then
        chmod +x "$CLEANUP_SCRIPT"
        "$CLEANUP_SCRIPT" "${SERVICE_NAME}" "${NAMESPACE}" "${TEST_NAME:-}"
    else
        log_warn "Cleanup script not found: $CLEANUP_SCRIPT"
        log_info "Performing basic cleanup..."
        
        if [[ "${CLEANUP_CLUSTER:-true}" == "true" ]]; then
            log_info "Cleaning up Kind cluster..."
            kind delete cluster --name zerotouch-preview || true
            clear_stage_cache
        fi
    fi
}

# Error handler
error_handler() {
    local exit_code=$?
    local line_number=$1
    log_error "Script failed at line $line_number with exit code $exit_code"
    log_error "Last command: $BASH_COMMAND"
    cleanup
    exit $exit_code
}

trap 'error_handler $LINENO' ERR
trap cleanup EXIT

    # Infrastructure Setup (CI Environment Only)
    if is_stage_complete "infrastructure"; then
        log_info "Skipping Infrastructure Setup (cached)"
    else
        log_info "Infrastructure Setup: Checkout and bootstrap platform"
        setup_ci_infrastructure
        mark_stage_complete "infrastructure"
    fi
    
    # Stage 1: Platform Readiness
    if is_stage_complete "platform_readiness"; then
        log_info "Skipping Stage 1: Platform Readiness (cached)"
    else
        log_info "Stage 1: Platform Readiness - Validate platform components service needs"
        PLATFORM_READINESS_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/validation/check-platform-readiness.sh"
        if [[ -f "$PLATFORM_READINESS_SCRIPT" ]]; then
            chmod +x "$PLATFORM_READINESS_SCRIPT"
            "$PLATFORM_READINESS_SCRIPT" --wait --timeout 300
        else
            log_error "Platform readiness script not found: $PLATFORM_READINESS_SCRIPT"
            exit 1
        fi
        mark_stage_complete "platform_readiness"
    fi

    # Stage 2: External Dependencies
    if is_stage_complete "external_dependencies"; then
        log_info "Skipping Stage 2: External Dependencies (cached)"
    else
        log_info "Stage 2: External Dependencies - Deploy other services this service depends on"
        EXTERNAL_DEPS_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/setup-external-dependencies.sh"
        if [[ -f "$EXTERNAL_DEPS_SCRIPT" ]]; then
            chmod +x "$EXTERNAL_DEPS_SCRIPT"
            "$EXTERNAL_DEPS_SCRIPT"
        else
            log_error "External dependencies script not found: $EXTERNAL_DEPS_SCRIPT"
            exit 1
        fi

        # Pre-deploy diagnostics
        log_info "Pre-deploy diagnostics: Validate external dependencies"
        PRE_DEPLOY_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/validation/pre-deploy-diagnostics.sh"
        if [[ -f "$PRE_DEPLOY_SCRIPT" ]]; then
            chmod +x "$PRE_DEPLOY_SCRIPT"
            "$PRE_DEPLOY_SCRIPT"
        else
            log_error "Pre-deploy diagnostics script not found: $PRE_DEPLOY_SCRIPT"
            exit 1
        fi
        mark_stage_complete "external_dependencies"
    fi

    # Stage 3: Service Deployment
    # Always run deployment stage (code changes require redeployment)
    log_info "Stage 3: Service Deployment - Build, patch, and deploy the service"
    
    # Step 3a: Docker Registry Authentication (if in CI mode)
    if [[ "${GITHUB_ACTIONS:-}" == "true" && -n "${BOT_GITHUB_TOKEN:-}" && -n "${BOT_GITHUB_USERNAME:-}" ]]; then
        log_info "Authenticating with GitHub Container Registry..."
        if echo "$BOT_GITHUB_TOKEN" | docker login ghcr.io -u "$BOT_GITHUB_USERNAME" --password-stdin; then
            log_success "Successfully authenticated with GHCR"
        else
            log_error "Failed to authenticate with GitHub Container Registry"
            exit 1
        fi
    else
        log_info "Skipping Docker registry authentication (not in CI or credentials not available)"
    fi
    
    # Step 3b: Build service image (Platform auto-detects mode) - Skip if using pre-built artifact
    if [[ -n "${OVERRIDE_IMAGE_TAG:-}" ]]; then
        log_info "Skipping service build - using pre-built artifact: ${OVERRIDE_IMAGE_TAG}"
        # Set the build variables for downstream scripts
        BUILD_MODE="artifact"
        IMAGE_TAG="${OVERRIDE_IMAGE_TAG}"
        if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
            echo "BUILD_MODE=artifact" >> "$GITHUB_OUTPUT"
            echo "IMAGE_TAG=${OVERRIDE_IMAGE_TAG}" >> "$GITHUB_OUTPUT"
        fi
    else
        log_info "Building service image..."
        BUILD_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/build-service.sh"
        if [[ -f "$BUILD_SCRIPT" ]]; then
            chmod +x "$BUILD_SCRIPT"
            # Run build script from service directory
            "$BUILD_SCRIPT" "${SERVICE_NAME}"
            
            # Read back vars (For local run, we manually set defaults if GITHUB_OUTPUT missing)
            if [[ -f "${GITHUB_OUTPUT:-}" ]]; then
                BUILD_MODE=$(grep "BUILD_MODE=" "$GITHUB_OUTPUT" | cut -d'=' -f2 || echo "test")
                IMAGE_TAG=$(grep "IMAGE_TAG=" "$GITHUB_OUTPUT" | cut -d'=' -f2 || echo "ci-test")
            else
                # Fallback for local execution if not in GHA
                BUILD_MODE="test"
                IMAGE_TAG="${SERVICE_NAME}:ci-test"
            fi
            
            log_success "Build completed - Mode: $BUILD_MODE, Tag: $IMAGE_TAG"
        else
            log_error "Build script not found: $BUILD_SCRIPT"
            exit 1
        fi
    fi

    # Step 3c: Checkout PR claims (if in PR environment)
    log_info "Forcing PR claims checkout for CI testing (environment: $ENVIRONMENT -> pr)"
    CHECKOUT_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/checkout-pr-claims.sh"
    
    if [[ -f "$CHECKOUT_SCRIPT" ]]; then
        chmod +x "$CHECKOUT_SCRIPT"
        log_info "Calling checkout script: $CHECKOUT_SCRIPT pr $NAMESPACE $SERVICE_ROOT"
        
        if "$CHECKOUT_SCRIPT" "pr" "$NAMESPACE" "$SERVICE_ROOT"; then
            log_info "✅ PR claims checkout completed successfully"
        else
            log_error "❌ PR claims checkout failed with exit code: $?"
            exit 1
        fi
    else
        log_error "PR claims checkout script not found: $CHECKOUT_SCRIPT"
        exit 1
    fi
    
    # Step 3d: Patch service deployment manifests
    log_info "Patching service deployment manifests..."
    PATCH_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/patch-service-images.sh"
    if [[ -f "$PATCH_SCRIPT" ]]; then
        chmod +x "$PATCH_SCRIPT"
        # Use the final image tag (either from build or override)
        FINAL_IMAGE_TAG="${OVERRIDE_IMAGE_TAG:-$IMAGE_TAG}"
        # Run patch script from service directory to access platform/claims
        "$PATCH_SCRIPT" "${SERVICE_NAME}" "${BUILD_MODE}" "${FINAL_IMAGE_TAG}"
        log_success "Manifest patching completed"
    else
        log_error "Patch script not found: $PATCH_SCRIPT"
        exit 1
    fi
    
    # Apply service-specific patches to claims before deployment
    log_info "Applying service-specific patches to platform claims..."
    SERVICE_PATCHES_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/apply-service-patches.sh"
    if [[ -f "$SERVICE_PATCHES_SCRIPT" ]]; then
        chmod +x "$SERVICE_PATCHES_SCRIPT"
        # Use the SERVICE_ROOT that was set earlier (should be service-code directory)
        log_info "Service root directory: $SERVICE_ROOT"
        log_info "Platform root directory: $PLATFORM_ROOT"
        "$SERVICE_PATCHES_SCRIPT" --service-dir "$SERVICE_ROOT"
    else
        log_error "Service patches script not found: $SERVICE_PATCHES_SCRIPT"
        exit 1
    fi
    
    # Determine which tag to deploy
    FINAL_IMAGE_TAG="${OVERRIDE_IMAGE_TAG:-$IMAGE_TAG}"
    
    # Deploy service
    DEPLOY_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/deploy.sh"
    if [[ -f "$DEPLOY_SCRIPT" ]]; then
        chmod +x "$DEPLOY_SCRIPT"
        # CHANGE: Explicitly pass the calculated tag to deploy.sh
        # deploy.sh accepts: $1=ENVIRONMENT, $2=IMAGE_TAG
        "$DEPLOY_SCRIPT" "ci" "$FINAL_IMAGE_TAG"
    else
        log_error "Deploy script not found: $DEPLOY_SCRIPT"
        exit 1
    fi

    # Run database migrations
    if [[ -d "migrations" ]]; then
        MIGRATIONS_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/run-migrations.sh"
        if [[ -f "$MIGRATIONS_SCRIPT" ]]; then
            chmod +x "$MIGRATIONS_SCRIPT"
            "$MIGRATIONS_SCRIPT" "${NAMESPACE}"
        else
            log_error "Migration script not found: $MIGRATIONS_SCRIPT"
            exit 1
        fi
    else
        log_info "No migrations/ directory found, skipping database migrations"
    fi
    
    mark_stage_complete "service_deployment"

    # Stage 4: Internal Validation
    # Always run validation and tests (verify current state)
    log_info "Stage 4: Internal Validation - Test service's own infrastructure and health"
    POST_DEPLOY_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/validation/post-deploy-diagnostics.sh"
    if [[ -f "$POST_DEPLOY_SCRIPT" ]]; then
        chmod +x "$POST_DEPLOY_SCRIPT"
        "$POST_DEPLOY_SCRIPT"
    else
        log_error "Post-deploy diagnostics script not found: $POST_DEPLOY_SCRIPT"
        exit 1
    fi

    # Run in-cluster tests
    log_info "Run in-cluster tests: Execute integration tests"
    if [[ -n "$TEST_PATH" && -n "$TEST_NAME" ]]; then
        TEST_JOB_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/run-test-job.sh"
        if [[ -f "$TEST_JOB_SCRIPT" ]]; then
            chmod +x "$TEST_JOB_SCRIPT"
            # Use the final image tag (either from build or override)
            FINAL_IMAGE_TAG="${OVERRIDE_IMAGE_TAG:-$IMAGE_TAG}"
            if "$TEST_JOB_SCRIPT" "${TEST_PATH}" "${TEST_NAME}" "${TIMEOUT}" "${NAMESPACE}" "${FINAL_IMAGE_TAG}"; then
                log_success "✅ In-cluster tests completed successfully!"
            else
                log_error "❌ In-cluster tests failed!"
                exit 1
            fi
        else
            log_error "Test job script not found: $TEST_JOB_SCRIPT"
            exit 1
        fi
    else
        log_info "No tests configured, skipping in-cluster tests"
    fi
    
    mark_stage_complete "validation"

    echo ""
    echo "================================================================================"
    echo "CENTRALIZED IN-CLUSTER TEST COMPLETE"
    echo "================================================================================"
    log_success "✅ All CI workflow stages completed successfully!"
    echo "  Service:    ${SERVICE_NAME}"
    echo "  Test:       ${TEST_NAME:-N/A}"
    echo "  Result:     PASSED"
    echo ""
    echo "This script used the filesystem contract for service discovery."
    echo "Stage cache saved to: $STAGE_CACHE_FILE"
    echo "To force full run: SKIP_CACHE=true ./in-cluster-test.sh"
    echo "================================================================================"
}

# Infrastructure setup for CI environment
setup_ci_infrastructure() {
    # Step 1: Checkout repository (simulated - we're already in the repo)
    log_info "Checkout repository (already in repository)"

    # Step 2: Platform checkout handled by service entry point
    log_info "Platform checkout handled by service entry point"
    
    # Set platform root path - in CI, we're in service-code/ and platform is in ../zerotouch-platform/
    if [[ -d "../zerotouch-platform" ]]; then
        PLATFORM_ROOT="$(cd ../zerotouch-platform && pwd)"
    elif [[ -d "./zerotouch-platform" ]]; then
        PLATFORM_ROOT="$(cd ./zerotouch-platform && pwd)"
    else
        log_error "Platform directory not found. Expected ../zerotouch-platform or ./zerotouch-platform"
        exit 1
    fi
    
    # Set service root path - current working directory where ci/config.yaml is located
    SERVICE_ROOT="$(pwd)"
    
    # Export both paths so all child scripts can use them
    export PLATFORM_ROOT
    export SERVICE_ROOT
    log_success "Using platform checkout at: $PLATFORM_ROOT"
    log_success "Using service root at: $SERVICE_ROOT"

    # Step 3: Configure AWS credentials (skip for local - assume already configured)
    log_info "Configure AWS credentials (assuming already configured locally)"

    # Step 4: Set up Docker Buildx (skip for local - assume Docker is available)
    log_info "Set up Docker Buildx (assuming Docker is available locally)"

    # Step 5: Setup Platform Environment
    log_info "Setup Platform Environment"
    PLATFORM_SETUP_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/setup-platform-environment.sh"
    if [[ -f "$PLATFORM_SETUP_SCRIPT" ]]; then
        chmod +x "$PLATFORM_SETUP_SCRIPT"
        # CHANGE: Check for OVERRIDE_IMAGE_TAG env var (passed from GitHub Actions)
        if [[ -n "${OVERRIDE_IMAGE_TAG:-}" ]]; then
            log_info "Using pre-built artifact: ${OVERRIDE_IMAGE_TAG}. Skipping local build."
            # Use a new flag --skip-build to tell the setup script to ONLY do cluster setup & loading
            "$PLATFORM_SETUP_SCRIPT" \
                --service="${SERVICE_NAME}" \
                --image-tag="${OVERRIDE_IMAGE_TAG}" \
                --skip-build=true
        else
            # Default behavior (Builds locally)
            "$PLATFORM_SETUP_SCRIPT" \
                --service="${SERVICE_NAME}" \
                --image-tag="${IMAGE_TAG}"
        fi
    else
        log_error "Platform setup script not found: $PLATFORM_SETUP_SCRIPT"
        exit 1
    fi

    # Step 6: Bootstrap platform
    log_info "Bootstrap platform"
    cd "${PLATFORM_ROOT}"
    if [[ -f "scripts/bootstrap/01-master-bootstrap.sh" ]]; then
        chmod +x scripts/bootstrap/01-master-bootstrap.sh
        ./scripts/bootstrap/01-master-bootstrap.sh --mode preview
    else
        log_error "Master bootstrap script not found: scripts/bootstrap/01-master-bootstrap.sh"
        exit 1
    fi

    # Return to service directory (assuming we're running from service root)
    cd - > /dev/null

    # Step 7: Apply platform patches (including conditional services)
    log_info "Apply platform patches"
    
    # Apply platform patches with conditional services
    cd "${PLATFORM_ROOT}"
    PATCHES_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/patches/00-apply-all-patches.sh"
    if [[ -f "$PATCHES_SCRIPT" ]]; then
        chmod +x "$PATCHES_SCRIPT"
        "$PATCHES_SCRIPT" --force
    else
        log_error "Preview patches script not found: $PATCHES_SCRIPT"
        exit 1
    fi
    cd - > /dev/null
    
    # Step 8: Synchronize required platform components
    log_info "Synchronize required platform components"
    SYNC_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/sync-platform-components.sh"
    if [[ -f "$SYNC_SCRIPT" ]]; then
        chmod +x "$SYNC_SCRIPT"
        "$SYNC_SCRIPT"
    else
        log_error "Platform sync script not found: $SYNC_SCRIPT"
        exit 1
    fi
    
    # Step 9: Additional settling time for ArgoCD operations
    log_info "Allowing additional time for ArgoCD operations to settle..."
    sleep 15
    log_success "Infrastructure setup completed - ArgoCD operations have settled"
}

# Call main function with all arguments
main "$@"
#!/bin/bash
set -euo pipefail

# 04-verify-persistence.sh - Validate hybrid persistence with S3 backup and restore

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Source helper scripts
source "${SCRIPT_DIR}/helpers/verify-persistence/validator.sh"
source "${SCRIPT_DIR}/helpers/verify-persistence/tester.sh"
source "${SCRIPT_DIR}/helpers/verify-persistence/cleaner.sh"

# Default values
TENANT_NAME="${TENANT_NAME:-deepagents-runtime}"
NAMESPACE="${NAMESPACE:-intelligence-deepagents}"
VERBOSE="${VERBOSE:-false}"
CLEANUP="${CLEANUP:-true}"

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ  $1${NC}"
}

log_step() {
    echo -e "${BLUE}Step: $1${NC}"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Kubectl retry function
kubectl_retry() {
    local max_attempts=20
    local timeout=15
    local attempt=1
    local exitCode=0

    while [ $attempt -le $max_attempts ]; do
        if timeout $timeout kubectl "$@"; then
            return 0
        fi
        exitCode=$?
        if [ $attempt -lt $max_attempts ]; then
            local delay=$((attempt * 2))
            log_warn "kubectl command failed (attempt $attempt/$max_attempts). Retrying in ${delay}s..."
            sleep $delay
        fi
        attempt=$((attempt + 1))
    done
    log_error "kubectl command failed after $max_attempts attempts"
    return $exitCode
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate AgentSandboxService hybrid persistence functionality in live cluster.

OPTIONS:
    --tenant <name>     Specify tenant for testing (default: deepagents-runtime)
    --namespace <name>  Override default namespace (default: intelligence-deepagents)
    --verbose           Enable detailed logging of cluster operations
    --no-cleanup        Skip cleanup of test resources after validation
    --help              Show this help message

VALIDATION CRITERIA:
    - InitContainer downloads workspace from real S3 on startup
    - Sidecar continuously backs up workspace changes to real S3
    - PreStop hook performs final backup on termination in live cluster
    - Workspace PVC sized correctly from storageGB field in live cluster
    - "Resurrection Test" passes (file survives actual pod recreation in cluster)

EXIT CODES:
    0 - All validations passed
    1 - Critical validation failed
    2 - Configuration error
    3 - Environment not ready
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tenant)
            TENANT_NAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --no-cleanup)
            CLEANUP=false
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 2
            ;;
    esac
done

main() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   AgentSandboxService Hybrid Persistence Validation         ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log_info "Starting AgentSandboxService hybrid persistence validation"
    log_info "Tenant: ${TENANT_NAME}, Namespace: ${NAMESPACE}"
    echo ""
    
    # Step 1: Validate environment and prerequisites
    log_step "1. Validating environment and prerequisites"
    if ! validate_environment; then
        log_error "Environment validation failed"
        exit 3
    fi
    echo ""
    
    # Step 2: Create test claim with persistence configuration
    log_step "2. Creating test AgentSandboxService claim with persistence"
    if ! create_test_claim; then
        log_error "Failed to create test claim"
        exit 1
    fi
    echo ""
    
    # Step 3: Validate PVC sizing from storageGB field
    log_step "3. Validating PVC sizing from storageGB field"
    if ! validate_pvc_sizing; then
        log_error "PVC sizing validation failed"
        exit 1
    fi
    echo ""
    
    # Step 4: Wait for pod to be ready and validate initContainer
    log_step "4. Validating initContainer workspace hydration"
    if ! validate_init_container; then
        log_error "InitContainer validation failed"
        exit 1
    fi
    echo ""
    
    # Step 5: Test workspace file creation and sidecar backup
    log_step "5. Testing workspace file creation and sidecar backup"
    if ! test_sidecar_backup; then
        log_error "Sidecar backup validation failed"
        exit 1
    fi
    echo ""
    
    # Step 6: Perform "Resurrection Test" - delete pod and verify file survives
    log_step "6. Performing Resurrection Test (file survives pod recreation)"
    if ! test_resurrection; then
        log_error "Resurrection Test failed"
        exit 1
    fi
    echo ""
    
    # Step 7: Test preStop hook final backup
    log_step "7. Testing preStop hook final backup"
    if ! test_prestop_backup; then
        log_error "PreStop hook validation failed"
        exit 1
    fi
    echo ""
    
    # Step 8: Cleanup test resources
    if [[ "${CLEANUP}" == "true" ]]; then
        log_step "8. Cleaning up test resources"
        cleanup_test_resources
        echo ""
    fi
    
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   All hybrid persistence validations passed successfully!   ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_success "AgentSandboxService hybrid persistence is ready for scaling"
}

# Execute main function
main "$@"
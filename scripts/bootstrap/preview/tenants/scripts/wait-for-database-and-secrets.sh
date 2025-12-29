#!/bin/bash
set -euo pipefail

# ==============================================================================
# Wait for Database and External Secrets Script
# ==============================================================================
# Purpose: Wait for PostgresInstance and ExternalSecrets to be ready before app deployment
# Usage: ./wait-for-database-and-secrets.sh <service-name> <namespace>
# ==============================================================================

SERVICE_NAME="${1:?Service name required}"
NAMESPACE="${2:?Namespace required}"

# Get script directory for finding other platform scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Use PLATFORM_ROOT from environment if set, otherwise calculate it
if [[ -z "${PLATFORM_ROOT:-}" ]]; then
    PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[DB-SECRETS-WAIT]${NC} $*"; }
log_success() { echo -e "${GREEN}[DB-SECRETS-WAIT]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[DB-SECRETS-WAIT]${NC} $*"; }
log_error() { echo -e "${RED}[DB-SECRETS-WAIT]${NC} $*"; }

# Function to wait for PostgresInstance to be ready
wait_for_database() {
    log_info "Waiting for PostgresInstance to be ready..."
    
    if kubectl wait --for=condition=Ready postgresinstance/${SERVICE_NAME}-db -n ${NAMESPACE} --timeout=120s; then
        log_success "PostgresInstance ${SERVICE_NAME}-db is ready"
    else
        log_warn "PostgresInstance wait timed out, but continuing..."
    fi
}

# Function to wait for a single external secret
wait_for_external_secret() {
    local secret_name="$1"
    local timeout="${2:-60}"
    
    log_info "Waiting for secret: $secret_name"
    
    # Use platform's external secret wait script if available
    WAIT_SECRET_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/wait/wait-for-external-secret.sh"
    
    if [[ -f "$WAIT_SECRET_SCRIPT" ]]; then
        chmod +x "$WAIT_SECRET_SCRIPT"
        if "$WAIT_SECRET_SCRIPT" "$secret_name" "${NAMESPACE}" --timeout "$timeout"; then
            log_success "Secret $secret_name is ready"
        else
            log_warn "Secret $secret_name sync timed out"
            return 1
        fi
    else
        # Fallback to simple kubectl wait
        log_warn "Platform wait script not found, using fallback method"
        if timeout "${timeout}s" bash -c "until kubectl get secret $secret_name -n ${NAMESPACE} &>/dev/null; do sleep 2; done"; then
            log_success "Secret $secret_name is ready"
        else
            log_warn "Secret $secret_name not found after ${timeout}s"
            return 1
        fi
    fi
}

# Function to wait for all required external secrets
wait_for_external_secrets() {
    log_info "Waiting for all required ExternalSecrets to sync..."
    
    # Define required secrets - these must match platform/claims/ namespace
    local required_secrets=(
        "ghcr-pull-secret"
        "${SERVICE_NAME}-app-secrets"
        "${SERVICE_NAME}-jwt-keys"
    )
    
    local failed_secrets=()
    
    for secret in "${required_secrets[@]}"; do
        if ! wait_for_external_secret "$secret" 60; then
            failed_secrets+=("$secret")
        fi
    done
    
    if [[ ${#failed_secrets[@]} -gt 0 ]]; then
        log_warn "Some secrets failed to sync: ${failed_secrets[*]}"
        log_warn "Pod may crash and restart until secrets are available"
        
        # Show ExternalSecret status for debugging
        for secret in "${failed_secrets[@]}"; do
            log_info "Checking ExternalSecret status for: $secret"
            kubectl describe externalsecret "$secret" -n "${NAMESPACE}" 2>/dev/null || \
            log_warn "ExternalSecret $secret not found"
        done
        
        return 1
    else
        log_success "All required secrets are ready"
        return 0
    fi
}

# Function to wait for database connection secret (created by Crossplane)
wait_for_database_secret() {
    local db_secret="${SERVICE_NAME}-db-conn"
    
    log_info "Waiting for database connection secret: $db_secret"
    
    if timeout 60s bash -c "until kubectl get secret $db_secret -n ${NAMESPACE} &>/dev/null; do sleep 2; done"; then
        log_success "Database connection secret is ready"
    else
        log_warn "Database connection secret not ready after 60s"
        return 1
    fi
}

# Main function to wait for all database and secret dependencies
wait_for_database_and_secrets() {
    log_info "Starting database and secrets dependency checks for ${SERVICE_NAME} in ${NAMESPACE}"
    
    local exit_code=0
    
    # Wait for database cluster
    if ! wait_for_database; then
        exit_code=1
    fi
    
    # Wait for database connection secret
    if ! wait_for_database_secret; then
        exit_code=1
    fi
    
    # Wait for external secrets
    if ! wait_for_external_secrets; then
        exit_code=1
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "All database and secret dependencies are ready"
    else
        log_warn "Some dependencies are not ready, but continuing..."
        log_warn "Application may experience startup issues until dependencies are available"
    fi
    
    return $exit_code
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    wait_for_database_and_secrets
fi
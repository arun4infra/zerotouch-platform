#!/bin/bash
set -euo pipefail

# ==============================================================================
# Platform Post-Deploy Diagnostics Script (Config-Driven)
# ==============================================================================
# Purpose: Service health verification after deployment using ci/config.yaml
# Usage: ./post-deploy-diagnostics.sh
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[POST-DEPLOY]${NC} $*"; }
log_success() { echo -e "${GREEN}[POST-DEPLOY]${NC} $*"; }
log_error() { echo -e "${RED}[POST-DEPLOY]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[POST-DEPLOY]${NC} $*"; }

# Load service configuration from ci/config.yaml
load_service_config() {
    # Get the script directory and calculate service root
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # In CI, we're in service-code subdirectory, so service root is current working directory
    local service_root="$(pwd)"
    local config_file="${SERVICE_ROOT:-$(pwd)}/ci/config.yaml"
    
    log_info "Debug: Script dir: $script_dir"
    log_info "Debug: Service root: $service_root" 
    log_info "Debug: Config file: $config_file"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "ci/config.yaml not found - cannot run diagnostics"
        log_error "Looked for: $config_file"
        exit 1
    fi
    
    if command -v yq &> /dev/null; then
        SERVICE_NAME=$(yq eval '.service.name' "$config_file")
        NAMESPACE=$(yq eval '.service.namespace' "$config_file")
        HEALTH_ENDPOINT=$(yq eval '.deployment.health_endpoint // "/ready"' "$config_file")
        LIVENESS_ENDPOINT=$(yq eval '.deployment.liveness_endpoint // "/health"' "$config_file")
        WAIT_TIMEOUT=$(yq eval '.deployment.wait_timeout // 300' "$config_file")
        PLATFORM_SERVICE_TYPE=$(yq eval '.platform.service.type // ""' "$config_file")
        PLATFORM_SERVICE_NAME=$(yq eval '.platform.service.name // ""' "$config_file")
        K8S_SERVICE_NAME=$(yq eval '.platform.service.k8s_service_name // .service.name' "$config_file")
    else
        log_error "yq is required but not installed"
        exit 1
    fi
    
    # Set deployment name to service name (platform standard)
    DEPLOYMENT_NAME="${SERVICE_NAME}"
    
    log_info "Service config loaded: ${SERVICE_NAME} in ${NAMESPACE}"
    log_info "Health endpoints: ${HEALTH_ENDPOINT}, ${LIVENESS_ENDPOINT}"
    if [[ -n "$PLATFORM_SERVICE_TYPE" ]]; then
        log_info "Platform service: ${PLATFORM_SERVICE_TYPE}/${PLATFORM_SERVICE_NAME}"
        log_info "K8s service: ${K8S_SERVICE_NAME}"
    fi
}

# Helper function to check if a diagnostic is enabled
diagnostic_enabled() {
    local diagnostic_path="$1"
    if command -v yq &> /dev/null; then
        local value=$(yq eval ".diagnostics.post_deploy.${diagnostic_path} // true" "${SERVICE_ROOT:-$(pwd)}/ci/config.yaml" 2>/dev/null)
        [[ "$value" == "true" ]]
    else
        # Default to enabled if yq not available
        return 0
    fi
}

# Load configuration
load_service_config

echo "================================================================================"
echo "Platform Post-Deploy Diagnostics"
echo "================================================================================"
echo "  Service:    ${SERVICE_NAME}"
echo "  Namespace:  ${NAMESPACE}"
echo "  Deployment: ${DEPLOYMENT_NAME}"
echo "================================================================================"

# Check deployment or platform service status
log_info "Checking service status..."

if [[ -n "$PLATFORM_SERVICE_TYPE" && "$PLATFORM_SERVICE_TYPE" == "agentsandboxservices" ]]; then
    # Check AgentSandboxService status
    if ! kubectl get "$PLATFORM_SERVICE_TYPE" "$PLATFORM_SERVICE_NAME" -n "${NAMESPACE}" &>/dev/null; then
        log_error "Platform service ${PLATFORM_SERVICE_TYPE}/${PLATFORM_SERVICE_NAME} not found"
        exit 1
    fi
    
    ready_status=$(kubectl get "$PLATFORM_SERVICE_TYPE" "$PLATFORM_SERVICE_NAME" -n "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' || echo "Unknown")
    log_info "Platform service status: Ready=${ready_status}"
    
    if [[ "$ready_status" != "True" ]]; then
        log_error "Platform service is not ready"
        exit 1
    fi
    
    log_success "Platform service is ready"
else
    # Check Deployment status
    if ! kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" &>/dev/null; then
        log_error "Deployment ${DEPLOYMENT_NAME} not found"
        exit 1
    fi

    ready_replicas=$(kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' || echo "0")
    desired_replicas=$(kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' || echo "1")
    available_replicas=$(kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.availableReplicas}' || echo "0")

    log_info "Deployment status: Ready ${ready_replicas}/${desired_replicas}, Available ${available_replicas}/${desired_replicas}"

    if [[ "${ready_replicas}" != "${desired_replicas}" ]]; then
        log_error "Deployment is not fully ready"
        exit 1
    fi

    log_success "Deployment is ready"
fi

# Check pod status
log_info "Checking pod status..."
kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=${SERVICE_NAME}" -o wide

# Check running pods (exclude Jobs with Succeeded status)
failed_pods=$(kubectl get pods -n "${NAMESPACE}" \
  -l "app.kubernetes.io/name=${SERVICE_NAME}" \
  --field-selector=status.phase!=Running,status.phase!=Succeeded \
  --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "${failed_pods}" -gt 0 ]]; then
    log_error "Found ${failed_pods} failed pods"
    kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=${SERVICE_NAME}" --field-selector=status.phase!=Running,status.phase!=Succeeded
    exit 1
fi

log_success "All pods are running"

# Check service
log_info "Checking service..."
if kubectl get service "${K8S_SERVICE_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    log_success "Service ${K8S_SERVICE_NAME} exists"
    kubectl get service "${K8S_SERVICE_NAME}" -n "${NAMESPACE}" -o wide
else
    log_error "Service ${K8S_SERVICE_NAME} not found"
    exit 1
fi

# Test service connectivity (if enabled)
if diagnostic_enabled "test_service_connectivity"; then
    log_info "Testing service connectivity..."
    service_ip=$(kubectl get service "${K8S_SERVICE_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.clusterIP}')
    service_port=$(kubectl get service "${K8S_SERVICE_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].port}')

    if [[ -n "${service_ip}" && -n "${service_port}" ]]; then
        log_info "Testing connection to ${service_ip}:${service_port}..."
        
        # Skip connectivity test for AgentSandboxService (scaled to zero when idle)
        if [[ -n "$PLATFORM_SERVICE_TYPE" && "$PLATFORM_SERVICE_TYPE" == "agentsandboxservices" ]]; then
            log_info "Skipping connectivity test for AgentSandboxService (event-driven, scaled to zero when idle)"
        else
            if kubectl run connectivity-test-$(date +%s) \
                --image=curlimages/curl:latest \
                --rm -i --restart=Never \
                --timeout=30s \
                -- curl -s --connect-timeout 10 "http://${service_ip}:${service_port}" >/dev/null 2>&1; then
                log_success "Service connectivity test passed"
            else
                log_error "Service connectivity test failed"
                exit 1
            fi
        fi
    else
        log_warn "Could not determine service IP or port"
    fi
else
    log_info "Service connectivity test disabled"
fi

# Test health endpoints (if enabled)
if diagnostic_enabled "test_health_endpoint"; then
    log_info "Testing health endpoints..."
    service_ip=$(kubectl get service "${K8S_SERVICE_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.clusterIP}')
    service_port=$(kubectl get service "${K8S_SERVICE_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].port}')

    if [[ -n "${service_ip}" && -n "${service_port}" ]]; then
        # Skip health endpoint test for AgentSandboxService (scaled to zero when idle)
        if [[ -n "$PLATFORM_SERVICE_TYPE" && "$PLATFORM_SERVICE_TYPE" == "agentsandboxservices" ]]; then
            log_info "Skipping health endpoint test for AgentSandboxService (event-driven, scaled to zero when idle)"
        else
            # Test readiness endpoint
            if kubectl run readiness-test-$(date +%s) \
                --image=curlimages/curl:latest \
                --rm -i --restart=Never \
                --timeout=30s \
                -- curl -s -f "http://${service_ip}:${service_port}${HEALTH_ENDPOINT}" >/dev/null 2>&1; then
                log_success "Readiness endpoint ${HEALTH_ENDPOINT} is responding"
            else
                log_error "Readiness endpoint ${HEALTH_ENDPOINT} not responding"
                exit 1
            fi
            
            # Test liveness endpoint
            if kubectl run liveness-test-$(date +%s) \
                --image=curlimages/curl:latest \
                --rm -i --restart=Never \
                --timeout=30s \
                -- curl -s -f "http://${service_ip}:${service_port}${LIVENESS_ENDPOINT}" >/dev/null 2>&1; then
                log_success "Liveness endpoint ${LIVENESS_ENDPOINT} is responding"
            else
                log_error "Liveness endpoint ${LIVENESS_ENDPOINT} not responding"
                exit 1
            fi
        fi
    else
        log_warn "Could not determine service IP/port for health checks"
    fi
else
    log_info "Health endpoint tests disabled"
fi

# Test database connection (if enabled)
if diagnostic_enabled "test_database_connection"; then
    log_info "Testing database connection..."
    
    # Check for standard database secret
    db_secret="${SERVICE_NAME}-db-conn"
    if kubectl get secret "$db_secret" -n "${NAMESPACE}" &>/dev/null; then
        log_success "Database secret $db_secret exists"
        
        # Test connection from application pod
        pod_name=$(kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=${SERVICE_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        
        if [[ -n "$pod_name" ]]; then
            log_info "Testing database connection from pod ${pod_name}..."
            
            # Test using standard environment variables
            if kubectl exec "${pod_name}" -n "${NAMESPACE}" -- sh -c '
                if command -v psql &> /dev/null && [ -n "${POSTGRES_HOST:-}" ]; then
                    PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "SELECT 1;" &>/dev/null && echo "Database connection successful" || echo "Database connection failed"
                else
                    echo "Database connection test skipped (psql not available or env vars not set)"
                fi
            ' 2>/dev/null; then
                log_success "Database connection test completed"
            else
                log_warn "Could not test database connection"
            fi
        else
            log_warn "No application pod found for database connection test"
        fi
    else
        log_info "No database secret found (service may not use database)"
    fi
else
    log_info "Database connection test disabled"
fi

# Check logs for errors
log_info "Checking recent logs for errors..."
if kubectl logs -n "${NAMESPACE}" -l "app.kubernetes.io/name=${SERVICE_NAME}" --tail=20 2>/dev/null | grep -i error; then
    log_warn "Errors found in recent logs"
else
    log_success "No errors found in recent logs"
fi

# Resource usage
log_info "Checking resource usage..."
if kubectl top pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=${SERVICE_NAME}" &>/dev/null; then
    kubectl top pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=${SERVICE_NAME}"
else
    log_info "Metrics not available"
fi

log_success "Post-deployment diagnostics completed successfully!"
log_success "Service is healthy and ready"
#!/bin/bash
# validator.sh - Environment validation for hybrid persistence testing

validate_environment() {
    log_info "Validating environment for hybrid persistence testing"
    
    # Check kubectl access
    if ! kubectl cluster-info &>/dev/null; then
        log_error "kubectl cluster access failed"
        return 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
        log_error "Namespace ${NAMESPACE} does not exist"
        return 1
    fi
    
    # Check if AgentSandboxService XRD is installed
    if ! kubectl get xrd xagentsandboxservices.platform.bizmatters.io &>/dev/null; then
        log_error "AgentSandboxService XRD not found"
        return 1
    fi
    
    # Check if aws-access-token secret exists
    if ! kubectl get secret aws-access-token -n "${NAMESPACE}" &>/dev/null; then
        log_error "aws-access-token secret not found in namespace ${NAMESPACE}"
        return 1
    fi
    
    # Check if agent-sandbox controller is running
    if ! kubectl get pods -n agent-sandbox-system -l app=agent-sandbox-controller --field-selector=status.phase=Running | grep -q Running; then
        log_error "agent-sandbox-controller not running"
        return 1
    fi
    
    log_success "Environment validation passed"
    return 0
}

validate_pvc_sizing() {
    local claim_name="test-persistence-sandbox"
    local expected_size="25Gi"  # From test claim storageGB: 25
    
    log_info "Validating PVC sizing for claim: ${claim_name}"
    
    # Wait for PVC to be created
    local timeout=60
    local count=0
    while [[ $count -lt $timeout ]]; do
        if kubectl get pvc "${claim_name}-workspace" -n "${NAMESPACE}" &>/dev/null; then
            break
        fi
        sleep 1
        ((count++))
    done
    
    if [[ $count -ge $timeout ]]; then
        log_error "PVC ${claim_name}-workspace not created within ${timeout} seconds"
        return 1
    fi
    
    # Check PVC size
    local actual_size
    actual_size=$(kubectl get pvc "${claim_name}-workspace" -n "${NAMESPACE}" -o jsonpath='{.spec.resources.requests.storage}')
    
    if [[ "${actual_size}" != "${expected_size}" ]]; then
        log_error "PVC size mismatch. Expected: ${expected_size}, Actual: ${actual_size}"
        return 1
    fi
    
    log_success "PVC sizing validation passed: ${actual_size}"
    return 0
}

validate_init_container() {
    local claim_name="test-persistence-sandbox"
    local pod_name
    
    log_info "Validating initContainer workspace hydration"
    
    # Wait for pod to be created
    local timeout=120
    local count=0
    while [[ $count -lt $timeout ]]; do
        pod_name=$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name="${claim_name}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -n "${pod_name}" ]]; then
            break
        fi
        sleep 2
        ((count++))
    done
    
    if [[ -z "${pod_name}" ]]; then
        log_error "Pod for claim ${claim_name} not found within ${timeout} seconds"
        return 1
    fi
    
    # Wait for initContainer to complete
    log_info "Waiting for initContainer to complete in pod: ${pod_name}"
    count=0
    while [[ $count -lt $timeout ]]; do
        local init_status
        init_status=$(kubectl get pod "${pod_name}" -n "${NAMESPACE}" -o jsonpath='{.status.initContainerStatuses[0].state.terminated.reason}' 2>/dev/null || echo "")
        
        if [[ "${init_status}" == "Completed" ]]; then
            log_success "InitContainer completed successfully"
            break
        elif [[ "${init_status}" == "Error" ]]; then
            log_error "InitContainer failed"
            kubectl logs "${pod_name}" -n "${NAMESPACE}" -c workspace-hydrator || true
            return 1
        fi
        
        sleep 2
        ((count++))
    done
    
    if [[ $count -ge $timeout ]]; then
        log_error "InitContainer did not complete within ${timeout} seconds"
        kubectl describe pod "${pod_name}" -n "${NAMESPACE}" || true
        return 1
    fi
    
    # Check initContainer logs for success message
    local logs
    logs=$(kubectl logs "${pod_name}" -n "${NAMESPACE}" -c workspace-hydrator 2>/dev/null || echo "")
    
    if [[ "${logs}" == *"Starting workspace hydration from S3"* ]]; then
        log_success "InitContainer workspace hydration validated successfully"
        return 0
    else
        log_error "InitContainer logs do not show expected hydration messages"
        echo "Logs: ${logs}"
        return 1
    fi
}

export -f validate_environment validate_pvc_sizing validate_init_container
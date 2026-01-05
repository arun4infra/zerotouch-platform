#!/bin/bash
# cleaner.sh - Cleanup functions for hybrid persistence testing

cleanup_test_resources() {
    local claim_name="test-persistence-sandbox"
    
    log_info "Cleaning up test resources for hybrid persistence validation"
    
    # Delete the test claim (this will trigger cleanup of all related resources)
    if kubectl get agentsandboxservice "${claim_name}" -n "${NAMESPACE}" &>/dev/null; then
        log_info "Deleting test AgentSandboxService claim: ${claim_name}"
        kubectl delete agentsandboxservice "${claim_name}" -n "${NAMESPACE}" --wait=true --timeout=120s || {
            log_warn "Failed to delete claim cleanly, forcing deletion"
            kubectl patch agentsandboxservice "${claim_name}" -n "${NAMESPACE}" -p '{"metadata":{"finalizers":[]}}' --type=merge || true
            kubectl delete agentsandboxservice "${claim_name}" -n "${NAMESPACE}" --force --grace-period=0 || true
        }
    fi
    
    # Wait for pods to be cleaned up
    log_info "Waiting for pods to be cleaned up"
    local timeout=60
    local count=0
    while [[ $count -lt $timeout ]]; do
        local pod_count
        pod_count=$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name="${claim_name}" --no-headers 2>/dev/null | wc -l)
        if [[ $pod_count -eq 0 ]]; then
            break
        fi
        sleep 2
        ((count++))
    done
    
    # Clean up any remaining resources manually if needed
    cleanup_remaining_resources "${claim_name}"
    
    # Clean up S3 test data (optional - commented out to preserve for debugging)
    # cleanup_s3_test_data "${claim_name}"
    
    log_success "Test resource cleanup completed"
}

cleanup_remaining_resources() {
    local claim_name="$1"
    
    log_info "Checking for remaining resources to clean up"
    
    # Force delete any remaining pods
    local remaining_pods
    remaining_pods=$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name="${claim_name}" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    
    if [[ -n "${remaining_pods}" ]]; then
        log_warn "Force deleting remaining pods"
        echo "${remaining_pods}" | xargs -r kubectl delete pod -n "${NAMESPACE}" --force --grace-period=0 || true
    fi
    
    # Clean up PVC if it still exists
    if kubectl get pvc "${claim_name}-workspace" -n "${NAMESPACE}" &>/dev/null; then
        log_info "Deleting remaining PVC: ${claim_name}-workspace"
        kubectl delete pvc "${claim_name}-workspace" -n "${NAMESPACE}" --wait=true --timeout=60s || {
            log_warn "Failed to delete PVC cleanly, forcing deletion"
            kubectl patch pvc "${claim_name}-workspace" -n "${NAMESPACE}" -p '{"metadata":{"finalizers":[]}}' --type=merge || true
            kubectl delete pvc "${claim_name}-workspace" -n "${NAMESPACE}" --force --grace-period=0 || true
        }
    fi
    
    # Clean up any remaining SandboxTemplate
    if kubectl get sandboxtemplate "${claim_name}" -n "${NAMESPACE}" &>/dev/null; then
        log_info "Deleting remaining SandboxTemplate: ${claim_name}"
        kubectl delete sandboxtemplate "${claim_name}" -n "${NAMESPACE}" --wait=true --timeout=60s || true
    fi
    
    # Clean up any remaining SandboxWarmPool
    if kubectl get sandboxwarmpool "${claim_name}" -n "${NAMESPACE}" &>/dev/null; then
        log_info "Deleting remaining SandboxWarmPool: ${claim_name}"
        kubectl delete sandboxwarmpool "${claim_name}" -n "${NAMESPACE}" --wait=true --timeout=60s || true
    fi
    
    # Clean up ServiceAccount
    if kubectl get serviceaccount "${claim_name}" -n "${NAMESPACE}" &>/dev/null; then
        log_info "Deleting remaining ServiceAccount: ${claim_name}"
        kubectl delete serviceaccount "${claim_name}" -n "${NAMESPACE}" || true
    fi
}

cleanup_s3_test_data() {
    local claim_name="$1"
    local s3_bucket="deepagents-sandbox-workspaces"
    local workspace_key="workspaces/${claim_name}/workspace.tar.gz"
    
    log_info "Cleaning up S3 test data (optional)"
    
    # Check if AWS CLI is available and credentials are configured
    if command -v aws &>/dev/null; then
        # Try to delete the test workspace backup
        if aws s3 ls "s3://${s3_bucket}/${workspace_key}" &>/dev/null; then
            log_info "Deleting S3 test backup: s3://${s3_bucket}/${workspace_key}"
            aws s3 rm "s3://${s3_bucket}/${workspace_key}" || {
                log_warn "Failed to delete S3 test backup - may need manual cleanup"
            }
        fi
    else
        log_info "AWS CLI not available - skipping S3 cleanup"
    fi
}

# Emergency cleanup function for when things go wrong
emergency_cleanup() {
    local claim_name="test-persistence-sandbox"
    
    log_warn "Performing emergency cleanup"
    
    # Force delete everything related to the test
    kubectl delete agentsandboxservice "${claim_name}" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null || true
    kubectl delete pods -n "${NAMESPACE}" -l app.kubernetes.io/name="${claim_name}" --force --grace-period=0 &>/dev/null || true
    kubectl delete pvc "${claim_name}-workspace" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null || true
    kubectl delete sandboxtemplate "${claim_name}" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null || true
    kubectl delete sandboxwarmpool "${claim_name}" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null || true
    kubectl delete serviceaccount "${claim_name}" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null || true
    
    log_warn "Emergency cleanup completed"
}

export -f cleanup_test_resources cleanup_remaining_resources cleanup_s3_test_data emergency_cleanup
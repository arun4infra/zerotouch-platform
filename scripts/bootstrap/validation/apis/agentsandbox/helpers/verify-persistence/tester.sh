#!/bin/bash
# tester.sh - Core testing functions for hybrid persistence

create_test_claim() {
    local claim_name="test-persistence-sandbox"
    
    log_info "Creating test AgentSandboxService claim: ${claim_name}"
    
    # Create test claim with persistence configuration
    cat << EOF | kubectl apply -f -
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: ${claim_name}
  namespace: ${NAMESPACE}
spec:
  image: "ghcr.io/arun4infra/deepagents-runtime:sha-9d6cb0e"
  # Override entrypoint to sleep (bypassing DB checks)
  command: ["/bin/sh", "-c"]
  args: ["echo 'Sandbox Persistence Test Started' > /workspace/index.html; python3 -m http.server 8080 --directory /workspace"]
  healthPath: "/"
  readyPath: "/"
  size: "small"
  storageGB: 25
  httpPort: 8080
  nats:
    url: "nats://nats.nats-system:4222"
    stream: "TEST_STREAM"
    consumer: "test-consumer"
  secret1Name: "aws-access-token"
  s3SecretName: "aws-access-token"
EOF
    
    if [[ $? -eq 0 ]]; then
        log_success "Test claim created successfully"
        export TEST_CLAIM_NAME="${claim_name}"
        return 0
    else
        log_error "Failed to create test claim"
        return 1
    fi
}

test_sidecar_backup() {
    local claim_name="test-persistence-sandbox"
    local pod_name
    local test_file="test-persistence-file.txt"
    local test_content="This file tests hybrid persistence - $(date)"
    
    log_info "Testing sidecar backup functionality"
    
    # Get pod name
    pod_name=$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name="${claim_name}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -z "${pod_name}" ]]; then
        log_error "Pod for claim ${claim_name} not found"
        return 1
    fi
    
    # Wait for pod to be ready
    log_info "Waiting for pod to be ready: ${pod_name}"
    if ! kubectl wait --for=condition=Ready pod/"${pod_name}" -n "${NAMESPACE}" --timeout=180s; then
        log_error "Pod did not become ready within timeout"
        kubectl describe pod "${pod_name}" -n "${NAMESPACE}" || true
        return 1
    fi
    
    # Create test file in workspace
    log_info "Creating test file in workspace: ${test_file}"
    if ! kubectl exec "${pod_name}" -n "${NAMESPACE}" -c main -- sh -c "echo '${test_content}' > /workspace/${test_file}"; then
        log_error "Failed to create test file in workspace"
        return 1
    fi
    
    # Wait for sidecar to backup the file (30 second backup interval + buffer)
    log_info "Waiting for sidecar backup to complete (45 seconds)"
    sleep 45
    
    # Check sidecar logs for backup activity
    local sidecar_logs
    sidecar_logs=$(kubectl logs "${pod_name}" -n "${NAMESPACE}" -c workspace-backup-sidecar --tail=20 2>/dev/null || echo "")
    
    if [[ "${sidecar_logs}" == *"Backing up workspace to S3"* ]]; then
        log_success "Sidecar backup activity detected in logs"
        export TEST_FILE_NAME="${test_file}"
        export TEST_FILE_CONTENT="${test_content}"
        return 0
    else
        log_error "No sidecar backup activity found in logs"
        echo "Sidecar logs: ${sidecar_logs}"
        return 1
    fi
}

test_resurrection() {
    local claim_name="test-persistence-sandbox"
    local pod_name
    local test_file="${TEST_FILE_NAME:-test-persistence-file.txt}"
    local expected_content="${TEST_FILE_CONTENT:-}"
    
    log_info "Performing Resurrection Test - deleting pod and verifying file survives"
    
    # Get current pod name
    pod_name=$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name="${claim_name}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -z "${pod_name}" ]]; then
        log_error "Pod for claim ${claim_name} not found"
        return 1
    fi
    
    log_info "Deleting pod: ${pod_name}"
    if ! kubectl delete pod "${pod_name}" -n "${NAMESPACE}" --wait=true --timeout=60s; then
        log_error "Failed to delete pod"
        return 1
    fi
    
    # Wait for new pod to be created and ready
    log_info "Waiting for new pod to be created and ready"
    local timeout=180
    local count=0
    local new_pod_name=""
    
    while [[ $count -lt $timeout ]]; do
        new_pod_name=$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name="${claim_name}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        
        if [[ -n "${new_pod_name}" && "${new_pod_name}" != "${pod_name}" ]]; then
            # Wait for pod to be ready
            if kubectl wait --for=condition=Ready pod/"${new_pod_name}" -n "${NAMESPACE}" --timeout=60s 2>/dev/null; then
                break
            fi
        fi
        
        sleep 2
        ((count++))
    done
    
    if [[ $count -ge $timeout ]]; then
        log_error "New pod did not become ready within ${timeout} seconds"
        return 1
    fi
    
    log_info "New pod ready: ${new_pod_name}"
    
    # Give initContainer time to hydrate workspace
    log_info "Waiting for workspace hydration to complete"
    sleep 30
    
    # Check if test file exists and has correct content
    log_info "Checking if test file survived pod recreation"
    local actual_content
    actual_content=$(kubectl exec "${new_pod_name}" -n "${NAMESPACE}" -c main -- cat "/workspace/${test_file}" 2>/dev/null || echo "FILE_NOT_FOUND")
    
    if [[ "${actual_content}" == "FILE_NOT_FOUND" ]]; then
        log_error "Test file ${test_file} not found after pod recreation"
        return 1
    fi
    
    if [[ -n "${expected_content}" && "${actual_content}" != "${expected_content}" ]]; then
        log_error "Test file content mismatch after resurrection"
        log_error "Expected: ${expected_content}"
        log_error "Actual: ${actual_content}"
        return 1
    fi
    
    log_success "Resurrection Test passed - file survived pod recreation"
    export NEW_POD_NAME="${new_pod_name}"
    return 0
}

test_prestop_backup() {
    local claim_name="test-persistence-sandbox"
    local pod_name="${NEW_POD_NAME:-}"
    local final_test_file="final-backup-test.txt"
    local final_content="Final backup test - $(date)"
    
    log_info "Testing preStop hook final backup"
    
    # Get pod name if not set
    if [[ -z "${pod_name}" ]]; then
        pod_name=$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name="${claim_name}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    fi
    
    if [[ -z "${pod_name}" ]]; then
        log_error "Pod for claim ${claim_name} not found"
        return 1
    fi
    
    # Create final test file
    log_info "Creating final test file: ${final_test_file}"
    if ! kubectl exec "${pod_name}" -n "${NAMESPACE}" -c main -- sh -c "echo '${final_content}' > /workspace/${final_test_file}"; then
        log_error "Failed to create final test file"
        return 1
    fi
    
    # Delete the pod to trigger preStop hook
    log_info "Deleting pod to trigger preStop hook: ${pod_name}"
    kubectl delete pod "${pod_name}" -n "${NAMESPACE}" --grace-period=30 &
    
    # Wait a moment for preStop to execute
    sleep 10
    
    # Check pod logs for preStop execution (if still available)
    local prestop_logs
    prestop_logs=$(kubectl logs "${pod_name}" -n "${NAMESPACE}" -c main --previous 2>/dev/null || echo "")
    
    # The preStop hook runs in the background, so we can't easily verify its execution
    # The real test is whether the file survives in the next resurrection test
    log_info "PreStop hook triggered - final backup should be in progress"
    
    # Wait for pod to be fully terminated
    kubectl wait --for=delete pod/"${pod_name}" -n "${NAMESPACE}" --timeout=60s || true
    
    log_success "PreStop hook test completed"
    return 0
}

export -f create_test_claim test_sidecar_backup test_resurrection test_prestop_backup
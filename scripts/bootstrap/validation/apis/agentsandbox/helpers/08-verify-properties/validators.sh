#!/bin/bash
# validators.sh - Property validation functions for AgentSandboxService

# Wait for claim to be ready
wait_for_claim_ready() {
  local claim_name="$1"
  local namespace="$2"
  local timeout="${3:-120}"
  
  local elapsed=0
  
  while [[ $elapsed -lt $timeout ]]; do
    local ready_status
    ready_status=$(kubectl get agentsandboxservice "$claim_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    
    if [[ "$ready_status" == "True" ]]; then
      return 0
    fi
    
    # Check for error conditions
    local synced_status
    synced_status=$(kubectl get agentsandboxservice "$claim_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Synced")].status}' 2>/dev/null || echo "")
    
    if [[ "$synced_status" == "False" ]]; then
      log_error "Claim failed to sync: $claim_name"
      return 1
    fi
    
    sleep 2
    elapsed=$((elapsed + 2))
  done
  
  return 1
}

# Wait for resource to be created
wait_for_resource_creation() {
  local resource_type="$1"
  local resource_name="$2"
  local namespace="$3"
  local timeout="${4:-60}"
  
  local elapsed=0
  
  while [[ $elapsed -lt $timeout ]]; do
    if kubectl get "$resource_type" "$resource_name" -n "$namespace" >/dev/null 2>&1; then
      return 0
    fi
    
    sleep 2
    elapsed=$((elapsed + 2))
  done
  
  return 1
}

# Wait for sandbox pod to be running
wait_for_sandbox_pod_running() {
  local claim_name="$1"
  local namespace="$2"
  local timeout="${3:-180}"
  
  local elapsed=0
  
  while [[ $elapsed -lt $timeout ]]; do
    local pod_name
    pod_name=$(kubectl get pods -n "$namespace" -l "app.kubernetes.io/name=$claim_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$pod_name" ]]; then
      local pod_status
      pod_status=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
      
      if [[ "$pod_status" == "Running" ]]; then
        return 0
      fi
    fi
    
    sleep 3
    elapsed=$((elapsed + 3))
  done
  
  return 1
}

# Test file persistence across pod recreation
test_file_persistence() {
  local claim_name="$1"
  local namespace="$2"
  
  # Get the running pod
  local pod_name
  pod_name=$(kubectl get pods -n "$namespace" -l "app.kubernetes.io/name=$claim_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  
  if [[ -z "$pod_name" ]]; then
    log_error "No running pod found for persistence test"
    return 1
  fi
  
  # Generate test file content
  local test_file_name
  test_file_name=$(generate_random_file_name)
  local test_content
  test_content=$(generate_random_file_content)
  
  # Write test file to workspace
  if ! kubectl exec "$pod_name" -n "$namespace" -c main -- sh -c "echo '$test_content' > /workspace/$test_file_name"; then
    log_error "Failed to write test file to workspace"
    return 1
  fi
  
  # Delete the pod to trigger recreation
  if ! kubectl delete pod "$pod_name" -n "$namespace"; then
    log_error "Failed to delete pod for recreation test"
    return 1
  fi
  
  # Wait for new pod to be running
  if ! wait_for_sandbox_pod_running "$claim_name" "$namespace" 120; then
    log_error "New pod not running after recreation"
    return 1
  fi
  
  # Get the new pod name
  local new_pod_name
  new_pod_name=$(kubectl get pods -n "$namespace" -l "app.kubernetes.io/name=$claim_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  
  if [[ -z "$new_pod_name" ]]; then
    log_error "No new pod found after recreation"
    return 1
  fi
  
  # Verify file content persisted
  local retrieved_content
  retrieved_content=$(kubectl exec "$new_pod_name" -n "$namespace" -c main -- cat "/workspace/$test_file_name" 2>/dev/null || echo "")
  
  if [[ "$retrieved_content" != "$test_content" ]]; then
    log_error "File content did not persist across pod recreation"
    log_error "Expected: $test_content"
    log_error "Got: $retrieved_content"
    return 1
  fi
  
  return 0
}

# Validate ScaledObject configuration
validate_scaledobject_config() {
  local claim_name="$1"
  local namespace="$2"
  
  # Check ScaledObject exists
  if ! kubectl get scaledobject "$claim_name" -n "$namespace" >/dev/null 2>&1; then
    log_error "ScaledObject not found: $claim_name"
    return 1
  fi
  
  # Validate target reference
  local target_api_version
  target_api_version=$(kubectl get scaledobject "$claim_name" -n "$namespace" -o jsonpath='{.spec.scaleTargetRef.apiVersion}')
  
  if [[ "$target_api_version" != "extensions.agents.x-k8s.io/v1alpha1" ]]; then
    log_error "Wrong ScaledObject target apiVersion: $target_api_version"
    return 1
  fi
  
  local target_kind
  target_kind=$(kubectl get scaledobject "$claim_name" -n "$namespace" -o jsonpath='{.spec.scaleTargetRef.kind}')
  
  if [[ "$target_kind" != "SandboxWarmPool" ]]; then
    log_error "Wrong ScaledObject target kind: $target_kind"
    return 1
  fi
  
  # Validate NATS trigger exists
  local triggers
  triggers=$(kubectl get scaledobject "$claim_name" -n "$namespace" -o jsonpath='{.spec.triggers}')
  
  if [[ "$triggers" == "null" || "$triggers" == "[]" ]]; then
    log_error "No triggers found in ScaledObject"
    return 1
  fi
  
  return 0
}

# Validate HTTP Service configuration
validate_http_service_config() {
  local service_name="$1"
  local namespace="$2"
  local claim_spec="$3"
  
  # Extract expected values from claim spec
  local expected_port
  expected_port=$(echo "$claim_spec" | yq '.spec.httpPort')
  local expected_session_affinity
  expected_session_affinity=$(echo "$claim_spec" | yq '.spec.sessionAffinity // "None"')
  
  # Validate service port
  local actual_port
  actual_port=$(kubectl get service "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].port}')
  
  if [[ "$actual_port" != "$expected_port" ]]; then
    log_error "Service port mismatch: expected $expected_port, got $actual_port"
    return 1
  fi
  
  # Validate session affinity
  local actual_session_affinity
  actual_session_affinity=$(kubectl get service "$service_name" -n "$namespace" -o jsonpath='{.spec.sessionAffinity}')
  
  if [[ "$actual_session_affinity" != "$expected_session_affinity" ]]; then
    log_error "Session affinity mismatch: expected $expected_session_affinity, got $actual_session_affinity"
    return 1
  fi
  
  # Validate service type
  local service_type
  service_type=$(kubectl get service "$service_name" -n "$namespace" -o jsonpath='{.spec.type}')
  
  if [[ "$service_type" != "ClusterIP" ]]; then
    log_error "Wrong service type: expected ClusterIP, got $service_type"
    return 1
  fi
  
  return 0
}

# Validate secret injection configuration
validate_secret_injection_config() {
  local claim_name="$1"
  local namespace="$2"
  local iteration="$3"
  
  # Get SandboxTemplate
  local template_yaml
  template_yaml=$(kubectl get sandboxtemplate "$claim_name" -n "$namespace" -o yaml)
  
  # Check envFrom configuration
  local envfrom_count
  envfrom_count=$(echo "$template_yaml" | yq '.spec.podTemplate.spec.containers[0].envFrom | length')
  
  # Should have aws-access-token plus user secrets (minimum 1, maximum 4)
  if [[ "$envfrom_count" -lt 1 || "$envfrom_count" -gt 4 ]]; then
    log_error "Invalid envFrom count: $envfrom_count (expected 1-4)"
    return 1
  fi
  
  # Validate aws-access-token is always present (should be last)
  local last_index=$((envfrom_count - 1))
  local aws_secret
  aws_secret=$(echo "$template_yaml" | yq ".spec.podTemplate.spec.containers[0].envFrom[$last_index].secretRef.name")
  
  if [[ "$aws_secret" != "aws-access-token" ]]; then
    log_error "aws-access-token not found in expected position"
    return 1
  fi
  
  # Validate user secrets are in correct positions
  for i in $(seq 0 $((envfrom_count - 2))); do
    local secret_name
    secret_name=$(echo "$template_yaml" | yq ".spec.podTemplate.spec.containers[0].envFrom[$i].secretRef.name")
    local expected_secret="test-secret-${iteration}-$((i + 1))"
    
    if [[ "$secret_name" != "$expected_secret" ]]; then
      log_error "Secret mismatch at position $i: expected $expected_secret, got $secret_name"
      return 1
    fi
  done
  
  return 0
}

# Create test secrets for iteration
create_test_secrets_for_iteration() {
  local iteration="$1"
  local namespace="$2"
  
  # Create 1-3 test secrets
  local num_secrets=$((RANDOM % 3 + 1))
  
  for i in $(seq 1 $num_secrets); do
    kubectl create secret generic "test-secret-${iteration}-${i}" \
      --from-literal="TEST_VAR_${i}=test-value-${iteration}-${i}" \
      --from-literal="ITERATION=${iteration}" \
      -n "$namespace" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
  done
}

# Cleanup test secrets for iteration
cleanup_test_secrets_for_iteration() {
  local iteration="$1"
  local namespace="$2"
  
  for i in {1..3}; do
    kubectl delete secret "test-secret-${iteration}-${i}" -n "$namespace" --ignore-not-found=true >/dev/null 2>&1
  done
}
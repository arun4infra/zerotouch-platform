#!/bin/bash
# validation.sh - Helper functions for validating AgentSandboxService functionality

# Test file persistence across pod recreation
test_file_persistence() {
  local claim_name="$1"
  local namespace="$2"
  
  # Get a running sandbox pod
  local pod_name
  pod_name=$(kubectl get pods -n "$namespace" -l "app.kubernetes.io/name=$claim_name" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  
  if [[ -z "$pod_name" ]]; then
    return 1
  fi
  
  # Create test file
  local test_content="persistence-test-$(date +%s)"
  local test_file="/workspace/persistence-test.txt"
  
  if ! kubectl exec "$pod_name" -n "$namespace" -c main -- sh -c "echo '$test_content' > $test_file"; then
    return 1
  fi
  
  # Delete pod
  if ! kubectl delete pod "$pod_name" -n "$namespace"; then
    return 1
  fi
  
  # Wait for new pod
  local timeout=180
  local elapsed=0
  local new_pod_name=""
  
  while [[ $elapsed -lt $timeout ]]; do
    new_pod_name=$(kubectl get pods -n "$namespace" -l "app.kubernetes.io/name=$claim_name" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$new_pod_name" && "$new_pod_name" != "$pod_name" ]]; then
      break
    fi
    
    sleep 10
    elapsed=$((elapsed + 10))
  done
  
  if [[ -z "$new_pod_name" || "$new_pod_name" == "$pod_name" ]]; then
    return 1
  fi
  
  # Wait for hydration
  sleep 30
  
  # Check file persistence
  local persisted_content
  persisted_content=$(kubectl exec "$new_pod_name" -n "$namespace" -c main -- cat "$test_file" 2>/dev/null || echo "")
  
  if [[ "$persisted_content" == "$test_content" ]]; then
    return 0
  else
    return 1
  fi
}

# Validate ScaledObject configuration
validate_scaledobject_config() {
  local claim_name="$1"
  local namespace="$2"
  
  # Check if ScaledObject exists (with -scaler suffix)
  if ! kubectl get scaledobject "${claim_name}-scaler" -n "$namespace" >/dev/null 2>&1; then
    return 1
  fi
  
  # Check if it targets SandboxWarmPool
  local target_ref
  target_ref=$(kubectl get scaledobject "${claim_name}-scaler" -n "$namespace" -o jsonpath='{.spec.scaleTargetRef.name}' 2>/dev/null)
  
  if [[ "$target_ref" != "$claim_name" ]]; then
    return 1
  fi
  
  # Check API version
  local api_version
  api_version=$(kubectl get scaledobject "${claim_name}-scaler" -n "$namespace" -o jsonpath='{.spec.scaleTargetRef.apiVersion}' 2>/dev/null)
  
  if [[ "$api_version" != "extensions.agents.x-k8s.io/v1alpha1" ]]; then
    return 1
  fi
  
  return 0
}

# Validate HTTP service configuration
validate_http_service_config() {
  local service_name="$1"
  local namespace="$2"
  local claim_spec="$3"
  
  # Check if service exists
  if ! kubectl get service "$service_name" -n "$namespace" >/dev/null 2>&1; then
    return 1
  fi
  
  # Get expected port from claim spec
  local expected_port
  expected_port=$(echo "$claim_spec" | yq '.spec.httpPort' 2>/dev/null || echo "8000")
  
  # Get actual port from service
  local actual_port
  actual_port=$(kubectl get service "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
  
  if [[ "$actual_port" != "$expected_port" ]]; then
    return 1
  fi
  
  return 0
}
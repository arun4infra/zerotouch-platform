#!/bin/bash
# prerequisites.sh - Helper functions for validating e2e test prerequisites

# Check if NATS stream exists
check_nats_stream_exists() {
  local stream_name="$1"
  
  # Try to find NATS box pods (these have the nats CLI)
  local nats_pods
  nats_pods=$(kubectl get pods -A -l app.kubernetes.io/component=nats-box --no-headers 2>/dev/null | head -1)
  
  if [[ -z "$nats_pods" ]]; then
    log_error "NATS box pods not found - NATS system is required for AgentSandboxService"
    return 1
  fi
  
  # Extract namespace and pod name
  local nats_namespace nats_pod
  nats_namespace=$(echo "$nats_pods" | awk '{print $1}')
  nats_pod=$(echo "$nats_pods" | awk '{print $2}')
  
  # Check if nats CLI is available in the pod
  if kubectl exec "$nats_pod" -n "$nats_namespace" -- which nats >/dev/null 2>&1; then
    # Try to get stream info
    if kubectl exec "$nats_pod" -n "$nats_namespace" -- nats stream info "$stream_name" >/dev/null 2>&1; then
      return 0
    else
      log_error "NATS stream $stream_name not found - stream must exist for scaling tests"
      return 1
    fi
  else
    log_error "NATS CLI not available in NATS box pod - cannot validate stream"
    return 1
  fi
}

# Wait for resource creation with timeout
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
    
    sleep 5
    elapsed=$((elapsed + 5))
  done
  
  return 1
}
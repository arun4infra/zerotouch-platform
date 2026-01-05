#!/bin/bash
# deployment.sh - Helper functions for AgentSandboxService deployment

# Wait for claim to be ready
wait_for_claim_ready() {
  local claim_name="$1"
  local namespace="$2"
  local timeout="${3:-300}"
  
  local elapsed=0
  
  while [[ $elapsed -lt $timeout ]]; do
    local ready_condition
    ready_condition=$(kubectl get agentsandboxservice "$claim_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    
    if [[ "$ready_condition" == "True" ]]; then
      return 0
    fi
    
    sleep 10
    elapsed=$((elapsed + 10))
  done
  
  return 1
}

# Wait for sandbox pod to be running
wait_for_sandbox_pod_running() {
  local claim_name="$1"
  local namespace="$2"
  local timeout="${3:-300}"
  
  local elapsed=0
  
  while [[ $elapsed -lt $timeout ]]; do
    local running_pods
    running_pods=$(kubectl get pods -n "$namespace" -l "app.kubernetes.io/name=$claim_name" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $running_pods -gt 0 ]]; then
      return 0
    fi
    
    sleep 10
    elapsed=$((elapsed + 10))
  done
  
  return 1
}
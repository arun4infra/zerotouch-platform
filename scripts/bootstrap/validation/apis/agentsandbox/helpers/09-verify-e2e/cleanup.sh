#!/bin/bash
# cleanup.sh - Helper functions for cleaning up e2e test resources

# Clean up AgentSandboxService claim and related resources
cleanup_agentsandbox_claim() {
  local claim_name="$1"
  local namespace="$2"
  
  log_info "Cleaning up AgentSandboxService claim: $claim_name"
  
  # Delete the claim (this should cascade to managed resources)
  kubectl delete agentsandboxservice "$claim_name" -n "$namespace" --ignore-not-found=true
  
  # Wait for resources to be cleaned up
  local timeout=120
  local elapsed=0
  
  while [[ $elapsed -lt $timeout ]]; do
    local remaining_resources=0
    
    # Check for remaining managed resources
    if kubectl get sandboxtemplate "$claim_name" -n "$namespace" >/dev/null 2>&1; then
      ((remaining_resources++))
    fi
    
    if kubectl get sandboxwarmpool "$claim_name" -n "$namespace" >/dev/null 2>&1; then
      ((remaining_resources++))
    fi
    
    if kubectl get scaledobject "$claim_name" -n "$namespace" >/dev/null 2>&1; then
      ((remaining_resources++))
    fi
    
    if kubectl get service "${claim_name}-http" -n "$namespace" >/dev/null 2>&1; then
      ((remaining_resources++))
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
      log_info "All managed resources cleaned up successfully"
      return 0
    fi
    
    sleep 5
    elapsed=$((elapsed + 5))
  done
  
  log_warning "Some managed resources may still be cleaning up"
  return 0
}

# Clean up test pods and temporary resources
cleanup_test_pods() {
  local namespace="$1"
  
  # Clean up any test pods that might be left over
  kubectl delete pods -n "$namespace" -l "test-type=e2e" --ignore-not-found=true
  
  # Clean up temporary files
  rm -f /tmp/http_test_result 2>/dev/null || true
}
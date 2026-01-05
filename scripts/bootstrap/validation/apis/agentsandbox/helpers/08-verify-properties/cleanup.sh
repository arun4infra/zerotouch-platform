#!/bin/bash
# cleanup.sh - Cleanup functions for property-based testing

# Cleanup all property test resources
cleanup_property_test_resources() {
  local test_prefix="$1"
  local namespace="$2"
  
  log_info "Cleaning up property test resources with prefix: $test_prefix"
  
  # Delete all AgentSandboxService claims with the test prefix
  local claims
  claims=$(kubectl get agentsandboxservice -n "$namespace" -o name | grep "$test_prefix" || true)
  
  if [[ -n "$claims" ]]; then
    echo "$claims" | xargs -r kubectl delete -n "$namespace" --ignore-not-found=true
  fi
  
  # Delete test secrets (pattern: test-secret-*-*)
  local secrets
  secrets=$(kubectl get secrets -n "$namespace" -o name | grep "test-secret-" || true)
  
  if [[ -n "$secrets" ]]; then
    echo "$secrets" | xargs -r kubectl delete -n "$namespace" --ignore-not-found=true
  fi
  
  # Wait for resources to be cleaned up
  local timeout=60
  local elapsed=0
  
  while [[ $elapsed -lt $timeout ]]; do
    local remaining_claims=0
    if kubectl get agentsandboxservice -n "$namespace" -o name 2>/dev/null | grep -q "$test_prefix"; then
      remaining_claims=$(kubectl get agentsandboxservice -n "$namespace" -o name 2>/dev/null | grep "$test_prefix" | wc -l | tr -d ' \t\n\r' || echo "0")
      # Ensure it's a valid number
      if ! [[ "$remaining_claims" =~ ^[0-9]+$ ]]; then
        remaining_claims=0
      fi
    fi
    
    if [[ "$remaining_claims" -eq 0 ]]; then
      break
    fi
    
    sleep 2
    elapsed=$((elapsed + 2))
  done
  
  log_info "Property test resource cleanup completed"
}

# Force cleanup of stuck resources
force_cleanup_stuck_resources() {
  local test_prefix="$1"
  local namespace="$2"
  
  log_warning "Force cleaning up stuck resources with prefix: $test_prefix"
  
  # Remove finalizers from stuck AgentSandboxService claims
  local stuck_claims
  stuck_claims=$(kubectl get agentsandboxservice -n "$namespace" -o name | grep "$test_prefix" || true)
  
  if [[ -n "$stuck_claims" ]]; then
    for claim in $stuck_claims; do
      kubectl patch "$claim" -n "$namespace" -p '{"metadata":{"finalizers":[]}}' --type=merge --ignore-not-found=true
    done
  fi
  
  # Remove finalizers from related resources
  local resource_types=("sandboxtemplate" "sandboxwarmpool" "scaledobject" "service" "serviceaccount")
  
  for resource_type in "${resource_types[@]}"; do
    local resources
    resources=$(kubectl get "$resource_type" -n "$namespace" -o name | grep "$test_prefix" || true)
    
    if [[ -n "$resources" ]]; then
      for resource in $resources; do
        kubectl patch "$resource" -n "$namespace" -p '{"metadata":{"finalizers":[]}}' --type=merge --ignore-not-found=true
        kubectl delete "$resource" -n "$namespace" --ignore-not-found=true
      done
    fi
  done
  
  log_info "Force cleanup completed"
}

# Cleanup resources by age (older than specified minutes)
cleanup_old_test_resources() {
  local namespace="$1"
  local age_minutes="${2:-30}"
  
  log_info "Cleaning up test resources older than $age_minutes minutes"
  
  # Calculate cutoff time
  local cutoff_time
  cutoff_time=$(date -d "$age_minutes minutes ago" -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Find and delete old AgentSandboxService claims
  local old_claims
  old_claims=$(kubectl get agentsandboxservice -n "$namespace" -o json | \
    jq -r ".items[] | select(.metadata.creationTimestamp < \"$cutoff_time\" and (.metadata.name | test(\"pbt-test-|test-\"))) | .metadata.name" || true)
  
  if [[ -n "$old_claims" ]]; then
    for claim in $old_claims; do
      log_info "Deleting old test claim: $claim"
      kubectl delete agentsandboxservice "$claim" -n "$namespace" --ignore-not-found=true
    done
  fi
  
  # Find and delete old test secrets
  local old_secrets
  old_secrets=$(kubectl get secrets -n "$namespace" -o json | \
    jq -r ".items[] | select(.metadata.creationTimestamp < \"$cutoff_time\" and (.metadata.name | test(\"test-secret-\"))) | .metadata.name" || true)
  
  if [[ -n "$old_secrets" ]]; then
    for secret in $old_secrets; do
      log_info "Deleting old test secret: $secret"
      kubectl delete secret "$secret" -n "$namespace" --ignore-not-found=true
    done
  fi
  
  log_info "Old test resource cleanup completed"
}

# Emergency cleanup - removes all test resources regardless of state
emergency_cleanup() {
  local namespace="$1"
  
  log_warning "EMERGENCY CLEANUP: Removing all test resources in namespace $namespace"
  
  # Delete all resources with test patterns
  local test_patterns=("pbt-test-" "test-api-" "test-res-" "test-persist-" "test-keda-" "test-http-" "test-secret-")
  
  for pattern in "${test_patterns[@]}"; do
    # AgentSandboxService claims
    kubectl get agentsandboxservice -n "$namespace" -o name | grep "$pattern" | xargs -r kubectl delete -n "$namespace" --ignore-not-found=true --force --grace-period=0
    
    # Related resources
    for resource_type in "sandboxtemplate" "sandboxwarmpool" "scaledobject" "service" "serviceaccount"; do
      kubectl get "$resource_type" -n "$namespace" -o name | grep "$pattern" | xargs -r kubectl delete -n "$namespace" --ignore-not-found=true --force --grace-period=0
    done
  done
  
  # Delete test secrets
  kubectl get secrets -n "$namespace" -o name | grep "test-secret-" | xargs -r kubectl delete -n "$namespace" --ignore-not-found=true --force --grace-period=0
  
  log_warning "Emergency cleanup completed"
}
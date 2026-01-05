#!/bin/bash
# load-testing.sh - Helper functions for load testing AgentSandboxService

# Monitor scaling metrics
monitor_scaling_metrics() {
  local claim_name="$1"
  local namespace="$2"
  local duration="${3:-60}"
  
  local end_time=$(($(date +%s) + duration))
  local initial_replicas
  initial_replicas=$(kubectl get sandboxwarmpool "$claim_name" -n "$namespace" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
  
  log_info "Monitoring scaling for $duration seconds (initial replicas: $initial_replicas)"
  
  while [[ $(date +%s) -lt $end_time ]]; do
    local current_replicas
    current_replicas=$(kubectl get sandboxwarmpool "$claim_name" -n "$namespace" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [[ "$current_replicas" != "$initial_replicas" ]]; then
      log_info "Scaling event detected: $initial_replicas -> $current_replicas"
      return 0
    fi
    
    # Log current status
    local scaledobject_status
    scaledobject_status=$(kubectl get scaledobject "$claim_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    
    if [[ "$VERBOSE" == "true" ]]; then
      log_info "Current replicas: $current_replicas, ScaledObject ready: $scaledobject_status"
    fi
    
    sleep 10
  done
  
  log_info "No scaling events observed during monitoring period"
  return 1
}

# Simulate load by creating NATS messages (if possible)
simulate_nats_load() {
  local stream_name="$1"
  local duration="${2:-30}"
  
  # Try to find NATS box pods (these have the nats CLI)
  local nats_pods
  nats_pods=$(kubectl get pods -A -l app.kubernetes.io/component=nats-box --no-headers 2>/dev/null | head -1)
  
  if [[ -z "$nats_pods" ]]; then
    log_error "NATS box pods not found - cannot simulate load for scaling test"
    return 1
  fi
  
  # Extract namespace and pod name
  local nats_namespace nats_pod
  nats_namespace=$(echo "$nats_pods" | awk '{print $1}')
  nats_pod=$(echo "$nats_pods" | awk '{print $2}')
  
  # Check if nats CLI is available
  if ! kubectl exec "$nats_pod" -n "$nats_namespace" -- which nats >/dev/null 2>&1; then
    log_error "NATS CLI not available - cannot simulate load"
    return 1
  fi
  
  log_info "Simulating NATS load for $duration seconds..."
  
  # Publish messages to create load
  local end_time=$(($(date +%s) + duration))
  local message_count=0
  
  while [[ $(date +%s) -lt $end_time ]]; do
    if kubectl exec "$nats_pod" -n "$nats_namespace" -- nats pub "$stream_name" "test-message-$message_count" >/dev/null 2>&1; then
      ((message_count++))
    fi
    sleep 1
  done
  
  log_info "Published $message_count messages to stream $stream_name"
  return 0
}
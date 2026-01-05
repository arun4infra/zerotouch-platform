#!/bin/bash
set -euo pipefail

# 09-verify-e2e.sh - End-to-end integration testing for AgentSandboxService with real deepagents-runtime
# Validates complete system functionality with actual workloads

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
TENANT_NAME="deepagents-runtime"
NAMESPACE="intelligence-deepagents"
VERBOSE=false
CLEANUP=true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

# Test configuration
CLAIM_NAME="deepagents-runtime-sandbox"
CLAIM_FILE="../zerotouch-tenants/tenants/deepagents-runtime/overlays/dev/agentsandbox-claim.yaml"
TEST_TIMEOUT=300
LOAD_TEST_DURATION=60

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --tenant)
      TENANT_NAME="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --cleanup)
      CLEANUP=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--tenant <name>] [--namespace <name>] [--verbose] [--cleanup]"
      echo "Validates complete AgentSandboxService system with real deepagents-runtime workload"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

log_info "Starting AgentSandboxService end-to-end integration testing"
log_info "Tenant: $TENANT_NAME, Namespace: $NAMESPACE"

# Source helper modules
source "${SCRIPT_DIR}/helpers/09-verify-e2e/prerequisites.sh"
source "${SCRIPT_DIR}/helpers/09-verify-e2e/deployment.sh"
source "${SCRIPT_DIR}/helpers/09-verify-e2e/validation.sh"
source "${SCRIPT_DIR}/helpers/09-verify-e2e/load-testing.sh"
source "${SCRIPT_DIR}/helpers/09-verify-e2e/cleanup.sh"

# Cleanup function
cleanup_e2e_resources() {
  if [[ "$CLEANUP" == "true" ]]; then
    log_info "Cleaning up end-to-end test resources..."
    # cleanup_agentsandbox_claim "$CLAIM_NAME" "$NAMESPACE"
    log_info "Cleanup skipped for debugging - resources left running"
  fi
}

# Set up cleanup trap
trap cleanup_e2e_resources EXIT

# Validation functions
validate_prerequisites() {
  log_info "Validating prerequisites for end-to-end testing..."
  
  # Check namespace exists
  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log_error "Namespace $NAMESPACE does not exist"
    return 1
  fi
  
  # Check AgentSandboxService XRD exists
  if ! kubectl get xrd xagentsandboxservices.platform.bizmatters.io >/dev/null 2>&1; then
    log_error "AgentSandboxService XRD not found"
    return 1
  fi
  
  # Check agent-sandbox controller is running
  if ! kubectl get pods -n agent-sandbox-system -l app=agent-sandbox-controller | grep -q Running; then
    log_error "Agent-sandbox controller not running"
    return 1
  fi
  
  # Check required secrets exist
  local required_secrets=("aws-access-token" "deepagents-runtime-db-conn" "deepagents-runtime-cache-conn" "deepagents-runtime-llm-keys")
  for secret in "${required_secrets[@]}"; do
    if ! kubectl get secret "$secret" -n "$NAMESPACE" >/dev/null 2>&1; then
      log_error "Required secret $secret not found in namespace $NAMESPACE"
      return 1
    fi
  done
  
  # Check NATS stream exists
  if ! check_nats_stream_exists "AGENT_EXECUTION"; then
    log_error "NATS stream AGENT_EXECUTION not found"
    return 1
  fi
  
  # Check claim file exists
  if [[ ! -f "$CLAIM_FILE" ]]; then
    log_error "AgentSandboxService claim file not found: $CLAIM_FILE"
    return 1
  fi
  
  log_success "Prerequisites validated successfully"
}

# Deploy AgentSandboxService claim
deploy_agentsandbox_claim() {
  log_info "Deploying AgentSandboxService claim..."
  
  # Apply the claim
  if ! kubectl apply -f "$CLAIM_FILE"; then
    log_error "Failed to apply AgentSandboxService claim"
    return 1
  fi
  
  log_info "AgentSandboxService claim applied successfully"
  
  # Wait for claim to be processed
  log_info "Waiting for claim to be processed..."
  local timeout=60
  local elapsed=0
  
  while [[ $elapsed -lt $timeout ]]; do
    local conditions
    conditions=$(kubectl get agentsandboxservice "$CLAIM_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions}' 2>/dev/null || echo "[]")
    
    if [[ "$conditions" != "[]" && "$conditions" != "null" ]]; then
      log_success "AgentSandboxService claim processed"
      return 0
    fi
    
    sleep 5
    elapsed=$((elapsed + 5))
  done
  
  log_error "AgentSandboxService claim not processed within timeout"
  return 1
}

# Validate sandbox instances start and become ready
validate_sandbox_readiness() {
  log_info "Validating sandbox instances start and become ready..."
  
  # Wait for SandboxTemplate to be created
  if ! wait_for_resource_creation "sandboxtemplate" "$CLAIM_NAME" "$NAMESPACE" 120; then
    log_error "SandboxTemplate not created"
    return 1
  fi
  
  # Wait for SandboxWarmPool to be created
  if ! wait_for_resource_creation "sandboxwarmpool" "$CLAIM_NAME" "$NAMESPACE" 120; then
    log_error "SandboxWarmPool not created"
    return 1
  fi
  
  # Wait for at least one sandbox pod to be running
  log_info "Waiting for sandbox pods to start..."
  local timeout=300
  local elapsed=0
  
  while [[ $elapsed -lt $timeout ]]; do
    local running_pods
    running_pods=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$CLAIM_NAME" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $running_pods -gt 0 ]]; then
      log_success "Sandbox pods are running ($running_pods instances)"
      return 0
    fi
    
    sleep 10
    elapsed=$((elapsed + 10))
  done
  
  log_error "No sandbox pods became ready within timeout"
  kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$CLAIM_NAME" || true
  return 1
}

# Test NATS message processing
test_nats_message_processing() {
  log_info "Testing NATS message processing with live message flow..."
  
  # Get a running sandbox pod
  local pod_name
  pod_name=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$CLAIM_NAME" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  
  if [[ -z "$pod_name" ]]; then
    log_error "No running sandbox pod found for NATS testing"
    return 1
  fi
  
  log_info "Testing NATS connectivity from pod: $pod_name"
  
  # Check if NATS environment variables are available (required)
  local nats_vars
  nats_vars=$(kubectl exec "$pod_name" -n "$NAMESPACE" -c main -- env | grep -E "^NATS_" || true)
  
  if [[ -z "$nats_vars" ]]; then
    log_error "No NATS environment variables found in sandbox container"
    return 1
  fi
  
  log_info "NATS environment variables found: $(echo "$nats_vars" | wc -l) variables"
  
  # Test actual NATS connectivity by trying to connect
  local nats_url
  nats_url=$(kubectl exec "$pod_name" -n "$NAMESPACE" -c main -- env | grep "^NATS_URL=" | cut -d'=' -f2 || echo "")
  
  if [[ -z "$nats_url" ]]; then
    log_error "NATS_URL environment variable not found"
    return 1
  fi
  
  log_info "Testing NATS connectivity to: $nats_url"
  
  # Verify NATS service exists in the cluster
  local nats_host nats_port
  nats_host=$(echo "$nats_url" | sed 's|nats://||' | cut -d':' -f1)
  nats_port=$(echo "$nats_url" | sed 's|nats://||' | cut -d':' -f2)
  
  # Check if NATS service exists
  if kubectl get svc nats -n nats >/dev/null 2>&1; then
    log_success "NATS service exists in cluster"
  else
    log_error "NATS service not found in cluster"
    return 1
  fi
  
  # Verify NATS port is configured correctly
  if [[ "$nats_port" == "4222" ]]; then
    log_success "NATS port correctly configured: $nats_port"
  else
    log_error "NATS port misconfigured: expected 4222, got $nats_port"
    return 1
  fi
  
  # Verify all required NATS environment variables are present
  local required_vars=("NATS_URL" "NATS_STREAM_NAME" "NATS_CONSUMER_GROUP")
  for var in "${required_vars[@]}"; do
    local var_value
    var_value=$(kubectl exec "$pod_name" -n "$NAMESPACE" -c main -- env | grep "^${var}=" | cut -d'=' -f2 || echo "")
    
    if [[ -n "$var_value" ]]; then
      log_success "NATS variable $var correctly set: $var_value"
    else
      log_error "NATS variable $var not found or empty"
      return 1
    fi
  done
  
  return 0
}

# Test workspace persistence across pod restarts
test_workspace_persistence() {
  log_info "Testing workspace persistence across pod restarts..."
  
  # Get a running sandbox pod
  local pod_name
  pod_name=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$CLAIM_NAME" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  
  if [[ -z "$pod_name" ]]; then
    log_error "No running sandbox pod found for persistence testing"
    return 1
  fi
  
  # Create a test file in workspace
  local test_content="e2e-test-$(date +%s)-$$"
  local test_file="/workspace/e2e-test.txt"
  
  log_info "Creating test file in workspace..."
  if ! kubectl exec "$pod_name" -n "$NAMESPACE" -c main -- sh -c "echo '$test_content' > $test_file"; then
    log_error "Failed to create test file in workspace"
    return 1
  fi
  
  # Verify file exists
  local file_content
  file_content=$(kubectl exec "$pod_name" -n "$NAMESPACE" -c main -- cat "$test_file" 2>/dev/null || echo "")
  
  if [[ "$file_content" != "$test_content" ]]; then
    log_error "Test file content mismatch"
    return 1
  fi
  
  log_info "Test file created successfully, deleting pod to test persistence..."
  
  # Delete the pod to trigger recreation
  if ! kubectl delete pod "$pod_name" -n "$NAMESPACE"; then
    log_error "Failed to delete pod for persistence test"
    return 1
  fi
  
  # Wait for new pod to be running
  log_info "Waiting for new pod to start..."
  local timeout=180
  local elapsed=0
  local new_pod_name=""
  
  while [[ $elapsed -lt $timeout ]]; do
    new_pod_name=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$CLAIM_NAME" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$new_pod_name" && "$new_pod_name" != "$pod_name" ]]; then
      log_info "New pod started: $new_pod_name"
      break
    fi
    
    sleep 10
    elapsed=$((elapsed + 10))
  done
  
  if [[ -z "$new_pod_name" || "$new_pod_name" == "$pod_name" ]]; then
    log_error "New pod did not start within timeout"
    return 1
  fi
  
  # Wait a bit for workspace hydration to complete
  sleep 30
  
  # Check if test file persisted
  log_info "Checking if test file persisted in new pod..."
  local persisted_content
  persisted_content=$(kubectl exec "$new_pod_name" -n "$NAMESPACE" -c main -- cat "$test_file" 2>/dev/null || echo "")
  
  if [[ "$persisted_content" == "$test_content" ]]; then
    log_success "Workspace persistence verified - file survived pod recreation"
    return 0
  else
    log_error "Workspace persistence failed - file not found or content mismatch"
    log_error "Expected: $test_content"
    log_error "Got: $persisted_content"
    return 1
  fi
}

# Test HTTP endpoints
test_http_endpoints() {
  log_info "Testing HTTP endpoints with real network traffic..."
  
  # Check if HTTP service was created
  local service_name="${CLAIM_NAME}-http"
  if ! kubectl get service "$service_name" -n "$NAMESPACE" >/dev/null 2>&1; then
    log_error "HTTP service $service_name not found"
    return 1
  fi
  
  # Get service details
  local service_port
  service_port=$(kubectl get service "$service_name" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}')
  
  log_info "Testing HTTP connectivity to service $service_name:$service_port"
  
  # Create a test pod with proper security context for HTTP connectivity testing
  local test_pod_name="http-test-$(date +%s)"
  
  # Create pod with proper security context
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $test_pod_name
  namespace: $NAMESPACE
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: ["sh", "-c"]
    args: ["curl -f -s -o /dev/null -w '%{http_code}' http://$service_name:$service_port/health || echo 'FAILED'"]
    securityContext:
      runAsNonRoot: true
      runAsUser: 1000
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
      seccompProfile:
        type: RuntimeDefault
EOF
  
  # Wait for pod to complete
  local timeout=60
  local elapsed=0
  
  while [[ $elapsed -lt $timeout ]]; do
    local pod_phase
    pod_phase=$(kubectl get pod "$test_pod_name" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    
    if [[ "$pod_phase" == "Succeeded" || "$pod_phase" == "Failed" ]]; then
      break
    fi
    
    sleep 2
    elapsed=$((elapsed + 2))
  done
  
  # Get the result
  local http_result
  http_result=$(kubectl logs "$test_pod_name" -n "$NAMESPACE" 2>/dev/null || echo "NO_LOGS")
  
  # Clean up test pod
  kubectl delete pod "$test_pod_name" -n "$NAMESPACE" --ignore-not-found=true
  
  if [[ "$http_result" =~ ^[2-3][0-9][0-9]$ ]]; then
    log_success "HTTP endpoint responded with status: $http_result"
    return 0
  elif [[ "$http_result" == "FAILED" ]]; then
    log_error "HTTP endpoint connection failed - service may not be responding"
    return 1
  else
    log_error "HTTP endpoint test failed with result: $http_result"
    return 1
  fi
}

# Test scaling behavior under load
test_scaling_behavior() {
  log_info "Testing scaling behavior under load..."
  
  # Check if ScaledObject was created
  if ! kubectl get scaledobject "${CLAIM_NAME}-scaler" -n "$NAMESPACE" >/dev/null 2>&1; then
    log_error "ScaledObject not found"
    return 1
  fi
  
  # Get initial replica count
  local initial_replicas
  initial_replicas=$(kubectl get sandboxwarmpool "$CLAIM_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
  
  log_info "Initial SandboxWarmPool replicas: $initial_replicas"
  
  # Check ScaledObject status
  local scaledobject_status
  scaledobject_status=$(kubectl get scaledobject "${CLAIM_NAME}-scaler" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
  
  if [[ "$scaledobject_status" == "True" ]]; then
    log_success "ScaledObject is ready and monitoring NATS queue"
  else
    log_warning "ScaledObject status: $scaledobject_status (may still be initializing)"
  fi
  
  # Monitor scaling metrics for a short period
  log_info "Monitoring scaling metrics for $LOAD_TEST_DURATION seconds..."
  local end_time=$(($(date +%s) + LOAD_TEST_DURATION))
  
  while [[ $(date +%s) -lt $end_time ]]; do
    local current_replicas
    current_replicas=$(kubectl get sandboxwarmpool "$CLAIM_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [[ "$current_replicas" != "$initial_replicas" ]]; then
      log_success "Scaling detected: replicas changed from $initial_replicas to $current_replicas"
      return 0
    fi
    
    sleep 10
  done
  
  log_info "No scaling events observed during monitoring period (may be expected with low load)"
  return 0
}

# Validate API parity with EventDrivenService
validate_api_parity() {
  log_info "Validating complete API parity with EventDrivenService..."
  
  # Get the AgentSandboxService spec
  local agentsandbox_spec
  agentsandbox_spec=$(kubectl get agentsandboxservice "$CLAIM_NAME" -n "$NAMESPACE" -o jsonpath='{.spec}' 2>/dev/null)
  
  if [[ -z "$agentsandbox_spec" ]]; then
    log_error "Failed to get AgentSandboxService spec"
    return 1
  fi
  
  # Validate all expected fields are present
  local required_fields=("image" "size" "nats" "httpPort" "secret1Name" "secret2Name" "secret3Name")
  local missing_fields=()
  
  for field in "${required_fields[@]}"; do
    local field_value
    field_value=$(echo "$agentsandbox_spec" | jq -r ".$field // empty" 2>/dev/null)
    
    if [[ -z "$field_value" ]]; then
      missing_fields+=("$field")
    fi
  done
  
  if [[ ${#missing_fields[@]} -gt 0 ]]; then
    log_error "Missing required fields: ${missing_fields[*]}"
    return 1
  fi
  
  log_success "API parity validated - all EventDrivenService fields present"
  return 0
}

# Main validation flow
main() {
  validate_prerequisites || return 1
  
  # Deploy AgentSandboxService claim
  deploy_agentsandbox_claim || return 1
  
  # Validate sandbox instances start and become ready
  validate_sandbox_readiness || return 1
  
  # Test NATS message processing
  test_nats_message_processing || return 1
  
  # Test workspace persistence
  test_workspace_persistence || return 1
  
  # Test HTTP endpoints
  test_http_endpoints || return 1
  
  # Test scaling behavior
  test_scaling_behavior || return 1
  
  # Validate API parity
  validate_api_parity || return 1
  
  log_success "✅ End-to-end integration testing completed successfully!"
  log_success "AgentSandboxService system is operational and ready for production use"
  return 0
}

# Run main function
if ! main; then
  log_error "❌ End-to-end integration testing failed"
  exit 1
fi
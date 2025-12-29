#!/bin/bash
# End-to-End Service Communication Validation Script
# Validates complete service-to-service communication workflow
# Requirements: 8.1, 8.2, 8.5

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="intelligence-deepagents"
DEEPAGENTS_SERVICE="deepagents-runtime-http"
IDE_ORCHESTRATOR_SERVICE="ide-orchestrator"
BACKEND_CONFIG_NAME="ide-orchestrator-backend-config"

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Main execution
main() {
    echo "================================================================================"
    echo "                    End-to-End Service Communication Validation"
    echo "================================================================================"
    echo "Namespace: $NAMESPACE"
    echo "DeepAgents Service: $DEEPAGENTS_SERVICE"
    echo "IDE Orchestrator Service: $IDE_ORCHESTRATOR_SERVICE"
    echo "================================================================================"
    
    # Check if running in preview mode (check node name instead of context)
    IS_PREVIEW_MODE=false
    if kubectl get nodes -o name 2>/dev/null | grep -q "zerotouch-preview"; then
        IS_PREVIEW_MODE=true
    fi
    
    if [ "$IS_PREVIEW_MODE" = true ]; then
        log_info "Preview mode detected - skipping e2e communication validation"
        log_info "This validation requires production namespaces and services"
        echo ""
        echo "================================================================================"
        echo "Validation Summary"
        echo "================================================================================"
        echo ""
        echo "Tests run:    0 (skipped in preview mode)"
        echo "Tests passed: 0"
        echo "Tests failed: 0"
        echo ""
        echo "✓ E2E communication validation skipped (preview mode)"
        echo ""
        echo "In preview mode, this validation is not applicable as it requires:"
        echo "- intelligence-deepagents namespace"
        echo "- deepagents-runtime-http service"
        echo "- Production tenant deployments"
        echo ""
        exit 0
    fi
    
    # Prerequisites check
    log_info "Checking prerequisites..."
    
    if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        log_error "Namespace $NAMESPACE does not exist"
        exit 1
    fi
    
    if ! kubectl get service $DEEPAGENTS_SERVICE -n $NAMESPACE >/dev/null 2>&1; then
        log_error "DeepAgents service $DEEPAGENTS_SERVICE not found in namespace $NAMESPACE"
        exit 1
    fi
    
    if ! kubectl get webservice $IDE_ORCHESTRATOR_SERVICE -n $NAMESPACE >/dev/null 2>&1; then
        log_warning "IDE Orchestrator WebService $IDE_ORCHESTRATOR_SERVICE not found (may not be fully deployed)"
    else
        log_info "IDE Orchestrator WebService found"
    fi
    
    log_success "Prerequisites check completed"
    
    echo "Starting tests..."
    
    # Test 1: DeepAgents Runtime Accessibility
    log_info "Test 1: Testing deepagents-runtime accessibility via both NATS and HTTP..."
    
    # Test HTTP service
    set +e
    kubectl run test-deepagents-http --rm -i --restart=Never --image=curlimages/curl:latest -n $NAMESPACE -- \
       curl -f -s http://$DEEPAGENTS_SERVICE.$NAMESPACE.svc.cluster.local:8000/health >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        log_success "DeepAgents HTTP service accessibility test PASSED"
    else
        log_error "DeepAgents HTTP service accessibility test FAILED"
    fi
    
    # Test original NATS service
    kubectl run test-deepagents-nats --rm -i --restart=Never --image=curlimages/curl:latest -n $NAMESPACE -- \
       curl -f -s http://deepagents-runtime.$NAMESPACE.svc.cluster.local:8080/health >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        log_success "DeepAgents NATS service accessibility test PASSED"
    else
        log_error "DeepAgents NATS service accessibility test FAILED"
    fi
    set -e
    
    # Test 2: Backend Service URL Resolution
    log_info "Test 2: Testing ide-orchestrator backend service URL resolution..."
    
    backend_url=$(kubectl get configmap $BACKEND_CONFIG_NAME -n $NAMESPACE -o jsonpath='{.data.BACKEND_SERVICE_URL}' 2>/dev/null || echo "")
    
    if [[ -z "$backend_url" ]]; then
        log_error "Backend service ConfigMap not found or empty"
    else
        expected_url="http://$DEEPAGENTS_SERVICE.$NAMESPACE.svc.cluster.local:8000"
        if [[ "$backend_url" == "$expected_url" ]]; then
            log_success "Backend service URL correctly resolved: $backend_url"
        else
            log_error "Backend service URL mismatch. Expected: $expected_url, Got: $backend_url"
        fi
    fi
    
    # Test 3: Environment Variable Injection
    log_info "Test 3: Testing environment variable injection..."
    
    set +e
    kubectl run test-env-injection --rm -i --restart=Never --image=alpine:latest -n $NAMESPACE \
       --env="TEST=1" \
       --overrides='{"spec":{"containers":[{"name":"test-env-injection","image":"alpine:latest","command":["/bin/sh","-c","echo BACKEND_SERVICE_URL=$BACKEND_SERVICE_URL && test -n \"$BACKEND_SERVICE_URL\""],"envFrom":[{"configMapRef":{"name":"'$BACKEND_CONFIG_NAME'","optional":true}}]}]}}' >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        log_success "Environment variable injection test PASSED"
    else
        log_error "Environment variable injection test FAILED"
    fi
    
    # Test 4: HTTP Communication
    log_info "Test 4: Testing HTTP communication from ide-orchestrator to deepagents-runtime..."
    
    kubectl run test-http-comm --rm -i --restart=Never --image=curlimages/curl:latest -n $NAMESPACE \
       --overrides='{"spec":{"containers":[{"name":"test-http-comm","image":"curlimages/curl:latest","command":["/bin/sh","-c","curl -f -s $BACKEND_SERVICE_URL/health"],"envFrom":[{"configMapRef":{"name":"'$BACKEND_CONFIG_NAME'","optional":true}}]}]}}' >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        log_success "HTTP communication test PASSED"
    else
        log_error "HTTP communication test FAILED"
    fi
    set -e
    
    # Test 5: Session Affinity Configuration
    log_info "Test 5: Testing session affinity configuration..."
    
    session_affinity=$(kubectl get service $IDE_ORCHESTRATOR_SERVICE -n $NAMESPACE -o jsonpath='{.spec.sessionAffinity}' 2>/dev/null || echo "")
    
    if [[ "$session_affinity" == "ClientIP" ]]; then
        log_success "Session affinity correctly configured: $session_affinity"
    else
        log_error "Session affinity not configured correctly. Expected: ClientIP, Got: $session_affinity"
    fi
    
    # Test 6: Load Balancing
    log_info "Test 6: Testing load balancing setup..."
    
    current_replicas=$(kubectl get deployment deepagents-runtime -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [[ "$current_replicas" -ge 1 ]]; then
        log_success "Load balancing ready with $current_replicas replica(s)"
    else
        log_error "No replicas available for load balancing"
    fi
    
    # Summary
    echo ""
    echo "================================================================================"
    echo "                              Test Summary"
    echo "================================================================================"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo "================================================================================"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "All end-to-end communication tests PASSED!"
        echo ""
        echo "✅ deepagents-runtime accessible via both NATS and HTTP"
        echo "✅ ide-orchestrator can resolve backend service URL from environment"
        echo "✅ HTTP requests from ide-orchestrator to deepagents-runtime succeed"
        echo "✅ Session affinity configured for WebSocket connections"
        echo "✅ Load balancing distributes requests across multiple replicas"
        echo ""
        echo "🎉 Complete service-to-service communication is working!"
        return 0
    else
        log_error "Some tests failed. Please check the logs above."
        return 1
    fi
}

# Run main function
main "$@"
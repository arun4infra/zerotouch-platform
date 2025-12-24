#!/bin/bash
set -euo pipefail

# ==============================================================================
# Test Job Execution Script
# ==============================================================================
# Creates and monitors Kubernetes test jobs
# Used by both local testing and CI workflows
# ==============================================================================

TEST_PATH="${1:-./tests/integration}"
TEST_NAME="${2:-integration-tests}"
TIMEOUT="${3:-600}"
NAMESPACE="${4:-intelligence-deepagents}"
IMAGE_TAG="${5:-ci-test}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $*" >&2; }

main() {
    log_info "Running in-cluster tests..."
    
    # Create and run test job using template
    export JOB_NAME="${TEST_NAME}-$(date +%s)"
    
    # Substitute variables in template
    sed -e "s/{{JOB_NAME}}/$JOB_NAME/g" \
        -e "s/{{NAMESPACE}}/$NAMESPACE/g" \
        -e "s/{{IMAGE}}/ide-orchestrator:$IMAGE_TAG/g" \
        -e "s|{{TEST_PATH}}|$TEST_PATH|g" \
        -e "s/{{TEST_NAME}}/$TEST_NAME/g" \
        scripts/ci/test-job-template.yaml > /tmp/test-job.yaml
    
    # Apply job and wait for completion
    kubectl apply -f /tmp/test-job.yaml
    
    echo "🚀 Starting test job: $JOB_NAME"
    echo "⏳ Waiting for job to complete (timeout: ${TIMEOUT}s)..."
    echo "📊 Namespace: $NAMESPACE"
    echo ""
    
    # Enhanced wait with detailed progress logging
    ELAPSED=0
    POLL_INTERVAL=15
    
    while [ $ELAPSED -lt $TIMEOUT ]; do
        # Check job status
        JOB_STATUS=$(kubectl get job $JOB_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
        JOB_FAILED=$(kubectl get job $JOB_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
        
        if [ "$JOB_STATUS" = "True" ]; then
            echo "✅ Job completed successfully after $((ELAPSED/60))m $((ELAPSED%60))s"
            break
        elif [ "$JOB_FAILED" = "True" ]; then
            echo "❌ Job failed after $((ELAPSED/60))m $((ELAPSED%60))s"
            break
        fi
        
        # Show progress every 30 seconds
        if [ $((ELAPSED % 30)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
            echo "⏳ Still waiting... ($((ELAPSED/60))m $((ELAPSED%60))s elapsed)"
            
            # Get pod status for progress indication
            POD_NAME=$(kubectl get pods -n $NAMESPACE -l job-name=$JOB_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
            if [ -n "$POD_NAME" ]; then
                POD_PHASE=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
                echo "   Pod: $POD_NAME ($POD_PHASE)"
                
                # Show container status
                CONTAINER_READY=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
                CONTAINER_STATE=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].state}' 2>/dev/null | jq -r 'keys[0]' 2>/dev/null || echo "unknown")
                echo "   Container: ready=$CONTAINER_READY, state=$CONTAINER_STATE"
                
                # Show recent logs (last 3 lines) for progress indication
                if [ "$POD_PHASE" = "Running" ]; then
                    echo "   Recent logs:"
                    kubectl logs $POD_NAME -n $NAMESPACE --tail=3 2>/dev/null | sed 's/^/     /' || echo "     (no logs yet)"
                fi
            else
                echo "   No pod found yet"
            fi
            echo ""
        fi
        
        sleep $POLL_INTERVAL
        ELAPSED=$((ELAPSED + POLL_INTERVAL))
    done
    
    # Final status check and diagnostics
    JOB_STATUS=$(kubectl get job $JOB_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
    JOB_FAILED=$(kubectl get job $JOB_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
    
    # Timeout case - comprehensive diagnostics
    if [ $ELAPSED -ge $TIMEOUT ] && [ "$JOB_STATUS" != "True" ]; then
        echo ""
        echo "🚨 TIMEOUT: Job did not complete within $((TIMEOUT/60)) minutes"
        show_diagnostics
        exit 1
    fi
    
    # Wait for job completion with better error handling (fallback)
    if ! kubectl wait --for=condition=complete --timeout=30s job/$JOB_NAME -n $NAMESPACE 2>/dev/null; then
        echo "❌ Job did not complete within final check timeout"
        show_diagnostics
        exit 1
    fi
    
    # Check if job succeeded or failed
    JOB_STATUS=$(kubectl get job $JOB_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "Unknown")
    JOB_FAILED=$(kubectl get job $JOB_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "False")
    
    echo ""
    echo "=== JOB COMPLETION STATUS ==="
    echo "Job completion status: $JOB_STATUS"
    echo "Job failed status: $JOB_FAILED"
    
    # ALWAYS get pod logs for debugging (success or failure)
    show_logs
    
    # Check for job failure
    if [ "$JOB_FAILED" = "True" ]; then
        echo ""
        echo "❌ Test job failed!"
        show_failure_diagnostics
        exit 1
    elif [ "$JOB_STATUS" != "True" ]; then
        echo ""
        echo "❌ Test job did not complete successfully!"
        echo "Job status: Complete=$JOB_STATUS, Failed=$JOB_FAILED"
        show_failure_diagnostics
        exit 1
    fi
    
    echo ""
    echo "✅ Test job completed successfully"
}

show_logs() {
    POD_NAME=$(kubectl get pods -n $NAMESPACE -l job-name=$JOB_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$POD_NAME" ]; then
        echo ""
        echo "=== COMPLETE TEST EXECUTION LOGS ==="
        echo "Pod: $POD_NAME"
        kubectl logs $POD_NAME -n $NAMESPACE || echo "Could not retrieve logs"
        echo "=== END TEST EXECUTION LOGS ==="
    else
        echo "❌ No pod found for job $JOB_NAME - this indicates a serious issue"
        kubectl get pods -n $NAMESPACE -l job-name=$JOB_NAME || echo "Could not list pods"
    fi
}

show_diagnostics() {
    echo ""
    echo "=== JOB DIAGNOSTICS ==="
    kubectl describe job $JOB_NAME -n $NAMESPACE 2>/dev/null || echo "Could not describe job"
    echo ""
    
    # Pod diagnostics
    POD_NAME=$(kubectl get pods -n $NAMESPACE -l job-name=$JOB_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$POD_NAME" ]; then
        echo "=== POD DIAGNOSTICS ==="
        kubectl describe pod $POD_NAME -n $NAMESPACE 2>/dev/null || echo "Could not describe pod"
        echo ""
        
        echo "=== POD EVENTS ==="
        kubectl get events -n $NAMESPACE --field-selector involvedObject.name=$POD_NAME --sort-by='.lastTimestamp' 2>/dev/null || echo "Could not get events"
        echo ""
        
        echo "=== CONTAINER LOGS (LAST 100 LINES) ==="
        kubectl logs $POD_NAME -n $NAMESPACE --tail=100 2>/dev/null || echo "Could not retrieve logs"
    else
        echo "❌ No pod found for job $JOB_NAME"
        echo ""
        echo "=== ALL PODS IN NAMESPACE ==="
        kubectl get pods -n $NAMESPACE 2>/dev/null || echo "Could not list pods"
    fi
    
    echo ""
    echo "=== NAMESPACE EVENTS (RECENT WARNINGS) ==="
    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' --field-selector type=Warning 2>/dev/null | tail -10 || echo "Could not get namespace events"
    
    echo ""
    echo "=== DEBUG COMMANDS ==="
    echo "kubectl describe job $JOB_NAME -n $NAMESPACE"
    echo "kubectl logs -l job-name=$JOB_NAME -n $NAMESPACE"
    echo "kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
}

show_failure_diagnostics() {
    POD_NAME=$(kubectl get pods -n $NAMESPACE -l job-name=$JOB_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$POD_NAME" ]; then
        echo ""
        echo "=== FAILURE DIAGNOSTICS ==="
        kubectl describe job $JOB_NAME -n $NAMESPACE || echo "Could not describe job"
        
        echo ""
        echo "=== POD FAILURE DETAILS ==="
        kubectl describe pod $POD_NAME -n $NAMESPACE || echo "Could not describe pod"
        
        echo ""
        echo "=== RECENT EVENTS ==="
        kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' --field-selector involvedObject.name=$POD_NAME | tail -10 || echo "Could not get events"
    fi
}

main "$@"
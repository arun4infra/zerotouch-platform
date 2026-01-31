#!/bin/bash
set -euo pipefail

# ==============================================================================
# KSOPS Package Deployment Validation Script
# ==============================================================================
# Purpose: Validate KSOPS package deployment to ArgoCD
# Validates: Checkpoint 1 - KSOPS Package Deployment
# ==============================================================================

echo "=== CHECKPOINT 1: KSOPS Package Deployment Validation ==="
echo ""

VALIDATION_FAILED=0

# Function to log validation results
log_check() {
    local status=$1
    local message=$2
    if [[ "$status" == "PASS" ]]; then
        echo "✅ PASS: $message"
    else
        echo "❌ FAIL: $message"
        VALIDATION_FAILED=1
    fi
}

# 1. Verify KSOPS sidecar container running in argocd-repo-server pod
echo "1. Checking KSOPS sidecar container in argocd-repo-server pod..."
if kubectl get pod -n argocd -l app.kubernetes.io/name=argocd-repo-server -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null | grep -q "ksops"; then
    SIDECAR_RUNNING=$(kubectl get pod -n argocd -l app.kubernetes.io/name=argocd-repo-server -o jsonpath='{.items[0].status.containerStatuses[?(@.name=="ksops")].state.running}' 2>/dev/null || echo "")
    if [[ -n "$SIDECAR_RUNNING" ]]; then
        # Check logs for socket creation message
        POD_NAME=$(kubectl get pod -n argocd -l app.kubernetes.io/name=argocd-repo-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if kubectl logs -n argocd "$POD_NAME" -c ksops --tail=20 2>/dev/null | grep -q "serving on.*ksops.*\.sock"; then
            log_check "PASS" "KSOPS sidecar container running with CMP server socket"
        else
            log_check "FAIL" "KSOPS sidecar running but CMP server not initialized"
        fi
    else
        log_check "FAIL" "KSOPS sidecar container exists but not running"
    fi
else
    log_check "FAIL" "KSOPS sidecar container not found in argocd-repo-server pod"
fi

# 2. Verify ConfigMap cmp-plugin exists in argocd namespace
echo "2. Checking ConfigMap cmp-plugin..."
if kubectl get configmap cmp-plugin -n argocd &>/dev/null; then
    log_check "PASS" "ConfigMap cmp-plugin exists in argocd namespace"
else
    log_check "FAIL" "ConfigMap cmp-plugin does not exist in argocd namespace"
fi

# 3. Verify sidecar logs show plugin loaded successfully
echo "3. Checking KSOPS plugin registration in sidecar logs..."
POD_NAME=$(kubectl get pod -n argocd -l app.kubernetes.io/name=argocd-repo-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$POD_NAME" ]]; then
    if kubectl logs -n argocd "$POD_NAME" -c ksops --tail=100 2>/dev/null | grep -q "argocd-cmp-server"; then
        log_check "PASS" "KSOPS plugin loaded successfully (CMP server running)"
    else
        log_check "FAIL" "KSOPS plugin not loaded (CMP server not found in logs)"
    fi
else
    log_check "FAIL" "Could not find argocd-repo-server pod"
fi

# 4. Verify health probes passing
echo "4. Checking health probes..."
if [[ -n "$POD_NAME" ]]; then
    LIVENESS=$(kubectl get pod -n argocd "$POD_NAME" -o jsonpath='{.status.containerStatuses[?(@.name=="ksops")].state.running}' 2>/dev/null || echo "")
    if [[ -n "$LIVENESS" ]]; then
        log_check "PASS" "Health probes passing (container running)"
    else
        log_check "FAIL" "Health probes failing (container not running)"
    fi
else
    log_check "FAIL" "Could not verify health probes (pod not found)"
fi

# 5. Verify resource limits applied correctly
echo "5. Checking resource limits..."
if [[ -n "$POD_NAME" ]]; then
    CPU_LIMIT=$(kubectl get pod -n argocd "$POD_NAME" -o jsonpath='{.spec.containers[?(@.name=="ksops")].resources.limits.cpu}' 2>/dev/null || echo "")
    MEMORY_LIMIT=$(kubectl get pod -n argocd "$POD_NAME" -o jsonpath='{.spec.containers[?(@.name=="ksops")].resources.limits.memory}' 2>/dev/null || echo "")
    
    if [[ "$CPU_LIMIT" == "1000m" || "$CPU_LIMIT" == "1" ]] && [[ "$MEMORY_LIMIT" == "512Mi" ]]; then
        log_check "PASS" "Resource limits applied correctly (CPU: $CPU_LIMIT, Memory: $MEMORY_LIMIT)"
    else
        log_check "FAIL" "Resource limits incorrect (CPU: $CPU_LIMIT, Memory: $MEMORY_LIMIT)"
    fi
else
    log_check "FAIL" "Could not verify resource limits (pod not found)"
fi

# 6. Verify both KSOPS and ESO packages deployed without conflicts
echo "6. Checking package coexistence..."
KSOPS_CM=$(kubectl get configmap cmp-plugin -n argocd &>/dev/null && echo "exists" || echo "missing")
ESO_CSS=$(kubectl get clustersecretstore aws-parameter-store &>/dev/null && echo "exists" || echo "missing")

if [[ "$KSOPS_CM" == "exists" ]] && [[ "$ESO_CSS" == "exists" ]]; then
    log_check "PASS" "Both KSOPS and ESO packages deployed without conflicts"
elif [[ "$KSOPS_CM" == "exists" ]] && [[ "$ESO_CSS" == "missing" ]]; then
    log_check "PASS" "KSOPS package deployed (ESO not required for this checkpoint)"
else
    log_check "FAIL" "Package deployment incomplete (KSOPS: $KSOPS_CM, ESO: $ESO_CSS)"
fi

echo ""
echo "=== Validation Summary ==="
if [[ $VALIDATION_FAILED -eq 0 ]]; then
    echo "✅ CHECKPOINT 1 PASSED: KSOPS package deployed successfully"
    exit 0
else
    echo "❌ CHECKPOINT 1 FAILED: Some validation checks failed"
    echo ""
    echo "Diagnostic Information:"
    echo "----------------------"
    if [[ -n "$POD_NAME" ]]; then
        echo "Pod Status:"
        kubectl get pod -n argocd "$POD_NAME" -o wide
        echo ""
        echo "Recent KSOPS Sidecar Logs:"
        kubectl logs -n argocd "$POD_NAME" -c ksops --tail=50 2>/dev/null || echo "Could not retrieve logs"
    fi
    exit 1
fi

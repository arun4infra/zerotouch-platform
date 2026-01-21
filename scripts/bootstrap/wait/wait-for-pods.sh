#!/bin/bash
# Wait for pods in critical namespaces to be ready
# Usage: ./wait-for-pods.sh [--timeout seconds]

set -e

TIMEOUT=600
CHECK_INTERVAL=10

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--timeout seconds]"
            exit 1
            ;;
    esac
done

# All namespaces that must have pods ready
ALL_NAMESPACES=("argocd" "external-secrets" "crossplane-system" "keda")

echo "Waiting for all pods to be ready..."
echo "Timeout: ${TIMEOUT}s"
echo ""

ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    echo "=== Checking pod status (${ELAPSED}s / ${TIMEOUT}s) ==="
    
    ALL_READY=true
    
    for ns in "${ALL_NAMESPACES[@]}"; do
        if ! kubectl get namespace "$ns" &>/dev/null; then
            echo "  $ns: namespace not found (may not be deployed yet)"
            ALL_READY=false
            continue
        fi
        
        TOTAL_PODS=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        
        if [[ "$TOTAL_PODS" -eq 0 ]]; then
            echo "  $ns: no pods (may not be deployed yet)"
            ALL_READY=false
            continue
        fi
        
        READY_PODS=$(kubectl get pods -n "$ns" -o json 2>/dev/null | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')
        
        if [[ "$READY_PODS" -eq "$TOTAL_PODS" ]]; then
            echo "  $ns: ✓ $READY_PODS/$TOTAL_PODS ready"
        else
            echo "  $ns: ⏳ $READY_PODS/$TOTAL_PODS ready"
            ALL_READY=false
            
            # Show which pods are not ready
            NOT_READY=$(kubectl get pods -n "$ns" -o json 2>/dev/null | jq -r '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status!="True")) | "\(.metadata.name) (\(.status.phase))"' | head -3)
            if [[ -n "$NOT_READY" ]]; then
                echo "$NOT_READY" | while read -r line; do
                    [[ -n "$line" ]] && echo "      - $line"
                done
            fi
        fi
    done
    
    echo ""
    
    if [ "$ALL_READY" = true ]; then
        echo "✓ All pods are ready!"
        exit 0
    fi
    
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

echo "✗ Timeout waiting for pods to be ready"
echo ""
echo "Final pod status:"
for ns in "${ALL_NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        echo ""
        echo "=== $ns ==="
        kubectl get pods -n "$ns" 2>/dev/null || echo "No pods"
    fi
done
exit 1

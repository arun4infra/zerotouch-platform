#!/bin/bash
# Port-Forward Validation Script
# Tests port-forward stability for critical platform services
#
# Usage: ./validate-port-forwards.sh [--timeout seconds] [--preview-mode]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
TIMEOUT=300
PREVIEW_MODE=false
CHECK_INTERVAL=5

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --preview-mode)
            PREVIEW_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--timeout seconds] [--preview-mode]"
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "🔌 Port-Forward Validation"
echo "=========================================="
echo ""
echo "Mode: $([ "$PREVIEW_MODE" = true ] && echo "Preview" || echo "Production")"
echo "Timeout: ${TIMEOUT}s"
echo ""

# Track overall status
FAILED=0

# Define services to test based on mode
if [ "$PREVIEW_MODE" = true ]; then
    # Preview mode - test services that should be available
    SERVICES=(
        "nats:nats:svc/nats:14222:4222"
        "argocd:argocd:svc/argocd-server:18080:443"
    )
    
    # Check if intelligence services are deployed
    if kubectl get namespace intelligence-deepagents &>/dev/null; then
        SERVICES+=(
            "intelligence-deepagents:intelligence-deepagents:svc/deepagents-runtime-db-rw:15433:5432"
            "intelligence-deepagents:intelligence-deepagents:svc/deepagents-runtime-cache:16380:6379"
        )
    fi
else
    # Production mode - test core platform services
    SERVICES=(
        "nats:nats:svc/nats:14222:4222"
        "argocd:argocd:svc/argocd-server:18080:443"
    )
fi

# Function to test a single port-forward
test_port_forward() {
    local namespace=$1
    local service_name=$2
    local service=$3
    local local_port=$4
    local remote_port=$5
    
    echo -e "🔍 Testing ${BLUE}$service_name${NC} ($namespace)"
    
    # Check if service exists
    if ! kubectl get service -n "$namespace" "${service#svc/}" >/dev/null 2>&1; then
        echo -e "  ❌ ${RED}Service not found${NC}: $service in namespace $namespace"
        return 1
    fi
    
    # Kill any existing process on the port
    local existing_pids=$(lsof -ti:$local_port 2>/dev/null || true)
    if [ ! -z "$existing_pids" ]; then
        echo "  🧹 Cleaning up existing processes on port $local_port"
        echo "$existing_pids" | xargs kill -9 2>/dev/null || true
        sleep 2
    fi
    
    # Start port-forward
    echo "  📡 Starting port-forward ($local_port -> $remote_port)..."
    kubectl port-forward -n "$namespace" "$service" "$local_port:$remote_port" >/dev/null 2>&1 &
    local pf_pid=$!
    
    # Wait for port-forward to establish
    sleep 3
    
    # Check if process is still running
    if ! kill -0 $pf_pid 2>/dev/null; then
        echo -e "  ❌ ${RED}Port-forward process died immediately${NC}"
        return 1
    fi
    
    # Test connection
    local connection_test=false
    local attempts=0
    local max_attempts=5
    
    while [ $attempts -lt $max_attempts ]; do
        if nc -z localhost $local_port 2>/dev/null; then
            connection_test=true
            break
        fi
        sleep 1
        ((attempts++))
    done
    
    if [ "$connection_test" = false ]; then
        echo -e "  ❌ ${RED}Connection test failed${NC} (port $local_port not responding)"
        kill $pf_pid 2>/dev/null || true
        return 1
    fi
    
    echo -e "  ✅ ${GREEN}Initial connection successful${NC}"
    
    # Stability test - keep connection alive and test periodically
    echo "  ⏱️  Testing stability for 30 seconds..."
    local stability_duration=30
    local stability_checks=$((stability_duration / CHECK_INTERVAL))
    local stable_checks=0
    
    for ((i=1; i<=stability_checks; i++)); do
        sleep $CHECK_INTERVAL
        
        # Check if port-forward process is still alive
        if ! kill -0 $pf_pid 2>/dev/null; then
            echo -e "  ❌ ${RED}Port-forward died during stability test${NC} (after $((i * CHECK_INTERVAL))s)"
            return 1
        fi
        
        # Test connection
        if nc -z localhost $local_port 2>/dev/null; then
            ((stable_checks++))
        else
            echo -e "  ❌ ${RED}Connection lost during stability test${NC} (after $((i * CHECK_INTERVAL))s)"
            kill $pf_pid 2>/dev/null || true
            return 1
        fi
    done
    
    # Cleanup
    kill $pf_pid 2>/dev/null || true
    sleep 1
    
    echo -e "  ✅ ${GREEN}Stability test passed${NC} ($stable_checks/$stability_checks checks successful)"
    return 0
}

# Run tests for each service
echo "📋 Testing port-forwards for ${#SERVICES[@]} services:"
echo ""

for service_config in "${SERVICES[@]}"; do
    IFS=':' read -r service_name namespace service local_port remote_port <<< "$service_config"
    
    if test_port_forward "$namespace" "$service_name" "$service" "$local_port" "$remote_port"; then
        echo -e "  ✅ ${GREEN}$service_name: PASSED${NC}"
    else
        echo -e "  ❌ ${RED}$service_name: FAILED${NC}"
        ((FAILED++))
    fi
    echo ""
done

# CNI Health Check (for preview mode)
if [ "$PREVIEW_MODE" = true ]; then
    echo "🌐 CNI Health Check:"
    echo "------------------------------------------"
    
    # Check if Cilium is running (should not be in preview mode)
    CILIUM_PODS=$(kubectl get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | wc -l | tr -d ' ')
    KINDNET_PODS=$(kubectl get pods -n kube-system -l app=kindnet --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$CILIUM_PODS" -gt 0 ]; then
        echo -e "  ⚠️  ${YELLOW}Cilium pods detected${NC}: $CILIUM_PODS (may cause port-forward issues)"
        echo -e "     ${YELLOW}Recommendation:${NC} Disable Cilium for Kind clusters"
        echo -e "     ${YELLOW}Note:${NC} This is a warning only - port-forwards are working"
    else
        echo -e "  ✅ ${GREEN}No Cilium pods detected${NC} (good for Kind clusters)"
    fi
    
    if [ "$KINDNET_PODS" -gt 0 ]; then
        echo -e "  ✅ ${GREEN}Kindnet CNI running${NC}: $KINDNET_PODS pods"
    else
        echo -e "  ⚠️  ${YELLOW}No Kindnet pods detected${NC}"
    fi
    
    # Check for old CNI network namespaces
    if command -v docker >/dev/null 2>&1; then
        KIND_CONTAINER=$(docker ps --filter "name=.*-control-plane" --format "{{.Names}}" 2>/dev/null | head -1)
        if [ -n "$KIND_CONTAINER" ]; then
            CNI_NAMESPACES=$(docker exec "$KIND_CONTAINER" ip netns list 2>/dev/null | wc -l | tr -d ' ')
            if [ "$CNI_NAMESPACES" -gt 10 ]; then
                echo -e "  ⚠️  ${YELLOW}Many CNI network namespaces detected${NC}: $CNI_NAMESPACES"
                echo -e "     ${YELLOW}This may indicate CNI conflicts${NC}"
            else
                echo -e "  ✅ ${GREEN}CNI network namespaces${NC}: $CNI_NAMESPACES (normal)"
            fi
        fi
    fi
    
    echo ""
fi

# Final Summary
echo "=========================================="
if [ $FAILED -eq 0 ]; then
    echo -e "✅ ${GREEN}PORT-FORWARD VALIDATION PASSED${NC}"
    echo "All port-forwards are stable and functional"
    exit 0
else
    echo -e "❌ ${RED}PORT-FORWARD VALIDATION FAILED${NC}"
    echo "$FAILED service(s) failed port-forward tests"
    echo ""
    echo "Common issues:"
    echo "  • CNI conflicts (Cilium + kindnet in Kind clusters)"
    echo "  • Service not ready or unhealthy"
    echo "  • Network namespace issues"
    echo "  • Resource constraints"
    echo ""
    echo "For Kind clusters, ensure Cilium is disabled:"
    echo "  ./scripts/bootstrap/patches/07-disable-cilium-for-kind.sh --force"
    exit 1
fi
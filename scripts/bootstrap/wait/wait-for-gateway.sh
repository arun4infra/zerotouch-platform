#!/bin/bash
# Wait for Gateway to be provisioned with LoadBalancer IP
# Usage: ./wait-for-gateway.sh [--timeout <seconds>]
#
# This script waits for:
# 1. Gateway to be Accepted by controller
# 2. Gateway to be Programmed (LoadBalancer provisioned)
# 3. LoadBalancer IP to be assigned
# 4. Basic connectivity test to LoadBalancer

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
TIMEOUT=300  # 5 minutes default
POLL_INTERVAL=10
GATEWAY_NAME="public-gateway"
GATEWAY_NAMESPACE="kube-system"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --gateway-name)
            GATEWAY_NAME="$2"
            shift 2
            ;;
        --namespace)
            GATEWAY_NAMESPACE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--timeout <seconds>] [--gateway-name <name>] [--namespace <namespace>]"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Waiting for Gateway Infrastructure                         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Gateway: ${GATEWAY_NAME}${NC}"
echo -e "${BLUE}Namespace: ${GATEWAY_NAMESPACE}${NC}"
echo -e "${BLUE}Timeout: ${TIMEOUT}s${NC}"
echo ""

# Function to check Gateway status
check_gateway_status() {
    local gateway_json
    gateway_json=$(kubectl get gateway "$GATEWAY_NAME" -n "$GATEWAY_NAMESPACE" -o json 2>/dev/null || echo "{}")
    
    if [ "$gateway_json" = "{}" ]; then
        echo "not_found"
        return
    fi
    
    local accepted_status programmed_status loadbalancer_ip
    accepted_status=$(echo "$gateway_json" | jq -r '.status.conditions[] | select(.type == "Accepted") | .status' 2>/dev/null || echo "Unknown")
    programmed_status=$(echo "$gateway_json" | jq -r '.status.conditions[] | select(.type == "Programmed") | .status' 2>/dev/null || echo "Unknown")
    loadbalancer_ip=$(echo "$gateway_json" | jq -r '.status.addresses[]? | select(.type == "IPAddress") | .value' 2>/dev/null || echo "")
    
    echo "${accepted_status}|${programmed_status}|${loadbalancer_ip}"
}

# Function to get Gateway condition messages
get_gateway_messages() {
    local gateway_json
    gateway_json=$(kubectl get gateway "$GATEWAY_NAME" -n "$GATEWAY_NAMESPACE" -o json 2>/dev/null || echo "{}")
    
    if [ "$gateway_json" != "{}" ]; then
        local accepted_msg programmed_msg
        accepted_msg=$(echo "$gateway_json" | jq -r '.status.conditions[] | select(.type == "Accepted") | .message' 2>/dev/null || echo "")
        programmed_msg=$(echo "$gateway_json" | jq -r '.status.conditions[] | select(.type == "Programmed") | .message' 2>/dev/null || echo "")
        
        [ -n "$accepted_msg" ] && echo "  Accepted: $accepted_msg"
        [ -n "$programmed_msg" ] && echo "  Programmed: $programmed_msg"
    fi
}

# Function to test LoadBalancer connectivity
test_connectivity() {
    local ip="$1"
    if command -v curl >/dev/null 2>&1; then
        if curl -s --connect-timeout 5 --max-time 10 "http://$ip" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

ELAPSED=0
LAST_STATUS=""

while [ $ELAPSED -lt $TIMEOUT ]; do
    STATUS=$(check_gateway_status)
    
    # Show continuous status updates every check interval (like other wait scripts)
    echo -e "${BLUE}=== Checking Gateway status (${ELAPSED}s / ${TIMEOUT}s) ===${NC}"
    
    case "$STATUS" in
        "not_found")
            echo -e "${YELLOW}⏳ Waiting for Gateway resource to be created...${NC}"
            if [ "$LAST_STATUS" != "not_found" ]; then
                LAST_STATUS="not_found"
            fi
            ;;
        "Unknown|Unknown|")
            echo -e "${YELLOW}⏳ Gateway created, waiting for controller to process...${NC}"
            if [ "$LAST_STATUS" != "waiting_controller" ]; then
                get_gateway_messages
                LAST_STATUS="waiting_controller"
            fi
            ;;
        "True|Unknown|"|"True|False|")
            echo -e "${GREEN}✓ Gateway accepted by controller${NC}"
            echo -e "${YELLOW}⏳ Waiting for LoadBalancer provisioning...${NC}"
            if [ "$LAST_STATUS" != "accepted" ]; then
                get_gateway_messages
                LAST_STATUS="accepted"
            fi
            ;;
        "True|True|")
            echo -e "${GREEN}✓ Gateway programmed${NC}"
            echo -e "${YELLOW}⏳ Waiting for LoadBalancer IP assignment...${NC}"
            if [ "$LAST_STATUS" != "programmed_no_ip" ]; then
                LAST_STATUS="programmed_no_ip"
            fi
            ;;
        "True|True|"*)
            IFS='|' read -r accepted programmed ip <<< "$STATUS"
            if [ -n "$ip" ]; then
                echo -e "${GREEN}✓ Gateway ready with LoadBalancer IP: ${ip}${NC}"
                
                # Test connectivity
                echo -e "${BLUE}🔍 Testing LoadBalancer connectivity...${NC}"
                if test_connectivity "$ip"; then
                    echo -e "${GREEN}✓ LoadBalancer responds to HTTP requests${NC}"
                else
                    echo -e "${YELLOW}⚠️  LoadBalancer reachable but no routes configured (expected)${NC}"
                fi
                
                echo ""
                echo -e "${GREEN}✓ Gateway Infrastructure Ready${NC}"
                echo -e "${BLUE}ℹ  LoadBalancer IP: ${ip}${NC}"
                echo -e "${BLUE}ℹ  Gateway can now accept HTTPRoute configurations${NC}"
                echo ""
                exit 0
            fi
            ;;
        *)
            IFS='|' read -r accepted programmed ip <<< "$STATUS"
            echo -e "${RED}⚠️  Gateway in unexpected state:${NC}"
            echo -e "   Accepted: $accepted"
            echo -e "   Programmed: $programmed"
            echo -e "   IP: ${ip:-none}"
            if [ "$LAST_STATUS" != "error_state" ]; then
                get_gateway_messages
                LAST_STATUS="error_state"
            fi
            ;;
    esac
    
    # Show current Gateway resource status (like other wait scripts show pod status)
    echo -e "${BLUE}Gateway resource status:${NC}"
    if kubectl get gateway "$GATEWAY_NAME" -n "$GATEWAY_NAMESPACE" >/dev/null 2>&1; then
        kubectl get gateway "$GATEWAY_NAME" -n "$GATEWAY_NAMESPACE" -o custom-columns="NAME:.metadata.name,CLASS:.spec.gatewayClassName,ADDRESS:.status.addresses[0].value,READY:.status.conditions[?(@.type=='Ready')].status" --no-headers 2>/dev/null || \
        kubectl get gateway "$GATEWAY_NAME" -n "$GATEWAY_NAMESPACE" --no-headers 2>/dev/null
    else
        echo -e "   ${YELLOW}Gateway resource not found${NC}"
    fi
    
    echo ""
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

# Timeout reached - show diagnostics
echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   TIMEOUT: Gateway not ready after ${TIMEOUT}s                   ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}=== DIAGNOSTICS ===${NC}"
echo ""

# Show Gateway status
echo -e "${BLUE}1. Gateway Status:${NC}"
if kubectl get gateway "$GATEWAY_NAME" -n "$GATEWAY_NAMESPACE" &>/dev/null; then
    kubectl describe gateway "$GATEWAY_NAME" -n "$GATEWAY_NAMESPACE"
else
    echo -e "${RED}✗ Gateway ${GATEWAY_NAME} not found in namespace ${GATEWAY_NAMESPACE}${NC}"
fi
echo ""

# Show GatewayClass status
echo -e "${BLUE}2. GatewayClass Status:${NC}"
if kubectl get gatewayclass cilium &>/dev/null; then
    kubectl describe gatewayclass cilium
else
    echo -e "${RED}✗ GatewayClass cilium not found${NC}"
fi
echo ""

# Show Cilium operator logs
echo -e "${BLUE}3. Cilium Operator Logs (last 20 lines):${NC}"
if kubectl get deployment cilium-operator -n kube-system &>/dev/null; then
    kubectl logs -n kube-system deployment/cilium-operator --tail=20 | grep -i gateway || echo "No gateway-related logs found"
else
    echo -e "${RED}✗ Cilium operator not found${NC}"
fi
echo ""

# Show HCCM logs if LoadBalancer provisioning is the issue
echo -e "${BLUE}4. Hetzner Cloud Controller Manager Logs (last 10 lines):${NC}"
if kubectl get deployment hcloud-cloud-controller-manager -n kube-system &>/dev/null; then
    kubectl logs -n kube-system deployment/hcloud-cloud-controller-manager --tail=10 || echo "No HCCM logs available"
else
    echo -e "${RED}✗ Hetzner Cloud Controller Manager not found${NC}"
fi
echo ""

echo -e "${YELLOW}Manual debug commands:${NC}"
echo "  kubectl describe gateway ${GATEWAY_NAME} -n ${GATEWAY_NAMESPACE}"
echo "  kubectl describe gatewayclass cilium"
echo "  kubectl logs -n kube-system deployment/cilium-operator --tail=50"
echo "  kubectl logs -n kube-system deployment/hcloud-cloud-controller-manager --tail=50"
echo ""

exit 1
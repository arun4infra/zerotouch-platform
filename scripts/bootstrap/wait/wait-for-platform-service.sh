#!/bin/bash
# Wait for Platform Service to be processed and deployment to be created
# Usage: ./wait-for-platform-service.sh <service-name> <namespace> [timeout]

set -euo pipefail

SERVICE_NAME="${1:?Service name required}"
NAMESPACE="${2:?Namespace required}"
TIMEOUT="${3:-300}"

ELAPSED=0
INTERVAL=10

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Waiting for Platform Service $SERVICE_NAME to be processed...${NC}"

# Load platform service configuration from ci/config.yaml
load_platform_service_config() {
    local config_file="${SERVICE_ROOT:-$(pwd)}/ci/config.yaml"
    
    if [[ ! -f "$config_file" ]]; then
        echo "❌ Service config not found: $config_file"
        return 1
    fi
    
    if command -v yq &> /dev/null; then
        PLATFORM_SERVICE_TYPE=$(yq eval '.platform.service.type // ""' "$config_file")
        PLATFORM_SERVICE_NAME=$(yq eval '.platform.service.name // ""' "$config_file")
    else
        echo "❌ yq is required but not installed"
        return 1
    fi
}

# Dynamically discover platform services in the namespace
discover_platform_service() {
    # First try to use config if available
    if load_platform_service_config && [[ -n "$PLATFORM_SERVICE_TYPE" ]] && [[ -n "$PLATFORM_SERVICE_NAME" ]]; then
        if kubectl get "$PLATFORM_SERVICE_TYPE" "$PLATFORM_SERVICE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
            echo "$PLATFORM_SERVICE_TYPE:$PLATFORM_SERVICE_NAME"
            return 0
        fi
    fi
    
    # Fallback to discovery
    local platform_services=$(kubectl api-resources --api-group=platform.bizmatters.io --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    
    for resource_type in $platform_services; do
        local resources=$(kubectl get "$resource_type" -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
        for resource_name in $resources; do
            if [[ "$resource_name" == *"$SERVICE_NAME"* ]]; then
                echo "$resource_type:$resource_name"
                return 0
            fi
        done
    done
    return 1
}

SERVICE_TYPE=""
PLATFORM_SERVICE_NAME=""

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Discover platform service dynamically
    PLATFORM_SERVICE_INFO=$(discover_platform_service)
    
    if [ -z "$PLATFORM_SERVICE_INFO" ]; then
        echo -e "  ${YELLOW}Platform service for $SERVICE_NAME not found yet... (${ELAPSED}s elapsed)${NC}"
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
        continue
    fi
    
    SERVICE_TYPE=$(echo "$PLATFORM_SERVICE_INFO" | cut -d: -f1)
    PLATFORM_SERVICE_NAME=$(echo "$PLATFORM_SERVICE_INFO" | cut -d: -f2)
    
    echo -e "  ${BLUE}Found $SERVICE_TYPE: $PLATFORM_SERVICE_NAME${NC}"
    
    # Check platform service status
    PLATFORM_STATUS=$(kubectl get "$SERVICE_TYPE" "$PLATFORM_SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Unknown")
    echo -e "    ${BLUE}$SERVICE_TYPE status: $PLATFORM_STATUS${NC}"
    
    # For AgentSandboxService, check if it's ready (no deployment expected)
    if [[ "$SERVICE_TYPE" == "agentsandboxservices" ]]; then
        READY_STATUS=$(kubectl get "$SERVICE_TYPE" "$PLATFORM_SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        READY_MESSAGE=$(kubectl get "$SERVICE_TYPE" "$PLATFORM_SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")
        
        if [ "$READY_STATUS" = "True" ]; then
            echo -e "  ${GREEN}✓ $SERVICE_TYPE $PLATFORM_SERVICE_NAME is ready${NC}"
            exit 0
        else
            echo -e "  ${YELLOW}$SERVICE_TYPE not ready yet... (${ELAPSED}s elapsed)${NC}"
            if [[ -n "$READY_MESSAGE" ]]; then
                echo -e "    ${YELLOW}Reason: $READY_MESSAGE${NC}"
            fi
            
            # Show composite resource status for debugging
            COMPOSITE_NAME=$(kubectl get "$SERVICE_TYPE" "$PLATFORM_SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.resourceRef.name}' 2>/dev/null || echo "")
            if [[ -n "$COMPOSITE_NAME" ]]; then
                echo -e "    ${BLUE}Checking composite resource: $COMPOSITE_NAME${NC}"
                COMPOSITE_READY=$(kubectl get xagentsandboxservice "$COMPOSITE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
                COMPOSITE_MESSAGE=$(kubectl get xagentsandboxservice "$COMPOSITE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")
                echo -e "    ${BLUE}Composite Ready: $COMPOSITE_READY${NC}"
                if [[ -n "$COMPOSITE_MESSAGE" ]]; then
                    echo -e "    ${BLUE}Composite Message: $COMPOSITE_MESSAGE${NC}"
                fi
                
                # Show child resources status
                echo -e "    ${BLUE}Child resources:${NC}"
                kubectl get xagentsandboxservice "$COMPOSITE_NAME" -o jsonpath='{.spec.resourceRefs[*].name}' 2>/dev/null | tr ' ' '\n' | while read -r child; do
                    if [[ -n "$child" ]]; then
                        CHILD_KIND=$(kubectl get xagentsandboxservice "$COMPOSITE_NAME" -o jsonpath="{.spec.resourceRefs[?(@.name=='$child')].kind}" 2>/dev/null || echo "Unknown")
                        echo -e "      - $CHILD_KIND: $child"
                    fi
                done
                
                # Debug storage component specifically if it's the blocker
                if [[ "$COMPOSITE_MESSAGE" == *"storage-component"* ]]; then
                    echo -e "    ${YELLOW}=== STORAGE COMPONENT DEBUG ===${NC}"
                    STORAGE_NAME=$(kubectl get xagentsandboxservice "$COMPOSITE_NAME" -o jsonpath='{.spec.resourceRefs[?(@.kind=="XAgentSandboxStorage")].name}' 2>/dev/null || echo "")
                    if [[ -n "$STORAGE_NAME" ]]; then
                        echo -e "    ${YELLOW}Storage resource: $STORAGE_NAME${NC}"
                        STORAGE_READY=$(kubectl get xagentsandboxstorage "$STORAGE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
                        STORAGE_MESSAGE=$(kubectl get xagentsandboxstorage "$STORAGE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")
                        echo -e "    ${YELLOW}Storage Ready: $STORAGE_READY${NC}"
                        if [[ -n "$STORAGE_MESSAGE" ]]; then
                            echo -e "    ${YELLOW}Storage Message: $STORAGE_MESSAGE${NC}"
                        fi
                        
                        # Show storage's child objects
                        echo -e "    ${YELLOW}Storage child objects:${NC}"
                        kubectl get xagentsandboxstorage "$STORAGE_NAME" -o jsonpath='{.spec.resourceRefs[*].name}' 2>/dev/null | tr ' ' '\n' | while read -r obj; do
                            if [[ -n "$obj" ]]; then
                                OBJ_KIND=$(kubectl get xagentsandboxstorage "$STORAGE_NAME" -o jsonpath="{.spec.resourceRefs[?(@.name=='$obj')].kind}" 2>/dev/null || echo "Unknown")
                                OBJ_READY=$(kubectl get object "$obj" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
                                echo -e "      - $OBJ_KIND: $obj (Ready: $OBJ_READY)"
                                if [[ "$OBJ_READY" != "True" ]]; then
                                    OBJ_MESSAGE=$(kubectl get object "$obj" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")
                                    if [[ -n "$OBJ_MESSAGE" ]]; then
                                        echo -e "        Message: $OBJ_MESSAGE"
                                    fi
                                fi
                            fi
                        done
                    fi
                    echo -e "    ${YELLOW}=== END STORAGE DEBUG ===${NC}"
                fi
            fi
            
            sleep $INTERVAL
            ELAPSED=$((ELAPSED + INTERVAL))
            continue
        fi
    fi
    
    # For other platform services, check if Deployment exists (created by Crossplane composition)
    if ! kubectl get deployment "$SERVICE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        echo -e "  ${YELLOW}Waiting for Deployment to be created by platform... (${ELAPSED}s elapsed)${NC}"
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
        continue
    fi
    
    # Check Deployment status
    READY_REPLICAS=$(kubectl get deployment "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    TOTAL_REPLICAS=$(kubectl get deployment "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    echo -e "  ${BLUE}Deployment: $SERVICE_NAME | Ready: $READY_REPLICAS/$TOTAL_REPLICAS (${ELAPSED}s elapsed)${NC}"
    
    # Check for pod failures
    POD_STATUS=$(kubectl get pods -n "$NAMESPACE" -l app="$SERVICE_NAME" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$POD_STATUS" = "Failed" ] || [ "$POD_STATUS" = "CrashLoopBackOff" ]; then
        echo -e "  ${RED}✗ Pod is in failed state: $POD_STATUS${NC}"
        kubectl describe pods -n "$NAMESPACE" -l app="$SERVICE_NAME"
        exit 1
    fi
    
    if [ "$READY_REPLICAS" = "$TOTAL_REPLICAS" ] && [ "$READY_REPLICAS" != "0" ]; then
        echo -e "  ${GREEN}✓ $SERVICE_TYPE $PLATFORM_SERVICE_NAME is ready${NC}"
        exit 0
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo -e "${RED}✗ Timeout waiting for Platform Service after ${TIMEOUT}s${NC}"
echo ""
echo -e "${YELLOW}=== Debugging Information ===${NC}"

if [ -n "$PLATFORM_SERVICE_NAME" ] && [ -n "$SERVICE_TYPE" ]; then
    echo "$SERVICE_TYPE details:"
    kubectl describe "$SERVICE_TYPE" "$PLATFORM_SERVICE_NAME" -n "$NAMESPACE" 2>/dev/null || echo "Not found"
    echo ""
fi

echo "Deployment details:"
kubectl describe deployment "$SERVICE_NAME" -n "$NAMESPACE" 2>/dev/null || echo "Not found"
echo ""
echo "Pods:"
kubectl get pods -n "$NAMESPACE" -l app="$SERVICE_NAME" 2>/dev/null || echo "No pods found"
echo ""
echo "Recent events in namespace:"
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20
exit 1
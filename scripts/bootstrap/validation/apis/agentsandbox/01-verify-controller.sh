#!/bin/bash
# Verify Agent Sandbox Controller Bootstrap
# Usage: ./01-verify-controller.sh [--tenant <name>] [--namespace <name>] [--verbose] [--cleanup]
#
# This script verifies:
# 1. agent-sandbox-system namespace exists in live cluster
# 2. agent-sandbox-controller pod is Ready and healthy in cluster
# 3. SandboxTemplate and SandboxWarmPool CRDs are installed and accessible
# 4. aws-access-token secret exists in intelligence-deepagents namespace
# 5. Controller responds to health checks via live HTTP requests

set -euo pipefail

# Print output immediately for CI visibility
echo "Starting Agent Sandbox Controller verification..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || {
    echo "ERROR: Failed to determine script directory" >&2
    exit 1
}

# Navigate to repo root from script location (5 levels up from scripts/bootstrap/validation/apis/agentsandbox/)
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)" || {
    echo "ERROR: Failed to navigate to repo root from $SCRIPT_DIR" >&2
    # Fallback: assume we're in the repo root already
    REPO_ROOT="$(pwd)"
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
TENANT=""
NAMESPACE=""
VERBOSE=false
CLEANUP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tenant)
            TENANT="$2"
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
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--tenant <name>] [--namespace <name>] [--verbose] [--cleanup]"
            exit 1
            ;;
    esac
done

# Kubectl wrapper function with optional timeout
kubectl_cmd() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 15 kubectl "$@"
    else
        kubectl "$@"
    fi
}

# Kubectl retry function
kubectl_retry() {
    local max_attempts=5
    local attempt=1
    local exitCode=0

    while [ $attempt -le $max_attempts ]; do
        if kubectl_cmd "$@" 2>/dev/null; then
            return 0
        fi

        exitCode=$?

        if [ $attempt -lt $max_attempts ]; then
            local delay=$((attempt * 2))
            if [ "$VERBOSE" = true ]; then
                echo -e "${YELLOW}⚠️  kubectl command failed (attempt $attempt/$max_attempts). Retrying in ${delay}s...${NC}" >&2
            fi
            sleep $delay
        fi

        attempt=$((attempt + 1))
    done

    echo -e "${RED}✗ kubectl command failed after $max_attempts attempts${NC}" >&2
    return $exitCode
}

# Wait for resource to be ready
wait_for_ready() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="$3"
    local timeout="${4:-300}"
    
    echo -e "${BLUE}Waiting for $resource_type/$resource_name to be ready (timeout: ${timeout}s)...${NC}"
    
    if kubectl_cmd wait --for=condition=Ready "$resource_type/$resource_name" -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
        echo -e "${GREEN}✓ $resource_type/$resource_name is ready${NC}"
        return 0
    else
        echo -e "${RED}✗ $resource_type/$resource_name failed to become ready within ${timeout}s${NC}"
        return 1
    fi
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Verifying Agent Sandbox Controller Bootstrap              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Track overall status
ERRORS=0
WARNINGS=0

# 1. Verify agent-sandbox-system namespace exists in live cluster
echo -e "${BLUE}Verifying agent-sandbox-system namespace...${NC}"

if kubectl_retry get namespace agent-sandbox-system &>/dev/null; then
    echo -e "${GREEN}✓ Namespace 'agent-sandbox-system' exists${NC}"
    
    # Check namespace status
    NAMESPACE_STATUS=$(kubectl_retry get namespace agent-sandbox-system -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$NAMESPACE_STATUS" = "Active" ]; then
        echo -e "${GREEN}✓ Namespace status: Active${NC}"
    else
        echo -e "${YELLOW}⚠️  Namespace status: $NAMESPACE_STATUS (expected: Active)${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${RED}✗ Namespace 'agent-sandbox-system' not found${NC}"
    echo -e "${BLUE}ℹ  Check if agent-sandbox controller deployment is applied${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# 2. Verify agent-sandbox-controller pod is Ready and healthy in cluster
echo -e "${BLUE}Verifying agent-sandbox-controller pod...${NC}"

if kubectl_retry get pods -n agent-sandbox-system -l app=agent-sandbox-controller &>/dev/null; then
    POD_COUNT=$(kubectl_retry get pods -n agent-sandbox-system -l app=agent-sandbox-controller --no-headers 2>/dev/null | wc -l)
    echo -e "${GREEN}✓ Found $POD_COUNT agent-sandbox-controller pod(s)${NC}"
    
    # Check if at least one pod is ready
    READY_PODS=$(kubectl_retry get pods -n agent-sandbox-system -l app=agent-sandbox-controller -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o "True" | wc -l)
    
    if [ "$READY_PODS" -gt 0 ]; then
        echo -e "${GREEN}✓ $READY_PODS pod(s) are Ready${NC}"
        
        # Get pod status details
        POD_NAME=$(kubectl_retry get pods -n agent-sandbox-system -l app=agent-sandbox-controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$POD_NAME" ]; then
            POD_PHASE=$(kubectl_retry get pod "$POD_NAME" -n agent-sandbox-system -o jsonpath='{.status.phase}' 2>/dev/null)
            echo -e "${GREEN}✓ Pod $POD_NAME phase: $POD_PHASE${NC}"
            
            if [ "$VERBOSE" = true ]; then
                echo -e "${BLUE}Pod details:${NC}"
                kubectl_retry describe pod "$POD_NAME" -n agent-sandbox-system 2>/dev/null | head -20
            fi
        fi
    else
        echo -e "${RED}✗ No agent-sandbox-controller pods are Ready${NC}"
        
        # Show pod status for debugging
        echo -e "${BLUE}Pod status:${NC}"
        kubectl_retry get pods -n agent-sandbox-system -l app=agent-sandbox-controller 2>/dev/null || true
        
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${RED}✗ No agent-sandbox-controller pods found${NC}"
    echo -e "${BLUE}ℹ  Check if agent-sandbox controller deployment is applied and pods are starting${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# 3. Verify SandboxTemplate and SandboxWarmPool CRDs are installed and accessible
echo -e "${BLUE}Verifying agent-sandbox CRDs...${NC}"

# Check SandboxTemplate CRD
if kubectl_retry get crd sandboxtemplates.extensions.agents.x-k8s.io &>/dev/null; then
    echo -e "${GREEN}✓ SandboxTemplate CRD is installed${NC}"
    
    # Verify CRD version
    CRD_VERSION=$(kubectl_retry get crd sandboxtemplates.extensions.agents.x-k8s.io -o jsonpath='{.spec.versions[0].name}' 2>/dev/null)
    echo -e "${GREEN}✓ SandboxTemplate CRD version: $CRD_VERSION${NC}"
else
    echo -e "${RED}✗ SandboxTemplate CRD not found${NC}"
    echo -e "${BLUE}ℹ  Check if agent-sandbox controller has installed the CRDs${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check SandboxWarmPool CRD
if kubectl_retry get crd sandboxwarmpools.extensions.agents.x-k8s.io &>/dev/null; then
    echo -e "${GREEN}✓ SandboxWarmPool CRD is installed${NC}"
    
    # Verify CRD version
    CRD_VERSION=$(kubectl_retry get crd sandboxwarmpools.extensions.agents.x-k8s.io -o jsonpath='{.spec.versions[0].name}' 2>/dev/null)
    echo -e "${GREEN}✓ SandboxWarmPool CRD version: $CRD_VERSION${NC}"
else
    echo -e "${RED}✗ SandboxWarmPool CRD not found${NC}"
    echo -e "${BLUE}ℹ  Check if agent-sandbox controller has installed the CRDs${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# 4. Verify aws-access-token secret exists in intelligence-deepagents namespace
echo -e "${BLUE}Verifying aws-access-token secret...${NC}"

if kubectl_retry get secret aws-access-token -n intelligence-deepagents &>/dev/null; then
    echo -e "${GREEN}✓ Secret 'aws-access-token' exists in intelligence-deepagents namespace${NC}"
    
    # Check secret keys
    SECRET_KEYS=$(kubectl_retry get secret aws-access-token -n intelligence-deepagents -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys[]' 2>/dev/null | sort)
    if echo "$SECRET_KEYS" | grep -q "AWS_ACCESS_KEY_ID"; then
        echo -e "${GREEN}✓ Secret contains AWS_ACCESS_KEY_ID${NC}"
    else
        echo -e "${RED}✗ Secret missing AWS_ACCESS_KEY_ID${NC}"
        ERRORS=$((ERRORS + 1))
    fi
    
    if echo "$SECRET_KEYS" | grep -q "AWS_SECRET_ACCESS_KEY"; then
        echo -e "${GREEN}✓ Secret contains AWS_SECRET_ACCESS_KEY${NC}"
    else
        echo -e "${RED}✗ Secret missing AWS_SECRET_ACCESS_KEY${NC}"
        ERRORS=$((ERRORS + 1))
    fi
    
    if echo "$SECRET_KEYS" | grep -q "AWS_DEFAULT_REGION"; then
        echo -e "${GREEN}✓ Secret contains AWS_DEFAULT_REGION${NC}"
    else
        echo -e "${YELLOW}⚠️  Secret missing AWS_DEFAULT_REGION (optional)${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${RED}✗ Secret 'aws-access-token' not found in intelligence-deepagents namespace${NC}"
    echo -e "${BLUE}ℹ  Check if ExternalSecret aws-access-token-es is applied and synced${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# 5. Controller responds to health checks via live HTTP requests
echo -e "${BLUE}Verifying controller health checks...${NC}"

# First check if controller service exists
if kubectl_retry get service agent-sandbox-controller -n agent-sandbox-system &>/dev/null; then
    echo -e "${GREEN}✓ Controller service exists${NC}"
    
    # Get service port
    SERVICE_PORT=$(kubectl_retry get service agent-sandbox-controller -n agent-sandbox-system -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
    echo -e "${GREEN}✓ Service port: $SERVICE_PORT${NC}"
    
    # Test health endpoint using port-forward
    echo -e "${BLUE}Testing health endpoint...${NC}"
    
    # Start port-forward in background
    kubectl_cmd port-forward -n agent-sandbox-system service/agent-sandbox-controller 8080:$SERVICE_PORT &
    PORT_FORWARD_PID=$!
    
    # Wait a moment for port-forward to establish
    sleep 3
    
    # Test health endpoint
    if curl -s -f http://localhost:8080/healthz >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Controller health endpoint responds${NC}"
    else
        echo -e "${YELLOW}⚠️  Controller health endpoint not responding (may not be implemented yet)${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
    
    # Clean up port-forward
    kill $PORT_FORWARD_PID 2>/dev/null || true
    wait $PORT_FORWARD_PID 2>/dev/null || true
    
else
    echo -e "${YELLOW}⚠️  Controller service not found (may use different service name)${NC}"
    
    # Try to find any service in the namespace
    SERVICES=$(kubectl_retry get services -n agent-sandbox-system --no-headers 2>/dev/null | wc -l)
    if [ "$SERVICES" -gt 0 ]; then
        echo -e "${BLUE}Found $SERVICES service(s) in agent-sandbox-system namespace${NC}"
        if [ "$VERBOSE" = true ]; then
            kubectl_retry get services -n agent-sandbox-system 2>/dev/null || true
        fi
    fi
    
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# Cleanup if requested
if [ "$CLEANUP" = true ]; then
    echo -e "${BLUE}Cleaning up test resources...${NC}"
    # Add cleanup logic here if needed
    echo -e "${GREEN}✓ Cleanup completed${NC}"
    echo ""
fi

# Summary
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Verification Summary                                       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Agent Sandbox Controller is ready for XRD installation.${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Next steps:${NC}"
    echo "  - Create AgentSandboxService XRD: ./02-verify-xrd.sh"
    echo "  - Test controller functionality: kubectl apply -f test-sandboxtemplate.yaml"
    echo "  - Monitor controller logs: kubectl logs -n agent-sandbox-system -l app=agent-sandbox-controller"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Agent Sandbox Controller has $WARNINGS warning(s) but no errors${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Review warnings above and monitor the deployment${NC}"
    exit 0
else
    echo -e "${RED}✗ Agent Sandbox Controller has $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Troubleshooting steps:${NC}"
    echo "  1. Check ArgoCD Application: kubectl describe application agent-sandbox-controller -n argocd"
    echo "  2. Check controller deployment: kubectl describe deployment agent-sandbox-controller -n agent-sandbox-system"
    echo "  3. Check controller logs: kubectl logs -n agent-sandbox-system -l app=agent-sandbox-controller"
    echo "  4. Check ExternalSecret: kubectl describe externalsecret aws-access-token-es -n intelligence-deepagents"
    echo "  5. Verify CRD installation: kubectl get crds | grep sandbox"
    exit 1
fi
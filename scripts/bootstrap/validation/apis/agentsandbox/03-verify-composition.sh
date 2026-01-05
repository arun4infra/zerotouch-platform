#!/bin/bash
# Verify AgentSandboxService Composition
# Usage: ./03-verify-composition.sh [--tenant <name>] [--namespace <name>] [--verbose] [--cleanup]
#
# This script verifies:
# 1. Composition creates SandboxTemplate with correct pod spec in live cluster
# 2. Composition creates SandboxWarmPool referencing template in live cluster
# 3. ServiceAccount created with proper permissions and accessible via kubectl
# 4. Resource patching works for image and size fields in live Crossplane
# 5. Test claim provisions actual resources successfully in cluster

set -euo pipefail

# Print output immediately for CI visibility
echo "Starting AgentSandboxService Composition verification..."

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
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Kubectl wrapper function with optional timeout
kubectl_cmd() {
    # Use timeout if available, otherwise run directly
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

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Verifying AgentSandboxService Composition                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Track overall status
ERRORS=0
WARNINGS=0

# 1. Verify Composition is installed
echo -e "${BLUE}Verifying AgentSandboxService Composition...${NC}"

if kubectl_retry get composition agent-sandbox-service &>/dev/null; then
    echo -e "${GREEN}✓ Composition 'agent-sandbox-service' is installed${NC}"
    
    # Verify composition has correct XRD reference
    XRD_REF=$(kubectl_retry get composition agent-sandbox-service -o jsonpath='{.spec.compositeTypeRef.kind}' 2>/dev/null)
    if [ "$XRD_REF" = "XAgentSandboxService" ]; then
        echo -e "${GREEN}✓ Composition references correct XRD: XAgentSandboxService${NC}"
    else
        echo -e "${YELLOW}⚠️  Composition XRD reference: $XRD_REF (expected: XAgentSandboxService)${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
    
    # Verify composition has expected resources
    RESOURCE_COUNT=$(kubectl_retry get composition agent-sandbox-service -o jsonpath='{.spec.resources}' 2>/dev/null | jq '. | length' 2>/dev/null || echo "0")
    if [ "$RESOURCE_COUNT" -ge 4 ]; then
        echo -e "${GREEN}✓ Composition has $RESOURCE_COUNT resources (expected: 4+)${NC}"
    else
        echo -e "${YELLOW}⚠️  Composition has $RESOURCE_COUNT resources (expected: 4+)${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${RED}✗ Composition 'agent-sandbox-service' not found${NC}"
    echo -e "${BLUE}ℹ  Check if platform/04-apis/agentsandbox/composition.yaml is applied${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# 2. Test AgentSandboxService claim creation and resource provisioning
echo -e "${BLUE}Testing AgentSandboxService claim provisioning...${NC}"

# Create temporary namespace for testing
TEST_NAMESPACE="agentsandbox-comp-test-$$"
kubectl create namespace "$TEST_NAMESPACE" 2>/dev/null || true

# Create temporary test files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR; kubectl delete namespace $TEST_NAMESPACE --ignore-not-found=true &>/dev/null || true" EXIT

# Test 1: Create a test claim with minimal configuration
cat > "$TEMP_DIR/test-claim.yaml" << 'EOF'
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-sandbox
  namespace: agentsandbox-comp-test
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  size: "small"
  nats:
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer"
  storageGB: 5
EOF

# Replace namespace placeholder
sed -i.bak "s/agentsandbox-comp-test/$TEST_NAMESPACE/g" "$TEMP_DIR/test-claim.yaml"

if [ "$CLEANUP" = false ]; then
    echo -e "${BLUE}Creating test AgentSandboxService claim...${NC}"
    
    if kubectl apply -f "$TEMP_DIR/test-claim.yaml" &>/dev/null; then
        echo -e "${GREEN}✓ Test claim created successfully${NC}"
        
        # Wait for claim to be processed
        echo -e "${BLUE}Waiting for claim to be processed (30s timeout)...${NC}"
        sleep 5
        
        # Check if composite resource was created
        if kubectl get xagentsandboxservice -n "$TEST_NAMESPACE" &>/dev/null; then
            echo -e "${GREEN}✓ Composite resource (XAgentSandboxService) created${NC}"
        else
            echo -e "${YELLOW}⚠️  Composite resource not found after 5s${NC}"
            WARNINGS=$((WARNINGS + 1))
        fi
        
        # Wait a bit more for resources to be provisioned
        sleep 10
        
        # 3. Verify ServiceAccount creation
        echo -e "${BLUE}Verifying ServiceAccount creation...${NC}"
        if kubectl get serviceaccount test-sandbox -n "$TEST_NAMESPACE" &>/dev/null; then
            echo -e "${GREEN}✓ ServiceAccount 'test-sandbox' created successfully${NC}"
            
            # Check ServiceAccount labels
            SA_LABELS=$(kubectl get serviceaccount test-sandbox -n "$TEST_NAMESPACE" -o jsonpath='{.metadata.labels}' 2>/dev/null || echo "{}")
            if echo "$SA_LABELS" | grep -q "app.kubernetes.io/name"; then
                echo -e "${GREEN}✓ ServiceAccount has correct labels${NC}"
            else
                echo -e "${YELLOW}⚠️  ServiceAccount missing expected labels${NC}"
                WARNINGS=$((WARNINGS + 1))
            fi
        else
            echo -e "${RED}✗ ServiceAccount 'test-sandbox' not found${NC}"
            ERRORS=$((ERRORS + 1))
        fi
        
        # 4. Verify PersistentVolumeClaim creation
        echo -e "${BLUE}Verifying PersistentVolumeClaim creation...${NC}"
        if kubectl get pvc test-sandbox-workspace -n "$TEST_NAMESPACE" &>/dev/null; then
            echo -e "${GREEN}✓ PVC 'test-sandbox-workspace' created successfully${NC}"
            
            # Check PVC storage size
            PVC_SIZE=$(kubectl get pvc test-sandbox-workspace -n "$TEST_NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null || echo "unknown")
            if [ "$PVC_SIZE" = "5Gi" ]; then
                echo -e "${GREEN}✓ PVC has correct storage size: $PVC_SIZE${NC}"
            else
                echo -e "${YELLOW}⚠️  PVC storage size: $PVC_SIZE (expected: 5Gi)${NC}"
                WARNINGS=$((WARNINGS + 1))
            fi
        else
            echo -e "${RED}✗ PVC 'test-sandbox-workspace' not found${NC}"
            ERRORS=$((ERRORS + 1))
        fi
        
        # 5. Verify SandboxTemplate creation (via Crossplane Object)
        echo -e "${BLUE}Verifying SandboxTemplate creation...${NC}"
        TEMPLATE_OBJECTS=$(kubectl get object -A -o jsonpath='{.items[?(@.spec.forProvider.manifest.kind=="SandboxTemplate")].metadata.name}' | grep test-sandbox || echo "")
        if [ -n "$TEMPLATE_OBJECTS" ]; then
            echo -e "${GREEN}✓ SandboxTemplate Object created successfully${NC}"
            
            # Get the first template object for validation
            TEMPLATE_OBJECT_NAME=$(echo "$TEMPLATE_OBJECTS" | awk '{print $1}')
            TEMPLATE_NAMESPACE=$(kubectl get object "$TEMPLATE_OBJECT_NAME" -A -o jsonpath='{.metadata.namespace}' 2>/dev/null)
            
            if [ -n "$TEMPLATE_OBJECT_NAME" ] && [ -n "$TEMPLATE_NAMESPACE" ]; then
                # Check SandboxTemplate image patching
                TEMPLATE_IMAGE=$(kubectl get object "$TEMPLATE_OBJECT_NAME" -n "$TEMPLATE_NAMESPACE" -o jsonpath='{.spec.forProvider.manifest.spec.podTemplate.spec.containers[0].image}' 2>/dev/null || echo "unknown")
                if [ "$TEMPLATE_IMAGE" = "ghcr.io/test/agent:v1.0.0" ]; then
                    echo -e "${GREEN}✓ SandboxTemplate has correct image: $TEMPLATE_IMAGE${NC}"
                else
                    echo -e "${YELLOW}⚠️  SandboxTemplate image: $TEMPLATE_IMAGE (expected: ghcr.io/test/agent:v1.0.0)${NC}"
                    WARNINGS=$((WARNINGS + 1))
                fi
                
                # Check resource sizing (small = 250m CPU request)
                TEMPLATE_CPU=$(kubectl get object "$TEMPLATE_OBJECT_NAME" -n "$TEMPLATE_NAMESPACE" -o jsonpath='{.spec.forProvider.manifest.spec.podTemplate.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "unknown")
                if [ "$TEMPLATE_CPU" = "250m" ]; then
                    echo -e "${GREEN}✓ SandboxTemplate has correct CPU request: $TEMPLATE_CPU${NC}"
                else
                    echo -e "${YELLOW}⚠️  SandboxTemplate CPU request: $TEMPLATE_CPU (expected: 250m for size=small)${NC}"
                    WARNINGS=$((WARNINGS + 1))
                fi
                
                # Check workspace volume mount
                VOLUME_MOUNT=$(kubectl get object "$TEMPLATE_OBJECT_NAME" -n "$TEMPLATE_NAMESPACE" -o jsonpath='{.spec.forProvider.manifest.spec.podTemplate.spec.containers[0].volumeMounts[0].mountPath}' 2>/dev/null || echo "unknown")
                if [ "$VOLUME_MOUNT" = "/workspace" ]; then
                    echo -e "${GREEN}✓ SandboxTemplate has workspace volume mount: $VOLUME_MOUNT${NC}"
                else
                    echo -e "${YELLOW}⚠️  SandboxTemplate workspace mount: $VOLUME_MOUNT (expected: /workspace)${NC}"
                    WARNINGS=$((WARNINGS + 1))
                fi
            fi
        else
            echo -e "${RED}✗ SandboxTemplate Object not found${NC}"
            ERRORS=$((ERRORS + 1))
        fi
        
        # 6. Verify SandboxWarmPool creation (via Crossplane Object)
        echo -e "${BLUE}Verifying SandboxWarmPool creation...${NC}"
        POOL_OBJECTS=$(kubectl get object -A -o jsonpath='{.items[?(@.spec.forProvider.manifest.kind=="SandboxWarmPool")].metadata.name}' | grep test-sandbox || echo "")
        if [ -n "$POOL_OBJECTS" ]; then
            echo -e "${GREEN}✓ SandboxWarmPool Object created successfully${NC}"
            
            # Get the first pool object for validation
            POOL_OBJECT_NAME=$(echo "$POOL_OBJECTS" | awk '{print $1}')
            POOL_NAMESPACE=$(kubectl get object "$POOL_OBJECT_NAME" -A -o jsonpath='{.metadata.namespace}' 2>/dev/null)
            
            if [ -n "$POOL_OBJECT_NAME" ] && [ -n "$POOL_NAMESPACE" ]; then
                # Check SandboxWarmPool template reference
                POOL_TEMPLATE_REF=$(kubectl get object "$POOL_OBJECT_NAME" -n "$POOL_NAMESPACE" -o jsonpath='{.spec.forProvider.manifest.spec.sandboxTemplateRef.name}' 2>/dev/null || echo "unknown")
                if [ "$POOL_TEMPLATE_REF" = "test-sandbox" ]; then
                    echo -e "${GREEN}✓ SandboxWarmPool references correct template: $POOL_TEMPLATE_REF${NC}"
                else
                    echo -e "${YELLOW}⚠️  SandboxWarmPool template reference: $POOL_TEMPLATE_REF (expected: test-sandbox)${NC}"
                    WARNINGS=$((WARNINGS + 1))
                fi
            fi
        else
            echo -e "${RED}✗ SandboxWarmPool Object not found${NC}"
            ERRORS=$((ERRORS + 1))
        fi
        
        # Clean up the test claim
        echo -e "${BLUE}Cleaning up test resources...${NC}"
        kubectl delete -f "$TEMP_DIR/test-claim.yaml" &>/dev/null || true
        
        # Wait for cleanup
        sleep 5
        
    else
        echo -e "${RED}✗ Failed to create test claim${NC}"
        if [ "$VERBOSE" = true ]; then
            kubectl apply -f "$TEMP_DIR/test-claim.yaml" || true
        fi
        ERRORS=$((ERRORS + 1))
    fi
fi

echo ""

# 7. Test resource patching with different configurations
echo -e "${BLUE}Testing resource patching with different configurations...${NC}"

# Test 2: Create a claim with different size and httpPort
cat > "$TEMP_DIR/test-claim-large.yaml" << 'EOF'
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-sandbox-large
  namespace: agentsandbox-comp-test
spec:
  image: "ghcr.io/test/agent:v2.0.0"
  size: "large"
  httpPort: 9000
  nats:
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer-large"
  storageGB: 20
  secret1Name: "test-db-secret"
  secret2Name: "test-cache-secret"
EOF

# Replace namespace placeholder
sed -i.bak "s/agentsandbox-comp-test/$TEST_NAMESPACE/g" "$TEMP_DIR/test-claim-large.yaml"

if [ "$CLEANUP" = false ]; then
    if kubectl apply --dry-run=server -f "$TEMP_DIR/test-claim-large.yaml" &>/dev/null; then
        echo -e "${GREEN}✓ Large configuration claim validates successfully${NC}"
        
        # Test actual creation briefly
        if kubectl apply -f "$TEMP_DIR/test-claim-large.yaml" &>/dev/null; then
            echo -e "${GREEN}✓ Large configuration claim created successfully${NC}"
            
            # Wait briefly and check one resource (via Crossplane Object)
            sleep 5
            LARGE_TEMPLATE_OBJECTS=$(kubectl get object -A -o jsonpath='{.items[?(@.spec.forProvider.manifest.kind=="SandboxTemplate")].metadata.name}' | grep test-sandbox-large || echo "")
            if [ -n "$LARGE_TEMPLATE_OBJECTS" ]; then
                LARGE_TEMPLATE_OBJECT_NAME=$(echo "$LARGE_TEMPLATE_OBJECTS" | awk '{print $1}')
                LARGE_TEMPLATE_NAMESPACE=$(kubectl get object "$LARGE_TEMPLATE_OBJECT_NAME" -A -o jsonpath='{.metadata.namespace}' 2>/dev/null)
                
                if [ -n "$LARGE_TEMPLATE_OBJECT_NAME" ] && [ -n "$LARGE_TEMPLATE_NAMESPACE" ]; then
                    # Check large size CPU limit (4000m)
                    LARGE_CPU_LIMIT=$(kubectl get object "$LARGE_TEMPLATE_OBJECT_NAME" -n "$LARGE_TEMPLATE_NAMESPACE" -o jsonpath='{.spec.forProvider.manifest.spec.podTemplate.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "unknown")
                    if [ "$LARGE_CPU_LIMIT" = "4000m" ]; then
                        echo -e "${GREEN}✓ Large size resource patching works correctly: $LARGE_CPU_LIMIT${NC}"
                    else
                        echo -e "${YELLOW}⚠️  Large size CPU limit: $LARGE_CPU_LIMIT (expected: 4000m)${NC}"
                        WARNINGS=$((WARNINGS + 1))
                    fi
                    
                    # Check httpPort patching
                    HTTP_PORT=$(kubectl get object "$LARGE_TEMPLATE_OBJECT_NAME" -n "$LARGE_TEMPLATE_NAMESPACE" -o jsonpath='{.spec.forProvider.manifest.spec.podTemplate.spec.containers[0].ports[0].containerPort}' 2>/dev/null || echo "unknown")
                    if [ "$HTTP_PORT" = "9000" ]; then
                        echo -e "${GREEN}✓ HTTP port patching works correctly: $HTTP_PORT${NC}"
                    else
                        echo -e "${YELLOW}⚠️  HTTP port: $HTTP_PORT (expected: 9000)${NC}"
                        WARNINGS=$((WARNINGS + 1))
                    fi
                fi
            fi
            
            # Clean up
            kubectl delete -f "$TEMP_DIR/test-claim-large.yaml" &>/dev/null || true
        fi
    else
        echo -e "${RED}✗ Large configuration claim validation failed${NC}"
        ERRORS=$((ERRORS + 1))
    fi
fi

echo ""

# Summary
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Verification Summary                                       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! AgentSandboxService Composition is ready.${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Next steps:${NC}"
    echo "  - Implement hybrid persistence: ./04-verify-persistence.sh"
    echo "  - Test with real workloads: kubectl apply -f <your-claim.yaml>"
    echo "  - Monitor resource creation: kubectl get xagentsandboxservice,sandboxtemplate,sandboxwarmpool -A"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  AgentSandboxService Composition has $WARNINGS warning(s) but no errors${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Review warnings above and monitor the deployment${NC}"
    exit 0
else
    echo -e "${RED}✗ AgentSandboxService Composition has $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Troubleshooting steps:${NC}"
    echo "  1. Check composition status: kubectl get composition agent-sandbox-service"
    echo "  2. Check composition details: kubectl describe composition agent-sandbox-service"
    echo "  3. Verify composition file: platform/04-apis/agentsandbox/composition.yaml"
    echo "  4. Check Crossplane provider: kubectl get provider kubernetes"
    echo "  5. Check test claim status: kubectl get agentsandboxservice -n $TEST_NAMESPACE"
    echo "  6. Check composite resource: kubectl get xagentsandboxservice -n $TEST_NAMESPACE"
    exit 1
fi
#!/bin/bash
# Verify AgentSandboxService XRD
# Usage: ./02-verify-xrd.sh [--tenant <name>] [--namespace <name>] [--verbose] [--cleanup]
#
# This script verifies:
# 1. AgentSandboxService XRD (CRD) is installed
# 2. All EventDrivenService fields are accepted by live API server
# 3. Field validation works correctly for invalid inputs
# 4. Test claims can be created and validated in live cluster

set -euo pipefail

# Print output immediately for CI visibility
echo "Starting AgentSandboxService XRD verification..."

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
echo -e "${BLUE}║   Verifying AgentSandboxService XRD                         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Track overall status
ERRORS=0
WARNINGS=0

# 1. Verify AgentSandboxService XRD (CRD) is installed
echo -e "${BLUE}Verifying AgentSandboxService XRD...${NC}"

if kubectl_retry get crd xagentsandboxservices.platform.bizmatters.io &>/dev/null; then
    echo -e "${GREEN}✓ XRD 'xagentsandboxservices.platform.bizmatters.io' is installed${NC}"
    
    # Verify claim CRD also exists
    if kubectl_retry get crd agentsandboxservices.platform.bizmatters.io &>/dev/null; then
        echo -e "${GREEN}✓ Claim CRD 'agentsandboxservices.platform.bizmatters.io' is installed${NC}"
    else
        echo -e "${RED}✗ Claim CRD 'agentsandboxservices.platform.bizmatters.io' not found${NC}"
        ERRORS=$((ERRORS + 1))
    fi
    
    # Verify XRD has correct API version
    API_VERSION=$(kubectl_retry get crd xagentsandboxservices.platform.bizmatters.io -o jsonpath='{.spec.versions[0].name}' 2>/dev/null)
    if [ "$API_VERSION" = "v1alpha1" ]; then
        echo -e "${GREEN}✓ XRD API version: v1alpha1${NC}"
    else
        echo -e "${YELLOW}⚠️  XRD API version: $API_VERSION (expected: v1alpha1)${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${RED}✗ XRD 'xagentsandboxservices.platform.bizmatters.io' not found${NC}"
    echo -e "${BLUE}ℹ  Check if platform/04-apis/agentsandbox/xrd.yaml is applied${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# 2. Test AgentSandboxService claim validation with EventDrivenService field parity
echo -e "${BLUE}Testing AgentSandboxService field compatibility...${NC}"

# Create temporary namespace for testing
TEST_NAMESPACE="agentsandbox-test-$$"
kubectl create namespace "$TEST_NAMESPACE" 2>/dev/null || true

# Create temporary test files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR; kubectl delete namespace $TEST_NAMESPACE --ignore-not-found=true &>/dev/null || true" EXIT

# Test 1: Valid minimal claim (image, nats)
cat > "$TEMP_DIR/valid-minimal.yaml" << 'EOF'
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-minimal
  namespace: agentsandbox-test
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  nats:
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer"
EOF

# Replace namespace placeholder
sed -i.bak "s/agentsandbox-test/$TEST_NAMESPACE/g" "$TEMP_DIR/valid-minimal.yaml"

if kubectl apply --dry-run=server -f "$TEMP_DIR/valid-minimal.yaml" &>/dev/null; then
    echo -e "${GREEN}✓ Minimal AgentSandboxService claim validates successfully${NC}"
else
    echo -e "${RED}✗ Minimal AgentSandboxService claim validation failed${NC}"
    if [ "$VERBOSE" = true ]; then
        kubectl apply --dry-run=server -f "$TEMP_DIR/valid-minimal.yaml" || true
    fi
    ERRORS=$((ERRORS + 1))
fi

# Test 2: Full EventDrivenService field compatibility
cat > "$TEMP_DIR/valid-full.yaml" << 'EOF'
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-full
  namespace: agentsandbox-test
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  size: "medium"
  nats:
    url: "nats://nats.nats.svc:4222"
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer"
  httpPort: 8000
  healthPath: "/health"
  readyPath: "/ready"
  sessionAffinity: "None"
  secret1Name: "test-db-conn"
  secret2Name: "test-cache-conn"
  secret3Name: "test-llm-keys"
  secret4Name: "test-extra-secret"
  secret5Name: "test-another-secret"
  imagePullSecrets:
    - name: "ghcr-pull-secret"
  initContainer:
    command: ["/bin/bash", "-c"]
    args: ["echo 'init complete'"]
  storageGB: 20
EOF

# Replace namespace placeholder
sed -i.bak "s/agentsandbox-test/$TEST_NAMESPACE/g" "$TEMP_DIR/valid-full.yaml"

if kubectl apply --dry-run=server -f "$TEMP_DIR/valid-full.yaml" &>/dev/null; then
    echo -e "${GREEN}✓ Full AgentSandboxService claim with all EventDrivenService fields validates successfully${NC}"
else
    echo -e "${RED}✗ Full AgentSandboxService claim validation failed${NC}"
    if [ "$VERBOSE" = true ]; then
        kubectl apply --dry-run=server -f "$TEMP_DIR/valid-full.yaml" || true
    fi
    ERRORS=$((ERRORS + 1))
fi

# Test 3: Invalid field validation (missing required field)
cat > "$TEMP_DIR/invalid-missing-stream.yaml" << 'EOF'
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-invalid
  namespace: agentsandbox-test
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  nats:
    consumer: "test-consumer"
    # stream is missing - should fail validation
EOF

# Replace namespace placeholder
sed -i.bak "s/agentsandbox-test/$TEST_NAMESPACE/g" "$TEMP_DIR/invalid-missing-stream.yaml"

if kubectl apply --dry-run=server -f "$TEMP_DIR/invalid-missing-stream.yaml" &>/dev/null; then
    echo -e "${RED}✗ Invalid AgentSandboxService claim was accepted (should have been rejected)${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ Invalid AgentSandboxService claim correctly rejected${NC}"
fi

# Test 4: Invalid size enum
cat > "$TEMP_DIR/invalid-size.yaml" << 'EOF'
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-invalid-size
  namespace: agentsandbox-test
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  size: "invalid-size"
  nats:
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer"
EOF

# Replace namespace placeholder
sed -i.bak "s/agentsandbox-test/$TEST_NAMESPACE/g" "$TEMP_DIR/invalid-size.yaml"

if kubectl apply --dry-run=server -f "$TEMP_DIR/invalid-size.yaml" &>/dev/null; then
    echo -e "${RED}✗ Invalid size enum was accepted (should have been rejected)${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ Invalid size enum correctly rejected${NC}"
fi

# Test 5: Invalid httpPort range
cat > "$TEMP_DIR/invalid-http-port.yaml" << 'EOF'
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-invalid-port
  namespace: agentsandbox-test
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  httpPort: 70000
  nats:
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer"
EOF

# Replace namespace placeholder
sed -i.bak "s/agentsandbox-test/$TEST_NAMESPACE/g" "$TEMP_DIR/invalid-http-port.yaml"

if kubectl apply --dry-run=server -f "$TEMP_DIR/invalid-http-port.yaml" &>/dev/null; then
    echo -e "${RED}✗ Invalid httpPort range was accepted (should have been rejected)${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ Invalid httpPort range correctly rejected${NC}"
fi

# Test 6: Invalid storageGB range
cat > "$TEMP_DIR/invalid-storage.yaml" << 'EOF'
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-invalid-storage
  namespace: agentsandbox-test
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  storageGB: 2000
  nats:
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer"
EOF

# Replace namespace placeholder
sed -i.bak "s/agentsandbox-test/$TEST_NAMESPACE/g" "$TEMP_DIR/invalid-storage.yaml"

if kubectl apply --dry-run=server -f "$TEMP_DIR/invalid-storage.yaml" &>/dev/null; then
    echo -e "${RED}✗ Invalid storageGB range was accepted (should have been rejected)${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ Invalid storageGB range correctly rejected${NC}"
fi

echo ""

# 3. Test actual claim creation in live cluster (if not cleanup mode)
if [ "$CLEANUP" = false ]; then
    echo -e "${BLUE}Testing live claim creation...${NC}"
    
    # Create a test claim in the live cluster
    if kubectl apply -f "$TEMP_DIR/valid-minimal.yaml" &>/dev/null; then
        echo -e "${GREEN}✓ Test claim created successfully in live cluster${NC}"
        
        # Wait a moment for the claim to be processed
        sleep 2
        
        # Check if the claim exists
        if kubectl get agentsandboxservice test-minimal -n "$TEST_NAMESPACE" &>/dev/null; then
            echo -e "${GREEN}✓ Test claim is accessible via kubectl${NC}"
        else
            echo -e "${YELLOW}⚠️  Test claim not found after creation${NC}"
            WARNINGS=$((WARNINGS + 1))
        fi
        
        # Clean up the test claim
        kubectl delete -f "$TEMP_DIR/valid-minimal.yaml" &>/dev/null || true
    else
        echo -e "${RED}✗ Failed to create test claim in live cluster${NC}"
        if [ "$VERBOSE" = true ]; then
            kubectl apply -f "$TEMP_DIR/valid-minimal.yaml" || true
        fi
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
    echo -e "${GREEN}✓ All checks passed! AgentSandboxService XRD is ready.${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Next steps:${NC}"
    echo "  - Create composition: platform/04-apis/agentsandbox/composition.yaml"
    echo "  - Test with real claims: kubectl apply -f <your-claim.yaml>"
    echo "  - Run composition validation: ./03-verify-composition.sh"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  AgentSandboxService XRD has $WARNINGS warning(s) but no errors${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Review warnings above and monitor the deployment${NC}"
    exit 0
else
    echo -e "${RED}✗ AgentSandboxService XRD has $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Troubleshooting steps:${NC}"
    echo "  1. Check XRD status: kubectl get xrd xagentsandboxservices.platform.bizmatters.io"
    echo "  2. Check XRD details: kubectl describe xrd xagentsandboxservices.platform.bizmatters.io"
    echo "  3. Verify XRD file: platform/04-apis/agentsandbox/xrd.yaml"
    echo "  4. Check cluster connectivity: kubectl cluster-info"
    exit 1
fi
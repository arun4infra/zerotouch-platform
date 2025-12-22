#!/bin/bash
# Comprehensive Platform Compliance Validation Script
# Validates deployed platform standards in Kubernetes environment

# Don't use strict mode - handle errors explicitly for CI compatibility

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Kubectl retry function
kubectl_retry() {
    local max_attempts=20
    local timeout=15
    local attempt=1
    local exitCode=0

    while [ $attempt -le $max_attempts ]; do
        if timeout $timeout kubectl "$@"; then
            return 0
        fi

        exitCode=$?

        if [ $attempt -lt $max_attempts ]; then
            local delay=$((attempt * 2))
            echo -e "${YELLOW}⚠️  kubectl command failed (attempt $attempt/$max_attempts). Retrying in ${delay}s...${NC}" >&2
            sleep $delay
        fi

        attempt=$((attempt + 1))
    done

    echo -e "${RED}✗ kubectl command failed after $max_attempts attempts${NC}" >&2
    return $exitCode
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Platform Standards Compliance Validation                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

ERRORS=0
WARNINGS=0

# Function to log errors
log_error() {
    echo -e "${RED}✗ $1${NC}"
    ((ERRORS++))
}

# Function to log warnings
log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    ((WARNINGS++))
}

# Function to log success
log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# 1. Verify Platform APIs Application is deployed and healthy
echo -e "${BLUE}Verifying Platform APIs deployment...${NC}"

if kubectl_retry get application apis -n argocd &>/dev/null; then
    log_success "ArgoCD Application 'apis' exists"
    
    SYNC_STATUS=$(kubectl_retry get application apis -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
    if [ "$SYNC_STATUS" = "Synced" ]; then
        log_success "Platform APIs are synced via GitOps"
    else
        log_warning "Platform APIs sync status: $SYNC_STATUS (expected: Synced)"
    fi
    
    HEALTH_STATUS=$(kubectl_retry get application apis -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
    if [ "$HEALTH_STATUS" = "Healthy" ]; then
        log_success "Platform APIs are healthy"
    else
        log_warning "Platform APIs health status: $HEALTH_STATUS (expected: Healthy)"
    fi
else
    log_error "ArgoCD Application 'apis' not found"
fi

echo ""

# 2. Verify XRDs are installed with correct versions
echo -e "${BLUE}Verifying XRD installations...${NC}"

# Check EventDrivenService XRD
if kubectl_retry get crd xeventdrivenservices.platform.bizmatters.io &>/dev/null; then
    log_success "EventDrivenService XRD is installed"
    
    API_VERSION=$(kubectl_retry get crd xeventdrivenservices.platform.bizmatters.io -o jsonpath='{.spec.versions[0].name}' 2>/dev/null)
    if [ "$API_VERSION" = "v1alpha1" ]; then
        log_success "EventDrivenService XRD version: v1alpha1"
    else
        log_warning "EventDrivenService XRD version: $API_VERSION (expected: v1alpha1)"
    fi
else
    log_error "EventDrivenService XRD not installed"
fi

# Check WebService XRD
if kubectl_retry get crd xwebservices.platform.bizmatters.io &>/dev/null; then
    log_success "WebService XRD is installed"
    
    API_VERSION=$(kubectl_retry get crd xwebservices.platform.bizmatters.io -o jsonpath='{.spec.versions[0].name}' 2>/dev/null)
    if [ "$API_VERSION" = "v1alpha1" ]; then
        log_success "WebService XRD version: v1alpha1"
    else
        log_warning "WebService XRD version: $API_VERSION (expected: v1alpha1)"
    fi
else
    log_error "WebService XRD not installed"
fi

echo ""

# 3. Verify Compositions are deployed
echo -e "${BLUE}Verifying Composition deployments...${NC}"

if kubectl_retry get composition event-driven-service &>/dev/null; then
    log_success "EventDrivenService Composition is deployed"
    
    # Check composition has correct number of resources
    RESOURCE_COUNT=$(kubectl_retry get composition event-driven-service -o json 2>/dev/null | jq '.spec.resources | length' 2>/dev/null)
    if [ "$RESOURCE_COUNT" -ge "5" ]; then
        log_success "EventDrivenService Composition has $RESOURCE_COUNT resources"
    else
        log_warning "EventDrivenService Composition has $RESOURCE_COUNT resources (expected: >=5)"
    fi
else
    log_error "EventDrivenService Composition not deployed"
fi

if kubectl_retry get composition webservice &>/dev/null; then
    log_success "WebService Composition is deployed"
    
    # Check composition has correct number of resources
    RESOURCE_COUNT=$(kubectl_retry get composition webservice -o json 2>/dev/null | jq '.spec.resources | length' 2>/dev/null)
    if [ "$RESOURCE_COUNT" -ge "6" ]; then
        log_success "WebService Composition has $RESOURCE_COUNT resources"
    else
        log_warning "WebService Composition has $RESOURCE_COUNT resources (expected: >=6)"
    fi
else
    log_error "WebService Composition not deployed"
fi

echo ""

# 4. Test platform compliance by deploying test claims
echo -e "${BLUE}Testing platform compliance with test deployments...${NC}"

# Create test namespace
kubectl create namespace platform-compliance-test --dry-run=client -o yaml | kubectl apply -f - &>/dev/null || true

# Test EventDrivenService deployment with security contexts
cat > /tmp/test-eds.yaml << EOF
apiVersion: platform.bizmatters.io/v1alpha1
kind: EventDrivenService
metadata:
  name: compliance-test-eds
  namespace: platform-compliance-test
spec:
  image: nginx:alpine
  size: micro
  nats:
    url: "nats://nats.nats.svc:4222"
    stream: "TEST_STREAM"
    consumer: "test-consumer"
EOF

if kubectl apply -f /tmp/test-eds.yaml &>/dev/null; then
    log_success "EventDrivenService test deployment created"
    
    # Wait for deployment to be ready
    sleep 10
    
    # Check if deployment has correct security contexts
    if kubectl_retry get deployment compliance-test-eds -n platform-compliance-test -o json 2>/dev/null | jq -e '.spec.template.spec.securityContext.runAsNonRoot == true' &>/dev/null; then
        log_success "EventDrivenService deployment has runAsNonRoot security context"
    else
        log_error "EventDrivenService deployment missing runAsNonRoot security context"
    fi
    
    # Check container security context
    if kubectl_retry get deployment compliance-test-eds -n platform-compliance-test -o json 2>/dev/null | jq -e '.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation == false' &>/dev/null; then
        log_success "EventDrivenService container has allowPrivilegeEscalation: false"
    else
        log_error "EventDrivenService container missing allowPrivilegeEscalation: false"
    fi
    
    # Check observability annotations
    if kubectl_retry get deployment compliance-test-eds -n platform-compliance-test -o json 2>/dev/null | jq -e '.spec.template.metadata.annotations."prometheus.io/scrape" == "true"' &>/dev/null; then
        log_success "EventDrivenService has Prometheus scrape annotation"
    else
        log_error "EventDrivenService missing Prometheus scrape annotation"
    fi
    
    # Check resource allocation
    CPU_REQUEST=$(kubectl_retry get deployment compliance-test-eds -n platform-compliance-test -o json 2>/dev/null | jq -r '.spec.template.spec.containers[0].resources.requests.cpu' 2>/dev/null)
    if [ "$CPU_REQUEST" = "100m" ]; then
        log_success "EventDrivenService micro size has correct CPU request: $CPU_REQUEST"
    else
        log_error "EventDrivenService micro size has incorrect CPU request: $CPU_REQUEST (expected: 100m)"
    fi
    
    # Clean up
    kubectl delete eventdrivenservice compliance-test-eds -n platform-compliance-test &>/dev/null || true
else
    log_error "EventDrivenService test deployment failed"
fi

# Test WebService deployment
cat > /tmp/test-ws.yaml << EOF
apiVersion: platform.bizmatters.io/v1alpha1
kind: WebService
metadata:
  name: compliance-test-ws
  namespace: platform-compliance-test
spec:
  image: nginx:alpine
  port: 8080
  size: micro
EOF

if kubectl apply -f /tmp/test-ws.yaml &>/dev/null; then
    log_success "WebService test deployment created"
    
    # Wait for deployment to be ready
    sleep 10
    
    # Check if deployment has correct security contexts
    if kubectl_retry get deployment compliance-test-ws -n platform-compliance-test -o json 2>/dev/null | jq -e '.spec.template.spec.securityContext.runAsNonRoot == true' &>/dev/null; then
        log_success "WebService deployment has runAsNonRoot security context"
    else
        log_error "WebService deployment missing runAsNonRoot security context"
    fi
    
    # Check resource allocation consistency
    CPU_REQUEST=$(kubectl_retry get deployment compliance-test-ws -n platform-compliance-test -o json 2>/dev/null | jq -r '.spec.template.spec.containers[0].resources.requests.cpu' 2>/dev/null)
    if [ "$CPU_REQUEST" = "100m" ]; then
        log_success "WebService micro size has correct CPU request: $CPU_REQUEST (consistent with EventDrivenService)"
    else
        log_error "WebService micro size has incorrect CPU request: $CPU_REQUEST (expected: 100m for consistency)"
    fi
    
    # Check Service creation
    if kubectl_retry get service compliance-test-ws -n platform-compliance-test &>/dev/null; then
        log_success "WebService Service resource created"
        
        # Check Service has observability annotations
        if kubectl_retry get service compliance-test-ws -n platform-compliance-test -o json 2>/dev/null | jq -e '.metadata.annotations."prometheus.io/scrape" == "true"' &>/dev/null; then
            log_success "WebService Service has Prometheus scrape annotation"
        else
            log_error "WebService Service missing Prometheus scrape annotation"
        fi
    else
        log_error "WebService Service resource not created"
    fi
    
    # Clean up
    kubectl delete webservice compliance-test-ws -n platform-compliance-test &>/dev/null || true
else
    log_error "WebService test deployment failed"
fi

# Clean up test namespace
kubectl delete namespace platform-compliance-test &>/dev/null || true

# Clean up temp files
rm -f /tmp/test-eds.yaml /tmp/test-ws.yaml

echo ""

# 5. Verify ArgoCD sync wave configuration
echo -e "${BLUE}Verifying GitOps deployment configuration...${NC}"

# Check if platform APIs are deployed in correct sync wave
ARGOCD_APP_PATH="$REPO_ROOT/bootstrap/argocd/base/04-apis.yaml"
if [ -f "$ARGOCD_APP_PATH" ]; then
    if grep -q "platform/04-apis" "$ARGOCD_APP_PATH"; then
        log_success "ArgoCD application configured for platform APIs"
    else
        log_error "ArgoCD application not properly configured for platform APIs"
    fi
    
    if grep -q "exclude.*examples" "$ARGOCD_APP_PATH"; then
        log_success "Examples properly excluded from GitOps deployment"
    else
        log_warning "Examples may not be excluded from GitOps deployment"
    fi
else
    log_error "ArgoCD application configuration not found"
fi

echo ""

# Summary
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Platform Compliance Validation Summary                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All platform compliance checks passed!${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Validated components:${NC}"
    echo "  • Platform APIs deployed via GitOps"
    echo "  • XRDs installed with correct versions"
    echo "  • Compositions deployed successfully"
    echo "  • Security contexts enforced consistently"
    echo "  • Observability configuration present"
    echo "  • Resource sizing consistent across XRDs"
    echo ""
    echo -e "${GREEN}Platform standards are enforced consistently across all deployed XRDs.${NC}"
    echo -e "${GREEN}The platform is ready for production workloads.${NC}"
    echo ""
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Platform compliance validation completed with $WARNINGS warning(s)${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Review warnings above and monitor the deployment${NC}"
    exit 0
else
    echo -e "${RED}✗ Platform compliance validation failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Troubleshooting steps:${NC}"
    echo "  1. Check ArgoCD Application: kubectl describe application apis -n argocd"
    echo "  2. Check XRD status: kubectl get xrd"
    echo "  3. Check Compositions: kubectl get compositions"
    echo "  4. Review platform deployment logs"
    exit 1
fi
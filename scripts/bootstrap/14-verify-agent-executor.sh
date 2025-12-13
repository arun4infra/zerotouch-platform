#!/bin/bash

# Script: Verify Agent Executor Deployment
# Usage: ./verify-agent-executor-deployment.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Track overall status
ERRORS=0
WARNINGS=0

# Task 4.6: Verify ApplicationSet
print_header "Task 4.6: Verify ApplicationSet"

if kubectl get applicationset tenant-applications -n argocd &>/dev/null; then
    print_success "ApplicationSet 'tenant-applications' exists"
else
    print_error "ApplicationSet 'tenant-applications' not found"
    print_info "Run: kubectl apply -f bootstrap/components/99-tenants.yaml"
    ((ERRORS++))
fi

if kubectl get application bizmatters-workloads -n argocd &>/dev/null; then
    print_success "Application 'bizmatters-workloads' exists"
    
    SYNC_STATUS=$(kubectl get application bizmatters-workloads -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
    if [ "$SYNC_STATUS" = "Synced" ]; then
        print_success "Application sync status: Synced"
    else
        print_warning "Application sync status: $SYNC_STATUS (expected: Synced)"
        ((WARNINGS++))
    fi
    
    HEALTH_STATUS=$(kubectl get application bizmatters-workloads -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
    if [ "$HEALTH_STATUS" = "Healthy" ]; then
        print_success "Application health status: Healthy"
    else
        print_warning "Application health status: $HEALTH_STATUS (expected: Healthy)"
        ((WARNINGS++))
    fi
else
    print_error "Application 'bizmatters-workloads' not found"
    print_info "Check ApplicationSet logs: kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller"
    ((ERRORS++))
fi

# Task 4.7: Verify Namespace
print_header "Task 4.7: Verify Namespace"

if kubectl get namespace intelligence-deepagents &>/dev/null; then
    print_success "Namespace 'intelligence-deepagents' exists"
    
    LABELS=$(kubectl get namespace intelligence-deepagents -o jsonpath='{.metadata.labels}' 2>/dev/null)
    if echo "$LABELS" | grep -q "layer.*intelligence" && echo "$LABELS" | grep -q "category.*deepagents"; then
        print_success "Namespace has correct labels"
    else
        print_warning "Namespace labels may be incorrect"
        ((WARNINGS++))
    fi
else
    print_error "Namespace 'intelligence-deepagents' not found"
    ((ERRORS++))
fi

# Task 4.8: Verify ExternalSecrets
print_header "Task 4.8: Verify ExternalSecrets"

EXTERNALSECRETS=("agent-executor-llm-keys" "ghcr-pull-secret")
for es in "${EXTERNALSECRETS[@]}"; do
    if kubectl get externalsecret "$es" -n intelligence-deepagents &>/dev/null; then
        print_success "ExternalSecret '$es' exists"
        
        READY=$(kubectl get externalsecret "$es" -n intelligence-deepagents -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [ "$READY" = "True" ]; then
            print_success "ExternalSecret '$es' is Ready"
        else
            print_warning "ExternalSecret '$es' is not Ready"
            ((WARNINGS++))
        fi
        
        # Check if corresponding secret exists
        SECRET_NAME=$(kubectl get externalsecret "$es" -n intelligence-deepagents -o jsonpath='{.spec.target.name}' 2>/dev/null)
        if kubectl get secret "$SECRET_NAME" -n intelligence-deepagents &>/dev/null; then
            print_success "Secret '$SECRET_NAME' created by ESO"
        else
            print_error "Secret '$SECRET_NAME' not found"
            ((ERRORS++))
        fi
    else
        print_error "ExternalSecret '$es' not found"
        ((ERRORS++))
    fi
done

# Task 4.8: Verify Crossplane Secrets
print_header "Task 4.8: Verify Crossplane-Generated Secrets"

CROSSPLANE_SECRETS=("agent-executor-db-conn" "agent-executor-cache-conn")
for secret in "${CROSSPLANE_SECRETS[@]}"; do
    if kubectl get secret "$secret" -n intelligence-deepagents &>/dev/null; then
        print_success "Crossplane secret '$secret' exists"
        
        # Verify secret keys
        if [ "$secret" = "agent-executor-db-conn" ]; then
            KEYS=$(kubectl get secret "$secret" -n intelligence-deepagents -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys[]' 2>/dev/null)
            if echo "$KEYS" | grep -q "endpoint" && echo "$KEYS" | grep -q "password"; then
                print_success "Secret '$secret' has correct keys"
            else
                print_warning "Secret '$secret' may be missing keys"
                ((WARNINGS++))
            fi
        fi
    else
        print_error "Crossplane secret '$secret' not found"
        print_info "Check Crossplane claims: kubectl get postgresinstance,dragonflyinstance -n intelligence-deepagents"
        ((ERRORS++))
    fi
done

# Task 4.9: Verify NATS Stream
print_header "Task 4.9: Verify NATS Stream"

if kubectl get job create-agent-execution-stream -n intelligence-deepagents &>/dev/null; then
    print_success "NATS stream Job exists"
    
    COMPLETIONS=$(kubectl get job create-agent-execution-stream -n intelligence-deepagents -o jsonpath='{.status.succeeded}' 2>/dev/null)
    if [ "$COMPLETIONS" = "1" ]; then
        print_success "NATS stream Job completed successfully"
    else
        print_warning "NATS stream Job not completed (succeeded: $COMPLETIONS)"
        ((WARNINGS++))
    fi
else
    print_error "NATS stream Job not found"
    ((ERRORS++))
fi

# Task 4.10: Verify Deployment
print_header "Task 4.10: Verify Deployment"

if kubectl get deployment agent-executor -n intelligence-deepagents &>/dev/null; then
    print_success "Deployment 'agent-executor' exists"
    
    READY_REPLICAS=$(kubectl get deployment agent-executor -n intelligence-deepagents -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    DESIRED_REPLICAS=$(kubectl get deployment agent-executor -n intelligence-deepagents -o jsonpath='{.spec.replicas}' 2>/dev/null)
    
    if [ "$READY_REPLICAS" = "$DESIRED_REPLICAS" ] && [ "$READY_REPLICAS" != "" ]; then
        print_success "Deployment ready: $READY_REPLICAS/$DESIRED_REPLICAS replicas"
    else
        print_warning "Deployment not ready: $READY_REPLICAS/$DESIRED_REPLICAS replicas"
        ((WARNINGS++))
    fi
else
    print_error "Deployment 'agent-executor' not found"
    ((ERRORS++))
fi

# Task 4.11: Verify Service
print_header "Task 4.11: Verify Service"

if kubectl get service agent-executor -n intelligence-deepagents &>/dev/null; then
    print_success "Service 'agent-executor' exists"
    
    SERVICE_TYPE=$(kubectl get service agent-executor -n intelligence-deepagents -o jsonpath='{.spec.type}' 2>/dev/null)
    if [ "$SERVICE_TYPE" = "ClusterIP" ]; then
        print_success "Service type: ClusterIP"
    else
        print_warning "Service type: $SERVICE_TYPE (expected: ClusterIP)"
        ((WARNINGS++))
    fi
else
    print_error "Service 'agent-executor' not found"
    ((ERRORS++))
fi

# Task 4.12: Verify KEDA ScaledObject
print_header "Task 4.12: Verify KEDA ScaledObject"

if kubectl get scaledobject agent-executor-scaler -n intelligence-deepagents &>/dev/null; then
    print_success "ScaledObject 'agent-executor-scaler' exists"
else
    print_error "ScaledObject 'agent-executor-scaler' not found"
    ((ERRORS++))
fi

# Task 4.13: Verify Pods
print_header "Task 4.13: Verify Pods"

POD_COUNT=$(kubectl get pods -n intelligence-deepagents -l app=agent-executor --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$POD_COUNT" -gt 0 ]; then
    print_success "Found $POD_COUNT agent-executor pod(s)"
    
    RUNNING_PODS=$(kubectl get pods -n intelligence-deepagents -l app=agent-executor --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$RUNNING_PODS" = "$POD_COUNT" ]; then
        print_success "All pods are Running"
    else
        print_warning "$RUNNING_PODS/$POD_COUNT pods are Running"
        ((WARNINGS++))
    fi
    
    # Check pod logs for startup message
    POD_NAME=$(kubectl get pods -n intelligence-deepagents -l app=agent-executor -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$POD_NAME" ]; then
        if kubectl logs "$POD_NAME" -n intelligence-deepagents -c agent-executor --tail=50 2>/dev/null | grep -q "readiness_check_passed"; then
            print_success "Pod logs show service is ready"
        else
            print_warning "Readiness check message not found in logs"
            ((WARNINGS++))
        fi
    fi
else
    print_error "No agent-executor pods found"
    ((ERRORS++))
fi

# Summary
print_header "Verification Summary"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    print_success "All checks passed! Deployment is healthy."
    echo ""
    print_info "Next steps:"
    echo "  - Test health endpoints (Task 4.14)"
    echo "  - Test message processing (Task 4.15)"
    echo "  - Test KEDA autoscaling (Task 4.16)"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    print_warning "Deployment has $WARNINGS warning(s) but no errors"
    echo ""
    print_info "Review warnings above and monitor the deployment"
    exit 0
else
    print_error "Deployment has $ERRORS error(s) and $WARNINGS warning(s)"
    echo ""
    print_info "Troubleshooting steps:"
    echo "  1. Check ArgoCD Application: kubectl describe application bizmatters-workloads -n argocd"
    echo "  2. Check pod events: kubectl get events -n intelligence-deepagents --sort-by='.lastTimestamp'"
    echo "  3. Check pod logs: kubectl logs -n intelligence-deepagents <pod-name> -c agent-executor"
    echo "  4. Review DEPLOYMENT_GUIDE.md troubleshooting section"
    exit 1
fi

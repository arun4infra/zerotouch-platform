#!/bin/bash
set -euo pipefail

# Platform Dependency Validation Script
# Validates that all required platform dependencies are available and healthy

echo "🔍 Validating platform dependencies..."

# Required platform services
DEPENDENCIES=(
    "cnpg-system:cnpg-cloudnative-pg:CloudNative PostgreSQL Operator"
    "external-secrets:external-secrets:External Secrets Operator"
    "intelligence-deepagents:deepagents-runtime:DeepAgents Runtime Service"
    "argocd:argocd-server:ArgoCD Server"
)

# Function to check if a deployment is ready
check_deployment() {
    local namespace="$1"
    local deployment="$2"
    local description="$3"
    
    echo "🔍 Checking ${description}..."
    
    if ! kubectl get deployment "${deployment}" -n "${namespace}" &>/dev/null; then
        echo "❌ ${description} deployment not found in namespace ${namespace}"
        return 1
    fi
    
    local ready_replicas
    local desired_replicas
    ready_replicas=$(kubectl get deployment "${deployment}" -n "${namespace}" -o jsonpath='{.status.readyReplicas}' || echo "0")
    desired_replicas=$(kubectl get deployment "${deployment}" -n "${namespace}" -o jsonpath='{.spec.replicas}' || echo "1")
    
    if [[ "${ready_replicas}" == "${desired_replicas}" ]] && [[ "${ready_replicas}" -gt 0 ]]; then
        echo "✅ ${description} is ready (${ready_replicas}/${desired_replicas})"
        return 0
    else
        echo "❌ ${description} is not ready (${ready_replicas}/${desired_replicas})"
        return 1
    fi
}

# Function to check if a service is accessible
check_service() {
    local namespace="$1"
    local service="$2"
    local description="$3"
    
    echo "🔍 Checking ${description} service..."
    
    if ! kubectl get service "${service}" -n "${namespace}" &>/dev/null; then
        echo "❌ ${description} service not found in namespace ${namespace}"
        return 1
    fi
    
    local cluster_ip
    cluster_ip=$(kubectl get service "${service}" -n "${namespace}" -o jsonpath='{.spec.clusterIP}')
    
    if [[ -n "${cluster_ip}" && "${cluster_ip}" != "None" ]]; then
        echo "✅ ${description} service is available at ${cluster_ip}"
        return 0
    else
        echo "❌ ${description} service has no cluster IP"
        return 1
    fi
}

# Check all dependencies
failed_checks=0

for dep in "${DEPENDENCIES[@]}"; do
    IFS=':' read -r namespace deployment description <<< "${dep}"
    
    if ! check_deployment "${namespace}" "${deployment}" "${description}"; then
        ((failed_checks++))
    fi
    
    # Also check service if it exists
    if kubectl get service "${deployment}" -n "${namespace}" &>/dev/null; then
        if ! check_service "${namespace}" "${deployment}" "${description}"; then
            ((failed_checks++))
        fi
    fi
done

# Check cluster-wide resources
echo "🔍 Checking cluster-wide resources..."

# Check storage classes
if kubectl get storageclass &>/dev/null; then
    storage_classes=$(kubectl get storageclass --no-headers | wc -l)
    echo "✅ Found ${storage_classes} storage class(es)"
else
    echo "❌ No storage classes found"
    ((failed_checks++))
fi

# Check metrics server
if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
    echo "✅ Metrics server is available"
else
    echo "⚠️  Metrics server not found (optional)"
fi

# Check ingress controller
if kubectl get deployment -A -l app.kubernetes.io/name=ingress-nginx &>/dev/null; then
    echo "✅ Ingress controller is available"
else
    echo "⚠️  Ingress controller not found (may be optional)"
fi

# Check DNS
echo "🔍 Checking DNS resolution..."
if kubectl run dns-test --image=busybox:1.28 --rm -i --restart=Never --timeout=30s -- nslookup kubernetes.default.svc.cluster.local &>/dev/null; then
    echo "✅ DNS resolution is working"
else
    echo "❌ DNS resolution failed"
    ((failed_checks++))
fi

# Check RBAC
echo "🔍 Checking RBAC permissions..."
if kubectl auth can-i create pods --as=system:serviceaccount:intelligence-orchestrator:ide-orchestrator &>/dev/null; then
    echo "✅ RBAC permissions are configured"
else
    echo "⚠️  RBAC permissions may need configuration"
fi

# Summary
echo ""
echo "📊 Platform Dependency Validation Summary:"
echo "=========================================="

if [[ ${failed_checks} -eq 0 ]]; then
    echo "✅ All platform dependencies are healthy and ready"
    echo "🚀 Platform is ready for ide-orchestrator deployment"
    exit 0
else
    echo "❌ ${failed_checks} dependency check(s) failed"
    echo "🔧 Please resolve the failed dependencies before proceeding"
    exit 1
fi
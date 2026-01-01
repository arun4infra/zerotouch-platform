#!/bin/bash
set -euo pipefail

# ==============================================================================
# CI Deploy Script
# ==============================================================================
# Purpose: GitOps service deployment automation
# 
# IMPORTANT: Preview vs Production Namespace Handling
# - Production: Namespaces created by tenant-infrastructure (ArgoCD app)  
# - Preview: Namespaces created by this CI script (mocks landing zones)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT should point to where the service code is checked out
# In CI workflows, service code is checked out to 'service-code' subdirectory
# The deploy script is called from service-code directory, so PROJECT_ROOT is current dir
PROJECT_ROOT="$(pwd)"

# Set PLATFORM_ROOT if not already set
if [[ -z "${PLATFORM_ROOT:-}" ]]; then
    PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
fi

# Load service configuration from ci/config.yaml
load_service_config() {
    local config_file="${SERVICE_ROOT:-$(pwd)}/ci/config.yaml"
    
    if [[ ! -f "$config_file" ]]; then
        echo "❌ Service config not found: $config_file"
        echo "🔍 Debug: Current directory: $(pwd)"
        echo "🔍 Debug: Looking for config at: $config_file"
        exit 1
    fi
    
    if command -v yq &> /dev/null; then
        SERVICE_NAME=$(yq eval '.service.name' "$config_file")
        NAMESPACE=$(yq eval '.service.namespace' "$config_file")
    else
        echo "❌ yq is required but not installed"
        exit 1
    fi
    
    if [[ -z "$SERVICE_NAME" || -z "$NAMESPACE" ]]; then
        echo "❌ service.name and service.namespace are required in ci/config.yaml"
        exit 1
    fi
}

# Load configuration
load_service_config

# Default values
ENVIRONMENT="${1:-ci}"
IMAGE_TAG="${2:-latest}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-300}"

echo "🚀 Deploying ${SERVICE_NAME} to ${ENVIRONMENT} environment..."

cd "${PROJECT_ROOT}"

# Validate environment
case "${ENVIRONMENT}" in
    ci|staging|production)
        echo "✅ Valid environment: ${ENVIRONMENT}"
        ;;
    *)
        echo "❌ Invalid environment: ${ENVIRONMENT}. Must be ci, staging, or production"
        exit 1
        ;;
esac

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check cluster connectivity
echo "🔍 Checking cluster connectivity..."
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster"
    exit 1
fi

# Mock Landing Zone (Preview Mode Only)
# In Production, tenant-infrastructure creates namespaces
# In Preview, CI must simulate this behavior
echo "📁 Setting up landing zone for preview mode..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Mock landing zone '${NAMESPACE}' created"

# Apply platform claims and manifests
echo "📋 Applying platform claims..."
echo "🔍 Checking for platform claims in: ${PROJECT_ROOT}/platform/claims/${NAMESPACE}"
USING_PLATFORM_CLAIMS=false
if [[ -d "${PROJECT_ROOT}/platform/claims/${NAMESPACE}" ]]; then
    echo "✅ Found platform claims directory"
    USING_PLATFORM_CLAIMS=true
    # Apply platform claims for the namespace (recursive to include subdirectories)
    kubectl apply -f "${PROJECT_ROOT}/platform/claims/${NAMESPACE}/" -n "${NAMESPACE}" --recursive
    echo "✅ Platform claims applied"
    
    # Wait for infrastructure dependencies using dedicated script
    INFRA_WAIT_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/wait-for-database-and-secrets.sh"
    if [[ -f "$INFRA_WAIT_SCRIPT" ]]; then
        chmod +x "$INFRA_WAIT_SCRIPT"
        # Ensure we exit if the wait script fails
        if ! "$INFRA_WAIT_SCRIPT" "${SERVICE_NAME}" "${NAMESPACE}"; then
            echo "❌ ERROR: Infrastructure dependencies failed to become ready"
            exit 1
        fi
    else
        echo "❌ Database and secrets wait script not found: $INFRA_WAIT_SCRIPT"
        exit 1
    fi
    
    # Use platform's generalized wait script for Platform Services (EventDrivenService or WebService)
    WAIT_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/wait/wait-for-platform-service.sh"
    if [[ -f "$WAIT_SCRIPT" ]]; then
        chmod +x "$WAIT_SCRIPT"
        "$WAIT_SCRIPT" "${SERVICE_NAME}" "${NAMESPACE}" "${WAIT_TIMEOUT}"
    else
        echo "❌ Platform service wait script not found: $WAIT_SCRIPT"
        exit 1
    fi
elif [[ -d "k8s/${ENVIRONMENT}" ]]; then
    # Environment-specific manifests (fallback)
    kubectl apply -f "k8s/${ENVIRONMENT}/" -n "${NAMESPACE}"
elif [[ -d "k8s/base" ]]; then
    # Base manifests with kustomization (fallback)
    kubectl apply -k "k8s/base" -n "${NAMESPACE}"
else
    echo "❌ No platform claims found in ${PROJECT_ROOT}/platform/claims/${NAMESPACE} or k8s manifests"
    echo "🔍 Debug: Current directory: $(pwd)"
    echo "🔍 Debug: PROJECT_ROOT: ${PROJECT_ROOT}"
    echo "🔍 Debug: Listing ${PROJECT_ROOT}/platform/claims/:"
    ls -la "${PROJECT_ROOT}/platform/claims/" || echo "Directory not found"
    exit 1
fi

# Always update image tag with what CI provides
echo "🏷️  Updating all image references to ${IMAGE_TAG}..."

if [[ "${USING_PLATFORM_CLAIMS}" == "true" ]]; then
    # Force replace ALL image references in platform claims with CI-provided tag
    echo "🔧 Updating images in platform claims..."
    find "${PROJECT_ROOT}/platform/claims/${NAMESPACE}/" -name "*.yaml" -type f | while read -r file; do
        echo "  Processing: $file"
        # Replace any image reference with the CI-built tag
        sed -i.bak "s|image: .*|image: ${IMAGE_TAG}|g" "$file"
        rm -f "${file}.bak"
    done
else
    # Update deployment directly for non-platform-claims
    kubectl set image deployment/${SERVICE_NAME} \
        ${SERVICE_NAME}="${IMAGE_TAG}" \
        -n "${NAMESPACE}"
fi

# Wait for deployment to be ready (only for non-platform-claims deployments)
if [[ "${USING_PLATFORM_CLAIMS}" == "false" ]]; then
    echo "⏳ Waiting for deployment to be ready..."
    kubectl rollout status deployment/${SERVICE_NAME} \
        -n "${NAMESPACE}" \
        --timeout="${WAIT_TIMEOUT}s"

    # Verify deployment
    echo "🔍 Verifying deployment..."
    READY_REPLICAS=$(kubectl get deployment ${SERVICE_NAME} -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}')
    DESIRED_REPLICAS=$(kubectl get deployment ${SERVICE_NAME} -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')

    if [[ "${READY_REPLICAS}" == "${DESIRED_REPLICAS}" ]]; then
        echo "✅ Deployment successful: ${READY_REPLICAS}/${DESIRED_REPLICAS} replicas ready"
    else
        echo "❌ Deployment failed: ${READY_REPLICAS}/${DESIRED_REPLICAS} replicas ready"
        exit 1
    fi

    # Show service endpoints
    echo "🌐 Service endpoints:"
    kubectl get services -n "${NAMESPACE}" -l app=${SERVICE_NAME}
else
    echo "✅ Platform service deployment completed (verified by wait script)"
fi

echo "🎉 Deployment completed successfully!"
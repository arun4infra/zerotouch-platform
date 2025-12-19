#!/bin/bash
# Collect logs for debugging failed integration tests
# Usage: ./scripts/local-ci/collect-logs.sh [output-directory]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-$SCRIPT_DIR/logs}"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}==>${NC} $1"
}

echo ""
echo "=== Collecting logs for debugging ==="
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"
log_info "Collecting logs to: $OUTPUT_DIR"

# Function to safely collect logs
collect_logs() {
    local namespace=$1
    local selector=$2
    local name=$3
    local output_file="$OUTPUT_DIR/${name}-${TIMESTAMP}.log"
    
    log_info "Collecting $name logs..."
    if kubectl get pods -n "$namespace" -l "$selector" --no-headers 2>/dev/null | grep -q .; then
        kubectl logs -n "$namespace" -l "$selector" --tail=200 > "$output_file" 2>&1 || {
            echo "Failed to collect logs for $name" > "$output_file"
        }
        log_info "✓ $name logs saved to: $output_file"
    else
        echo "No pods found for $name" > "$output_file"
        log_warn "No pods found for $name"
    fi
}

# Function to collect pod descriptions
collect_pod_descriptions() {
    local namespace=$1
    local name=$2
    local output_file="$OUTPUT_DIR/${name}-pods-${TIMESTAMP}.yaml"
    
    log_info "Collecting $name pod descriptions..."
    kubectl get pods -n "$namespace" -o yaml > "$output_file" 2>&1 || {
        echo "Failed to collect pod descriptions for $name" > "$output_file"
    }
    log_info "✓ $name pod descriptions saved to: $output_file"
}

# Collect ArgoCD logs
collect_logs "argocd" "app.kubernetes.io/name=argocd-application-controller" "argocd-application-controller"
collect_logs "argocd" "app.kubernetes.io/name=argocd-server" "argocd-server"
collect_logs "argocd" "app.kubernetes.io/name=argocd-repo-server" "argocd-repo-server"

# Collect External Secrets Operator logs
collect_logs "external-secrets" "app.kubernetes.io/name=external-secrets" "external-secrets-operator"

# Collect Crossplane logs
collect_logs "crossplane-system" "app=crossplane" "crossplane"

# Collect KEDA logs
collect_logs "keda" "app.kubernetes.io/name=keda-operator" "keda-operator"

# Collect NATS logs
collect_logs "nats" "app.kubernetes.io/name=nats" "nats"

# Collect Kagent logs
collect_logs "kagent" "app.kubernetes.io/name=kagent" "kagent"

# Collect Intelligence layer logs
collect_logs "intelligence" "" "intelligence-all"

# Collect cluster state
log_info "Collecting cluster state..."

# ArgoCD Applications
kubectl get applications -n argocd -o yaml > "$OUTPUT_DIR/argocd-applications-${TIMESTAMP}.yaml" 2>&1 || true

# All pods
kubectl get pods -A -o wide > "$OUTPUT_DIR/all-pods-${TIMESTAMP}.txt" 2>&1 || true

# Failed pods
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded -o yaml > "$OUTPUT_DIR/failed-pods-${TIMESTAMP}.yaml" 2>&1 || true

# Events
kubectl get events -A --sort-by='.lastTimestamp' > "$OUTPUT_DIR/events-${TIMESTAMP}.txt" 2>&1 || true

# Nodes
kubectl get nodes -o yaml > "$OUTPUT_DIR/nodes-${TIMESTAMP}.yaml" 2>&1 || true

# Persistent Volumes
kubectl get pv,pvc -A -o yaml > "$OUTPUT_DIR/storage-${TIMESTAMP}.yaml" 2>&1 || true

# Services and Ingress
kubectl get svc,ingress -A -o yaml > "$OUTPUT_DIR/networking-${TIMESTAMP}.yaml" 2>&1 || true

# ConfigMaps and Secrets (names only for security)
kubectl get configmaps,secrets -A > "$OUTPUT_DIR/configs-secrets-list-${TIMESTAMP}.txt" 2>&1 || true

# Custom Resources
log_info "Collecting custom resources..."
kubectl get crd -o name | while read -r crd; do
    crd_name=$(echo "$crd" | cut -d'/' -f2)
    kubectl get "$crd" -A -o yaml > "$OUTPUT_DIR/crd-${crd_name}-${TIMESTAMP}.yaml" 2>&1 || true
done

# Docker/Kind specific information
if command -v docker >/dev/null 2>&1; then
    log_info "Collecting Docker/Kind information..."
    docker ps --filter "name=zerotouch-preview" > "$OUTPUT_DIR/docker-containers-${TIMESTAMP}.txt" 2>&1 || true
    
    # Get Kind cluster info
    if command -v kind >/dev/null 2>&1; then
        kind get clusters > "$OUTPUT_DIR/kind-clusters-${TIMESTAMP}.txt" 2>&1 || true
    fi
fi

# Create a summary file
cat > "$OUTPUT_DIR/README-${TIMESTAMP}.txt" << EOF
Integration Test Debug Logs
===========================

Collected at: $(date)
Directory: $OUTPUT_DIR

Files:
- *-controller.log: Application controller logs
- *-pods.yaml: Pod descriptions
- argocd-applications.yaml: ArgoCD application states
- all-pods.txt: All pod status
- failed-pods.yaml: Failed pod details
- events.txt: Kubernetes events
- nodes.yaml: Node information
- storage.yaml: PV/PVC information
- networking.yaml: Services and Ingress
- configs-secrets-list.txt: ConfigMap and Secret names
- crd-*.yaml: Custom resource instances
- docker-containers.txt: Docker container status
- kind-clusters.txt: Kind cluster information

Common Issues:
1. Check failed-pods.yaml for pod startup issues
2. Check events.txt for recent cluster events
3. Check argocd-application-controller.log for sync issues
4. Check external-secrets-operator.log for secret issues
5. Check argocd-applications.yaml for application status

EOF

echo ""
log_info "✓ Log collection completed"
log_info "Debug information saved to: $OUTPUT_DIR"
echo ""
echo "Next steps:"
echo "1. Review the README file: $OUTPUT_DIR/README-${TIMESTAMP}.txt"
echo "2. Check failed pods: $OUTPUT_DIR/failed-pods-${TIMESTAMP}.yaml"
echo "3. Review events: $OUTPUT_DIR/events-${TIMESTAMP}.txt"
echo ""
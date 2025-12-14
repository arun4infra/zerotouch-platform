#!/bin/bash
# Pre-create NATS Application with correct storage class for preview mode
# This prevents ArgoCD from creating it with wrong values from cached/stale source
#
# Usage: ./precreate-nats-preview.sh
#
# This script should be called AFTER ArgoCD is installed but BEFORE platform-bootstrap syncs

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Pre-creating NATS Application for Preview Mode            ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Wait for ArgoCD to be ready
echo -e "${BLUE}Waiting for ArgoCD server to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s 2>/dev/null || {
    echo -e "${YELLOW}⚠ ArgoCD server not ready, continuing anyway...${NC}"
}

# Check if NATS Application already exists
if kubectl get application nats -n argocd &>/dev/null; then
    CURRENT_SC=$(kubectl get application nats -n argocd -o jsonpath='{.spec.source.helm.valuesObject.config.jetstream.fileStore.pvc.storageClassName}' 2>/dev/null || echo "")
    echo -e "${BLUE}NATS Application already exists with storageClassName: ${CURRENT_SC:-not set}${NC}"
    
    if [ "$CURRENT_SC" = "standard" ]; then
        echo -e "${GREEN}✓ NATS Application already has correct storage class${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ NATS Application has wrong storage class, will patch it${NC}"
        
        # Delete existing NATS resources if they have wrong storage class
        if kubectl get pvc nats-js-nats-0 -n nats &>/dev/null; then
            NATS_PVC_SC=$(kubectl get pvc nats-js-nats-0 -n nats -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo "")
            if [ "$NATS_PVC_SC" = "local-path" ]; then
                echo -e "${BLUE}Deleting NATS namespace to clean up wrong PVC...${NC}"
                kubectl delete namespace nats --wait=false 2>/dev/null || true
                for i in {1..30}; do
                    if ! kubectl get namespace nats &>/dev/null; then
                        echo -e "${GREEN}✓ NATS namespace deleted${NC}"
                        break
                    fi
                    sleep 1
                done
            fi
        fi
        
        # Delete the application so we can recreate it
        kubectl delete application nats -n argocd --wait=true 2>/dev/null || true
    fi
fi

# Apply NATS Application with correct storage class
echo -e "${BLUE}Creating NATS Application with storageClassName: standard...${NC}"

cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nats
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
  labels:
    app.kubernetes.io/instance: platform-bootstrap
spec:
  project: default
  source:
    chart: nats
    repoURL: https://nats-io.github.io/k8s/helm/charts/
    targetRevision: 1.2.6
    helm:
      valuesObject:
        config:
          jetstream:
            enabled: true
            fileStore:
              enabled: true
              dir: /data
              maxSize: 10Gi
              pvc:
                enabled: true
                size: 10Gi
                storageClassName: standard
            memoryStore:
              enabled: true
              maxSize: 1Gi
          cluster:
            enabled: false
        container:
          image:
            repository: nats
            tag: 2.10.22-alpine
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 1Gi
        natsBox:
          enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: nats
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  ignoreDifferences:
    - group: apps
      kind: StatefulSet
      name: nats
      jqPathExpressions:
        - .spec.volumeClaimTemplates[]?.metadata.creationTimestamp
        - .spec.volumeClaimTemplates[]?.status
        - .spec.volumeClaimTemplates[]?.spec.storageClassName
EOF

# Verify
NEW_SC=$(kubectl get application nats -n argocd -o jsonpath='{.spec.source.helm.valuesObject.config.jetstream.fileStore.pvc.storageClassName}' 2>/dev/null || echo "")
echo -e "${GREEN}✓ NATS Application created with storageClassName: ${NEW_SC}${NC}"

exit 0

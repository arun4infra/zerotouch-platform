# Platform Testing Guide

## Overview

`01-master-bootstrap.sh` supports two modes:
- **Production**: Installs Talos OS on bare metal
- **Preview**: Creates Kind cluster for CI/CD testing

## Preview Mode Usage

```bash
./scripts/bootstrap/01-master-bootstrap.sh --mode preview
```

**Prerequisites**: Set AWS credentials as environment variables
```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."  # Optional
```

**What it does**:
1. Installs kubectl, helm, kind (if missing)
2. Creates Kind cluster (`zerotouch-preview`)
3. Bootstraps platform via existing scripts
4. ArgoCD auto-deploys: Crossplane, ESO, CNPG, NATS, KEDA, XRDs, Compositions

**Cleanup**:
```bash
./scripts/bootstrap/cleanup-preview.sh
```

## GitHub Actions Pattern

```yaml
steps:
  - name: Checkout service
    uses: actions/checkout@v4
    with:
      path: my-service
  
  - name: Clone platform
    uses: actions/checkout@v4
    with:
      repository: org/zerotouch-platform
      ref: main
      path: zerotouch-platform
  
  - name: Configure AWS
    uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      aws-region: ap-south-1
  
  - name: Export AWS credentials
    run: |
      echo "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" >> $GITHUB_ENV
      echo "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" >> $GITHUB_ENV
      echo "AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN" >> $GITHUB_ENV
  
  - name: Bootstrap platform
    working-directory: zerotouch-platform
    run: ./scripts/bootstrap/01-master-bootstrap.sh --mode preview
  
  - name: Deploy and test
    working-directory: my-service
    run: |
      kubectl apply -f platform/claims/
      kubectl wait --for=condition=Ready xeventdrivenservice/my-service --timeout=300s
      ./scripts/ci/run-tests.sh
  
  - name: Cleanup
    if: always()
    working-directory: zerotouch-platform
    run: ./scripts/bootstrap/cleanup-preview.sh
```

## Deployed Components

**Foundation**: Crossplane, ESO, CNPG, NATS, KEDA
**APIs**: PostgresInstance, DragonflyInstance, EventDrivenService XRDs + Compositions
**Config**: AWS ClusterSecretStore, ProviderConfig, NATS streams

## Troubleshooting

```bash
# Check status
kubectl get applications -n argocd
kubectl get pods -n crossplane-system
kubectl get xrd

# View logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
kubectl logs -n crossplane-system -l app=crossplane

# Common issues
# - ArgoCD stuck: Wait 5-10 min for initial sync
# - ESO not ready: Check AWS credentials in external-secrets namespace
# - Claims failing: Verify XRDs established and compositions exist
```

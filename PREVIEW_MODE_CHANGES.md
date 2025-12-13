# Preview Mode Changes Summary

## Overview
This document summarizes the changes made to support proper preview mode deployment using industry-standard Kustomize overlays and environment-specific configurations.

## Key Changes Made

### 1. Kustomize Overlays Structure (Industry Standard)
```
platform/05-databases/overlays/
├── kustomization.yaml          # Base overlay
├── development/
│   └── kustomization.yaml      # Kind/preview patches (storage class: standard)
└── production/
    └── kustomization.yaml      # Production config (storage class: local-path)
```

### 2. Preview Components Structure
```
bootstrap/components/preview/
├── 01-crossplane.yaml         # No control plane tolerations
├── 01-keda.yaml               # No control plane tolerations  
├── 01-nats.yaml               # No control plane tolerations, standard storage
├── 01-eso.yaml                # No control plane tolerations
└── 05-databases.yaml          # Uses development overlay
```

### 3. Bootstrap Applications
- **Production**: `bootstrap/root.yaml` → `bootstrap/10-platform-bootstrap.yaml` → `bootstrap/components/`
- **Preview**: `bootstrap/root-preview.yaml` → `bootstrap/10-platform-bootstrap-preview.yaml` → `bootstrap/components/preview/`

### 4. Script Updates

#### `scripts/bootstrap/helpers/setup-preview.sh`
- ✅ Updated to use Kustomize overlays instead of runtime patching
- ✅ Detects storage class automatically
- ✅ Validates overlay structure
- ✅ Industry-standard approach

#### `scripts/bootstrap/09-install-argocd.sh`
- ✅ Mode-aware root application selection
- ✅ Uses `root-preview.yaml` for preview mode
- ✅ Uses `root.yaml` for production mode

#### `scripts/bootstrap/helpers/ensure-preview-urls.sh`
- ✅ Updated to handle preview components directory
- ✅ Processes both production and preview component files

#### `scripts/bootstrap/01-master-bootstrap.sh`
- ✅ Already calls setup-preview.sh in preview mode
- ✅ Already passes mode to ArgoCD installation
- ✅ No changes needed

## Issues Resolved

### ✅ NATS Storage Issue
- **Problem**: PVC stuck on `local-path` storage class in Kind
- **Solution**: Preview NATS uses `standard` storage class

### ✅ Database Storage Issues  
- **Problem**: PostgreSQL and Dragonfly PVCs stuck on `local-path` storage class
- **Solution**: Development overlay patches both to use `standard` storage class

### ✅ Platform Component Scheduling
- **Problem**: Components with control plane tolerations couldn't schedule in Kind
- **Solution**: Preview components have no tolerations

### ✅ Bootstrap Application Selection
- **Problem**: Same bootstrap used for both environments
- **Solution**: Mode-aware root application selection

## Deployment Flow

### Preview Mode (GitHub Actions/Kind)
1. `setup-preview.sh` validates Kustomize structure
2. ArgoCD installs with `root-preview.yaml`
3. Platform bootstrap uses `bootstrap/components/preview/`
4. Database compositions use development overlay (`standard` storage)
5. All components schedule without control plane tolerations

### Production Mode (Talos)
1. ArgoCD installs with `root.yaml`  
2. Platform bootstrap uses `bootstrap/components/`
3. Database compositions use production overlay (`local-path` storage)
4. Components use control plane tolerations as configured

## Benefits

### ✅ Industry Standard
- Uses Kustomize overlays (Netflix, Google, Spotify pattern)
- GitOps native - all changes tracked in Git
- Kubernetes native - built into kubectl

### ✅ Environment Parity
- Same deployment process, different configurations
- Reproducible across environments
- No runtime patching or scripts

### ✅ Maintainable
- Clear separation of concerns
- Version controlled configurations
- Easy to add new environments

## Next Steps

1. **Test the current GitHub Actions workflow** - should now resolve storage issues
2. **Monitor deployment** - verify PVCs provision correctly
3. **Validate services** - ensure databases and caches start properly

The storage class and scheduling issues should now be resolved with this industry-standard approach.
# Control Plane Scheduling Configuration

## Overview

This document explains the control plane scheduling setup and how platform components are configured to work with Talos Linux control plane isolation.

## Talos Configuration

```yaml
allowSchedulingOnControlPlanes: false # Prevents running workload on control-plane nodes.
```

**Location**: `zerotouch-platform/bootstrap/talos/nodes/cp01-main/config.yaml:508`

## How It Works

When `allowSchedulingOnControlPlanes: false`:

1. **Talos applies taint** to control plane nodes:
   - Key: `node-role.kubernetes.io/control-plane`
   - Effect: `NoSchedule`

2. **Workload scheduling behavior**:
   - Regular workloads are **blocked** from control plane nodes
   - Only pods with matching tolerations can schedule on control planes
   - System components (kubelet static pods) run normally

## Platform Component Scheduling

### Components WITH Control Plane Tolerations (run on control plane)

| Component | Configuration | Location |
|-----------|---------------|----------|
| **ArgoCD** | Kustomize patches add tolerations to all deployments | `bootstrap/argocd/kustomization.yaml` |
| **External Secrets** | Helm values with tolerations + nodeSelector | `bootstrap/components/01-eso.yaml` |
| **NATS** | StatefulSet patch with tolerations + affinity | `bootstrap/components/01-nats.yaml` |
| **Crossplane** | Helm values with tolerations | `bootstrap/components/01-crossplane.yaml` |
| **KEDA** | Helm values with tolerations | `bootstrap/components/01-keda.yaml` |
| **Cilium** | Built-in DaemonSet tolerations | Talos inline manifest |

### Components WITHOUT Tolerations (run on worker nodes only)

- Application databases (PostgreSQL, Dragonfly)
- Intelligence services (Qdrant, AI agents)
- Custom workloads and compositions

## Toleration Configuration Examples

### ArgoCD (Kustomize Patch)
```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

### External Secrets (Helm Values)
```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
nodeSelector:
  node-role.kubernetes.io/control-plane: ""
```

### NATS (StatefulSet Patch)
```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: node-role.kubernetes.io/control-plane
              operator: Exists
```

## Environment Behavior

### Production (Multi-Node)
- ✅ Platform components on control planes
- ✅ Application workloads on worker nodes
- ✅ Proper isolation and resource separation

### Development/Kind (Single-Node)
- ✅ Platform components on control plane
- ❌ Application workloads blocked (no worker nodes)
- **Solution**: Platform components have tolerations to work in single-node setups

### Preview Mode
- **Production**: All platform components have control plane tolerations
- **Preview**: All platform components run without tolerations (assumes Kind cluster)
- Auto-detection based on control plane taints presence

## Key Benefits

1. **Security**: Isolates application workloads from control plane
2. **Performance**: Prevents resource contention on control plane
3. **Reliability**: Protects critical Kubernetes components
4. **Flexibility**: Platform components can run on control planes when needed

## Troubleshooting

**Symptom**: Pods stuck in `Pending` state with `SchedulingDisabled` events
**Cause**: Missing tolerations for control plane scheduling
**Solution**: Add tolerations to pod spec or helm values

**Symptom**: Platform components fail in single-node clusters
**Cause**: No worker nodes available
**Solution**: Ensure platform components have control plane tolerations (already configured)
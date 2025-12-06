# Production-Grade Bootstrap Sequence

## Overview
This document describes the production-safe bootstrap sequence for the ZeroTouch platform, ensuring proper ordering of network stack initialization before GitOps deployment.

## Bootstrap Sequence

### 1️⃣ Bootstrap Control Plane Node
- Talos OS installed on control plane
- Minimal Cilium inline manifest applied (embedded in Talos config)
- Cilium pod + cilium-operator (single replica) becomes ready
- **Note**: Operator scaling to 1 is normal at this point because only one node exists

### 2️⃣ Readiness Gate (CRITICAL)
Before installing ArgoCD, the script ensures:
- ✅ Cilium agent ready (`k8s-app=cilium`)
- ✅ Cilium operator ready (`name=cilium-operator`)
- ✅ Cilium health reports passing

**Commands used:**
```bash
kubectl wait --for=condition=ready pod -n kube-system -l k8s-app=cilium --timeout=180s
kubectl wait --for=condition=ready pod -n kube-system -l name=cilium-operator --timeout=180s
```

**Why this matters**: ArgoCD requires a functioning network stack to sync applications. Without this gate, ArgoCD pods may fail to start or experience nil pointer dereferences due to missing network connectivity.

### 3️⃣ Install ArgoCD
Now that the network stack exists, ArgoCD can start reliably and begin syncing platform applications.

### 4️⃣ Join Worker Node
- Worker boots with Talos configuration
- Talos pulls bootstrap config
- Cilium agent starts on worker
- Cilium operator detects second node

### 5️⃣ Automatic Operator Scaling
The Cilium operator deployment is configured with `replicas: 2` in the bootstrap manifest.

**Production-safe behavior:**
- On single node: Kubernetes schedules only 1 replica (can't satisfy anti-affinity)
- After worker joins: Kubernetes automatically schedules 2nd replica
- No manual scaling required - Kubernetes handles it naturally

**Why this is correct:**
- ❌ Manual scaling (scale down → scale up) is a bootstrap workaround, not production-safe
- ✅ Declarative replica count lets Kubernetes satisfy constraints when nodes exist
- ✅ No harm if applied early - K8s will schedule what it can

## Key Principles

### Separation of Concerns
- **Bootstrap workarounds** should not be baked into operational procedures
- **Declarative state** (replicas: 2) is better than imperative scaling commands
- **Kubernetes scheduler** handles constraints naturally without manual intervention

### Production Architecture
In a properly architected production cluster:
- The operator should scale naturally after the second node joins
- No manual scaling toggles in procedures
- Readiness gates ensure proper sequencing
- Network stack must exist before GitOps layer

## Files Modified

### `scripts/bootstrap/01-master-bootstrap.sh`
- Added readiness gates before ArgoCD installation (Step 1.6)
- Removed any manual scaling logic
- Added informational messages about natural scaling behavior

### `bootstrap/talos-templates/cilium-bootstrap.yaml`
- Operator deployment configured with `replicas: 2`
- Anti-affinity rules prevent multiple replicas on same node
- Kubernetes scheduler handles replica placement naturally

## Verification

After bootstrap completes:

```bash
# Check Cilium agent (should be running on all nodes)
kubectl get pods -n kube-system -l k8s-app=cilium

# Check Cilium operator (1 replica on single node, 2 after worker joins)
kubectl get pods -n kube-system -l name=cilium-operator

# Verify Cilium health
kubectl exec -n kube-system <cilium-pod> -- cilium status

# Check ArgoCD is syncing
kubectl get applications -n argocd
```

## Troubleshooting

### Operator stuck at 1 replica after worker joins
```bash
# Check operator deployment
kubectl get deployment cilium-operator -n kube-system -o yaml

# Check pod anti-affinity constraints
kubectl describe deployment cilium-operator -n kube-system

# Verify worker node is ready
kubectl get nodes
```

### ArgoCD fails to start
```bash
# Check if Cilium was ready before ArgoCD installation
kubectl get pods -n kube-system -l k8s-app=cilium

# Check ArgoCD pod events
kubectl describe pod -n argocd <argocd-pod>

# Verify network connectivity
kubectl exec -n kube-system <cilium-pod> -- cilium connectivity test
```

## References

- [Cilium Installation Guide](https://docs.cilium.io/en/stable/installation/)
- [Talos CNI Configuration](https://www.talos.dev/latest/kubernetes-guides/network/)
- [ArgoCD Bootstrap](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/)

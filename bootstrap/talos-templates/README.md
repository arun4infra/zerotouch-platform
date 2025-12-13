# Talos Configuration Templates

This directory contains **public templates** for Talos machine configurations and bootstrap manifests.

## Files

### `cilium-bootstrap.yaml`
Static Cilium CNI manifest (version 1.16.1) with minimal bootstrap configuration.

**Features enabled:**
- Core CNI networking
- Kube-proxy replacement
- IPAM mode: kubernetes
- Talos-specific security contexts
- KubePrism integration (localhost:7445)

**Features disabled (ArgoCD will enable after bootstrap):**
- Hubble UI
- Hubble Relay
- Gateway API

**Regeneration:**
Only regenerate if upgrading Cilium version or changing core configuration:
```bash
helm template cilium cilium/cilium \
  --version 1.16.1 \
  --namespace kube-system \
  --kube-version 1.34.1 \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=localhost \
  --set k8sServicePort=7445 \
  --set securityContext.capabilities.ciliumAgent='{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}' \
  --set securityContext.capabilities.cleanCiliumState='{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}' \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup \
  --set hubble.enabled=false \
  --set gatewayAPI.enabled=false \
  > bootstrap/talos-templates/cilium-bootstrap.yaml
```

### `controlplane.yaml.tmpl` (coming soon)
Template for Talos control plane machine configuration.

### `worker.yaml.tmpl` (coming soon)
Template for Talos worker machine configuration.

## Usage

Templates are rendered with environment-specific values from `environments/{env}/talos-values.yaml`.

Generate configs:
```bash
make generate-configs ENV=dev
```

This creates actual Talos configs in `bootstrap/talos/nodes/` (gitignored).

# Talos Configuration Templates

This directory contains **modular templates** for Talos machine configurations and bootstrap manifests.

## Architecture

### Modular Cilium Bootstrap
The `cilium/` directory contains modular Cilium configuration files that are dynamically combined by `scripts/bootstrap/install/02-embed-network-manifests.sh`:

- `01-serviceaccounts.yaml` - Cilium service accounts
- `02-configmaps.yaml` - Cilium configuration
- `03-envoy-config.yaml` - Envoy proxy configuration  
- `04-rbac.yaml` - **RBAC permissions (includes Gateway API)**
- `05-rolebindings.yaml` - Role bindings
- `06-agent-daemonset.yaml` - Cilium agent DaemonSet
- `07-envoy-daemonset.yaml` - Cilium Envoy DaemonSet
- `08-operator-deployment.yaml` - Cilium operator Deployment
- `09-crds.yaml` - Cilium CRDs

### Dynamic Generation Process

1. **Script combines modular files** → `cilium-bootstrap.yaml`
2. **Script embeds into Talos config** → `nodes/cp01-main/config.yaml` 
3. **Talos applies during cluster bootstrap** → Running cluster

### Gateway API Support

**RBAC Requirements:**
The `cilium-operator` ClusterRole in `04-rbac.yaml` **must include**:
```yaml
# CiliumGatewayClassConfig for Gateway API
- apiGroups:
  - cilium.io
  resources:
  - ciliumgatewayclassconfigs
  - ciliumenvoyconfigs
  - ciliumclusterwideenvoyconfigs
  verbs:
  - get
  - list
  - watch
```

**Critical:** Changes to modular files require running the embed script to take effect:
```bash
./scripts/bootstrap/install/02-embed-network-manifests.sh
```

## Files

### `cilium-bootstrap.yaml` (Generated)
**DO NOT EDIT DIRECTLY** - This file is generated from `cilium/*.yaml` modules.

**Features enabled:**
- Core CNI networking with Gateway API support
- Kube-proxy replacement
- External Envoy proxy for Gateway API
- L7 proxy capabilities
- Mesh authentication
- IPAM mode: kubernetes

### `gateway-api-crds.yaml`
Gateway API CRDs (v1.4.1) downloaded and embedded before Cilium for proper Gateway API detection.

## Usage

### Modifying Cilium Configuration
1. Edit files in `cilium/` directory
2. Run embed script: `./scripts/bootstrap/install/02-embed-network-manifests.sh`
3. Apply to cluster or rebuild cluster with new config

### Upgrading Cilium
Update the modular files in `cilium/` directory, then regenerate.

**Never edit `cilium-bootstrap.yaml` directly** - changes will be overwritten.

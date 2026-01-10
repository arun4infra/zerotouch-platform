# Cilium Bootstrap Manifests (Modular)

This directory contains the modular Cilium bootstrap manifests that are combined
during cluster bootstrap into a single `cilium-bootstrap.yaml` file.

## File Structure

Files are numbered to ensure correct ordering when concatenated:

| File | Description | Lines |
|------|-------------|-------|
| `01-serviceaccounts.yaml` | ServiceAccounts for cilium, cilium-envoy, cilium-operator | ~20 |
| `02-configmaps.yaml` | Cilium ConfigMap with all configuration options | ~230 |
| `03-envoy-config.yaml` | Envoy proxy bootstrap configuration | ~330 |
| `04-rbac.yaml` | ClusterRoles for cilium-agent and cilium-operator | ~370 |
| `05-rolebindings.yaml` | ClusterRoleBindings and namespace Roles | ~70 |
| `06-agent-daemonset.yaml` | Cilium agent DaemonSet | ~450 |
| `07-envoy-daemonset.yaml` | Cilium Envoy proxy DaemonSet | ~175 |
| `08-operator-deployment.yaml` | Cilium operator Deployment | ~120 |
| `09-crds.yaml` | CRDs required for Gateway API (CiliumEnvoyConfig) | ~230 |

## How It Works

The `02-embed-cilium.sh` script:
1. Concatenates all `*.yaml` files in this directory (sorted alphabetically)
2. Outputs to `../cilium-bootstrap.yaml`
3. Embeds the combined manifest into Talos control plane config

## Modifying Cilium Configuration

1. Edit the appropriate file in this directory
2. Run `02-embed-cilium.sh` to regenerate the combined manifest
3. The changes will be applied on next cluster bootstrap

## Adding New Components

1. Create a new numbered YAML file (e.g., `10-new-component.yaml`)
2. Ensure the number maintains correct ordering for dependencies
3. Run `02-embed-cilium.sh` to include in the combined manifest

## Source

These manifests are generated from Cilium Helm chart v1.18.5 with Gateway API enabled.
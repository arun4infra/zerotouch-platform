#!/bin/bash
set -euo pipefail

# Requirement: yq (https://github.com/mikefarah/yq)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERSIONS_FILE="${REPO_ROOT}/platform/versions.yaml"

echo "Syncing ArgoCD manifests with platform/versions.yaml..."

# Verify yq is installed
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed"
    echo "Install: https://github.com/mikefarah/yq"
    exit 1
fi

# Verify versions file exists
if [ ! -f "$VERSIONS_FILE" ]; then
    echo "Error: versions.yaml not found at $VERSIONS_FILE"
    exit 1
fi

# Helper function to update only if changed
update_if_changed() {
    local file=$1
    local current_val=$(yq "$2" "$file")
    local new_val=$3
    
    if [ "$current_val" != "$new_val" ]; then
        yq -i "$2 = \"$new_val\"" "$file"
        return 0
    fi
    return 1
}

# 1. Update Crossplane
VER=$(yq '.components.crossplane.chart_version' $VERSIONS_FILE)
if update_if_changed "${REPO_ROOT}/bootstrap/argocd/base/01-crossplane.yaml" ".spec.source.targetRevision" "$VER"; then
    echo "✓ Crossplane -> $VER (updated)"
else
    echo "✓ Crossplane -> $VER (unchanged)"
fi

# 2. Update External Secrets
VER=$(yq '.components.external_secrets.chart_version' $VERSIONS_FILE)
if update_if_changed "${REPO_ROOT}/bootstrap/argocd/base/00-eso.yaml" ".spec.source.targetRevision" "$VER"; then
    echo "✓ ESO -> $VER (updated)"
else
    echo "✓ ESO -> $VER (unchanged)"
fi

# 3. Update Cert Manager
VER=$(yq '.components.cert_manager.chart_version' $VERSIONS_FILE)
if update_if_changed "${REPO_ROOT}/bootstrap/argocd/base/01-cert-manager.yaml" ".spec.source.targetRevision" "$VER"; then
    echo "✓ Cert Manager -> $VER (updated)"
else
    echo "✓ Cert Manager -> $VER (unchanged)"
fi

# 4. Update CNPG
VER=$(yq '.components.cnpg.chart_version' $VERSIONS_FILE)
if update_if_changed "${REPO_ROOT}/bootstrap/argocd/base/02-cnpg.yaml" ".spec.source.targetRevision" "$VER"; then
    PG_IMG=$(yq '.components.cnpg.postgres_image' $VERSIONS_FILE)
    echo "✓ CNPG -> $VER (updated, Postgres: $PG_IMG)"
else
    echo "✓ CNPG -> $VER (unchanged)"
fi

# 5. Update NATS
VER=$(yq '.components.nats.chart_version' $VERSIONS_FILE)
if update_if_changed "${REPO_ROOT}/bootstrap/argocd/base/05-nats.yaml" ".spec.source.targetRevision" "$VER"; then
    echo "✓ NATS -> $VER (updated)"
else
    echo "✓ NATS -> $VER (unchanged)"
fi

# 6. Update KEDA
VER=$(yq '.components.keda.chart_version' $VERSIONS_FILE)
if update_if_changed "${REPO_ROOT}/bootstrap/argocd/base/04-keda.yaml" ".spec.source.targetRevision" "$VER"; then
    echo "✓ KEDA -> $VER (updated)"
else
    echo "✓ KEDA -> $VER (unchanged)"
fi

# 7. Update kagent
VER=$(yq '.components.kagent.chart_version' $VERSIONS_FILE)
if update_if_changed "${REPO_ROOT}/bootstrap/argocd/base/04-kagent.yaml" ".spec.source.targetRevision" "$VER"; then
    echo "✓ kagent -> $VER (updated)"
else
    echo "✓ kagent -> $VER (unchanged)"
fi

# 8. Update ArgoCD version in install script
ARGOCD_VER=$(yq '.components.argocd.version' $VERSIONS_FILE)
CURRENT_ARGOCD=$(grep '^ARGOCD_VERSION=' ${REPO_ROOT}/scripts/bootstrap/install/09-install-argocd.sh | cut -d'"' -f2)
if [ "$CURRENT_ARGOCD" != "$ARGOCD_VER" ]; then
    sed -i.bak "s/ARGOCD_VERSION=\".*\"/ARGOCD_VERSION=\"$ARGOCD_VER\"/" ${REPO_ROOT}/scripts/bootstrap/install/09-install-argocd.sh
    rm ${REPO_ROOT}/scripts/bootstrap/install/09-install-argocd.sh.bak
    echo "✓ ArgoCD -> $ARGOCD_VER (updated)"
else
    echo "✓ ArgoCD -> $ARGOCD_VER (unchanged)"
fi

# 9. Update Talos version in install script
TALOS_VER=$(yq '.components.talos.version' $VERSIONS_FILE)
CURRENT_TALOS=$(grep '^TALOS_VERSION=' ${REPO_ROOT}/scripts/bootstrap/install/03-install-talos.sh | cut -d'"' -f2)
if [ "$CURRENT_TALOS" != "$TALOS_VER" ]; then
    sed -i.bak "s/^TALOS_VERSION=\".*\"/TALOS_VERSION=\"$TALOS_VER\"/" ${REPO_ROOT}/scripts/bootstrap/install/03-install-talos.sh
    rm ${REPO_ROOT}/scripts/bootstrap/install/03-install-talos.sh.bak
    echo "✓ Talos -> $TALOS_VER (updated)"
else
    echo "✓ Talos -> $TALOS_VER (unchanged)"
fi

# 10. Update Cilium operator image in template
CILIUM_IMG=$(yq '.components.cilium.operator_image' $VERSIONS_FILE)
CURRENT_CILIUM=$(grep 'image: "quay.io/cilium/operator-generic:' ${REPO_ROOT}/bootstrap/talos/templates/cilium/08-operator-deployment.yaml | sed 's/.*image: "\(.*\)"/\1/')
if [ "$CURRENT_CILIUM" != "$CILIUM_IMG" ]; then
    sed -i.bak "s|image: \"quay.io/cilium/operator-generic:.*\"|image: \"$CILIUM_IMG\"|" ${REPO_ROOT}/bootstrap/talos/templates/cilium/08-operator-deployment.yaml
    rm ${REPO_ROOT}/bootstrap/talos/templates/cilium/08-operator-deployment.yaml.bak
    echo "✓ Cilium -> $(yq '.components.cilium.version' $VERSIONS_FILE) (updated)"
else
    echo "✓ Cilium -> $(yq '.components.cilium.version' $VERSIONS_FILE) (unchanged)"
fi

# 11. Update SOPS and Age versions in KSOPS install script
SOPS_VER=$(yq '.components.cli_tools.sops' $VERSIONS_FILE)
AGE_VER=$(yq '.components.cli_tools.age' $VERSIONS_FILE)

CURRENT_SOPS=$(grep '^SOPS_VERSION=' ${REPO_ROOT}/scripts/bootstrap/install/08a-install-ksops.sh | cut -d'"' -f2)
CURRENT_AGE=$(grep '^AGE_VERSION=' ${REPO_ROOT}/scripts/bootstrap/install/08a-install-ksops.sh | cut -d'"' -f2)

if [ "$CURRENT_SOPS" != "$SOPS_VER" ]; then
    sed -i.bak "s/SOPS_VERSION=\".*\"/SOPS_VERSION=\"$SOPS_VER\"/" ${REPO_ROOT}/scripts/bootstrap/install/08a-install-ksops.sh
    rm ${REPO_ROOT}/scripts/bootstrap/install/08a-install-ksops.sh.bak
    echo "✓ SOPS -> $SOPS_VER (updated)"
else
    echo "✓ SOPS -> $SOPS_VER (unchanged)"
fi

if [ "$CURRENT_AGE" != "$AGE_VER" ]; then
    sed -i.bak "s/AGE_VERSION=\".*\"/AGE_VERSION=\"$AGE_VER\"/" ${REPO_ROOT}/scripts/bootstrap/install/08a-install-ksops.sh
    rm ${REPO_ROOT}/scripts/bootstrap/install/08a-install-ksops.sh.bak
    echo "✓ Age -> $AGE_VER (updated)"
else
    echo "✓ Age -> $AGE_VER (unchanged)"
fi

# 12. Update kubectl and helm versions in production infra deps script
KUBECTL_VER=$(yq '.components.cli_tools.kubectl' $VERSIONS_FILE)
HELM_VER=$(yq '.components.cli_tools.helm' $VERSIONS_FILE)

# Update kubectl version (replace the curl command that fetches latest)
CURRENT_KUBECTL_LINE=$(grep 'curl -LO.*kubectl' ${REPO_ROOT}/scripts/bootstrap/infra/00-setup-infra-deps.sh)
if [[ "$CURRENT_KUBECTL_LINE" == *"$KUBECTL_VER"* ]]; then
    echo "✓ kubectl -> $KUBECTL_VER (unchanged)"
else
    sed -i.bak "s|curl -LO \"https://dl.k8s.io/release/.*kubectl\"|curl -LO \"https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl\"|" ${REPO_ROOT}/scripts/bootstrap/infra/00-setup-infra-deps.sh
    rm ${REPO_ROOT}/scripts/bootstrap/infra/00-setup-infra-deps.sh.bak
    echo "✓ kubectl -> $KUBECTL_VER (updated)"
fi

# Update helm version (add version variable to helm install)
if grep -q "DESIRED_VERSION=" ${REPO_ROOT}/scripts/bootstrap/infra/00-setup-infra-deps.sh; then
    CURRENT_HELM=$(grep 'DESIRED_VERSION=' ${REPO_ROOT}/scripts/bootstrap/infra/00-setup-infra-deps.sh | cut -d'=' -f2)
    if [ "$CURRENT_HELM" != "$HELM_VER" ]; then
        sed -i.bak "s/DESIRED_VERSION=.*/DESIRED_VERSION=$HELM_VER/" ${REPO_ROOT}/scripts/bootstrap/infra/00-setup-infra-deps.sh
        rm ${REPO_ROOT}/scripts/bootstrap/infra/00-setup-infra-deps.sh.bak
        echo "✓ helm -> $HELM_VER (updated)"
    else
        echo "✓ helm -> $HELM_VER (unchanged)"
    fi
else
    # Add version variable before helm install
    sed -i.bak '/curl.*get-helm-3/i\    export DESIRED_VERSION='$HELM_VER ${REPO_ROOT}/scripts/bootstrap/infra/00-setup-infra-deps.sh
    rm ${REPO_ROOT}/scripts/bootstrap/infra/00-setup-infra-deps.sh.bak
    echo "✓ helm -> $HELM_VER (updated)"
fi

# 13. Update External DNS
VER=$(yq '.components.external_dns.chart_version' $VERSIONS_FILE)
WEBHOOK_IMG=$(yq '.components.external_dns.webhook_image' $VERSIONS_FILE)
if update_if_changed "${REPO_ROOT}/bootstrap/argocd/overlays/main/core/01-external-dns.yaml" ".spec.source.targetRevision" "$VER"; then
    echo "✓ External DNS -> $VER (updated, webhook: $WEBHOOK_IMG)"
else
    echo "✓ External DNS -> $VER (unchanged)"
fi
# Update webhook image in helm values
CURRENT_WEBHOOK=$(yq '.spec.source.helm.values' "${REPO_ROOT}/bootstrap/argocd/overlays/main/core/01-external-dns.yaml" | yq '.provider.webhook.image.repository + ":" + .provider.webhook.image.tag')
if [ "$CURRENT_WEBHOOK" != "$WEBHOOK_IMG" ]; then
    WEBHOOK_REPO=$(echo "$WEBHOOK_IMG" | cut -d':' -f1)
    WEBHOOK_TAG=$(echo "$WEBHOOK_IMG" | cut -d':' -f2)
    yq -i ".spec.source.helm.values |= (. | from_yaml | .provider.webhook.image.repository = \"$WEBHOOK_REPO\" | .provider.webhook.image.tag = \"$WEBHOOK_TAG\" | to_yaml)" "${REPO_ROOT}/bootstrap/argocd/overlays/main/core/01-external-dns.yaml"
    echo "  ✓ Webhook image updated"
fi

# 14. Update HCloud CCM
VER=$(yq '.components.hcloud_ccm.chart_version' $VERSIONS_FILE)
if update_if_changed "${REPO_ROOT}/bootstrap/argocd/overlays/main/core/01-hcloud-ccm.yaml" ".spec.source.targetRevision" "$VER"; then
    echo "✓ HCloud CCM -> $VER (updated)"
else
    echo "✓ HCloud CCM -> $VER (unchanged)"
fi

# 15. Update Cert-Manager Webhook Hetzner
VER=$(yq '.components.cert_manager_webhook_hetzner.chart_version' $VERSIONS_FILE)
if update_if_changed "${REPO_ROOT}/bootstrap/argocd/overlays/main/core/01-cert-manager-webhook-hetzner.yaml" ".spec.source.targetRevision" "$VER"; then
    echo "✓ Cert-Manager Webhook Hetzner -> $VER (updated)"
else
    echo "✓ Cert-Manager Webhook Hetzner -> $VER (unchanged)"
fi

# 16. Update Local Path Provisioner
VER=$(yq '.components.local_path_provisioner.version' $VERSIONS_FILE)
if update_if_changed "${REPO_ROOT}/bootstrap/argocd/overlays/main/core/00-local-path-provisioner.yaml" ".spec.source.targetRevision" "$VER"; then
    echo "✓ Local Path Provisioner -> $VER (updated)"
else
    echo "✓ Local Path Provisioner -> $VER (unchanged)"
fi

echo ""
echo "Sync complete. Commit changes to bootstrap/argocd/ and scripts/."

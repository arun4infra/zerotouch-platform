#!/bin/bash
# Embed Cilium Bootstrap Manifest into Talos Control Plane Config
# This adds the static Cilium manifest to cluster.inlineManifests section
# Only applied to control plane - workers inherit CNI automatically

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CP_CONFIG="$SCRIPT_DIR/../../bootstrap/talos/nodes/cp01-main/config.yaml"
CILIUM_MANIFEST="$SCRIPT_DIR/../../bootstrap/talos-templates/cilium-bootstrap.yaml"

# Check if Cilium manifest exists
if [ ! -f "$CILIUM_MANIFEST" ]; then
    echo "ERROR: Cilium bootstrap manifest not found at: $CILIUM_MANIFEST"
    exit 1
fi

# Check if control plane config exists
if [ ! -f "$CP_CONFIG" ]; then
    echo "ERROR: Control plane config not found at: $CP_CONFIG"
    echo ""
    echo "The Talos control plane config must exist before embedding Cilium."
    echo "This config should be checked into git at: bootstrap/talos/nodes/cp01-main/config.yaml"
    echo ""
    echo "If you need to generate a new config, use:"
    echo "  talosctl gen config <cluster-name> https://<control-plane-ip>:6443"
    echo ""
    exit 1
fi

echo "Embedding Cilium manifest into control plane Talos config..."

# Check if inlineManifests already exists (uncommented)
if grep -q "^[[:space:]]*inlineManifests:" "$CP_CONFIG"; then
    echo "⚠️  inlineManifests section already exists - removing old version"
    # Remove old inlineManifests section (from inlineManifests: to next top-level key at same indentation)
    # This AWK script removes the inlineManifests section and all its nested content
    awk '
        /^[[:space:]]*inlineManifests:/ { 
            indent = match($0, /[^ ]/)
            skip=1
            next 
        }
        skip && /^[[:space:]]*[a-zA-Z]/ {
            current_indent = match($0, /[^ ]/)
            if (current_indent <= indent) {
                skip=0
            }
        }
        !skip { print }
    ' "$CP_CONFIG" > /tmp/cp-config-no-inline.yaml
    mv /tmp/cp-config-no-inline.yaml "$CP_CONFIG"
    echo "✓ Old inlineManifests removed - will re-embed with latest manifest"
fi

# Find insertion point (after allowSchedulingOnControlPlanes)
LINE_NUM=$(grep -n "allowSchedulingOnControlPlanes:" "$CP_CONFIG" | cut -d: -f1)

if [ -z "$LINE_NUM" ]; then
    echo "ERROR: Could not find insertion point in control plane config"
    exit 1
fi

INSERT_LINE=$((LINE_NUM + 1))

# Create inline manifest section
cat > /tmp/inline-manifest.yaml <<'EOF'
    # Cilium CNI for bootstrap - minimal config
    # ArgoCD will adopt and enable full features (Hubble, Gateway API)
    inlineManifests:
        - name: cilium-bootstrap
          contents: |
EOF

# Add Cilium manifest content with proper indentation (12 spaces)
sed 's/^/            /' "$CILIUM_MANIFEST" >> /tmp/inline-manifest.yaml

# Backup original
cp "$CP_CONFIG" "$CP_CONFIG.backup-$(date +%Y%m%d-%H%M%S)"

# Insert into config
{
    head -n "$LINE_NUM" "$CP_CONFIG"
    cat /tmp/inline-manifest.yaml
    tail -n +$((INSERT_LINE)) "$CP_CONFIG"
} > /tmp/cp-config-new.yaml

# Replace with new config
mv /tmp/cp-config-new.yaml "$CP_CONFIG"
rm /tmp/inline-manifest.yaml

echo "✓ Cilium manifest embedded in control plane config"
echo "  Backup created: $CP_CONFIG.backup-*"
echo "  Workers will inherit CNI automatically"

#!/bin/bash
# Embed Gateway API CRDs and Cilium Bootstrap Manifests into Talos Control Plane Config
# This adds static manifests to cluster.inlineManifests section
# Gateway API CRDs MUST be loaded BEFORE Cilium so Cilium detects Gateway API support
# Only applied to control plane - workers inherit CNI automatically

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR" && while [[ ! -d .git && $(pwd) != "/" ]]; do cd ..; done; pwd))"
CP_CONFIG="$REPO_ROOT/bootstrap/talos/nodes/cp01-main/config.yaml"
CILIUM_DIR="$REPO_ROOT/bootstrap/talos/templates/cilium"
CILIUM_MANIFEST="$REPO_ROOT/bootstrap/talos/templates/cilium-bootstrap.yaml"
GATEWAY_API_MANIFEST="$REPO_ROOT/bootstrap/talos/templates/gateway-api-crds.yaml"
GATEWAY_API_VERSION="v1.4.1"

# Download Gateway API CRDs
echo "Preparing Gateway API CRDs ${GATEWAY_API_VERSION}..."
if [ ! -f "$GATEWAY_API_MANIFEST" ]; then
    echo "Downloading Gateway API CRDs..."
    curl -sL "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml" -o "$GATEWAY_API_MANIFEST"
    echo "✓ Gateway API CRDs downloaded"
else
    echo "✓ Gateway API CRDs already present"
fi

# Build combined Cilium manifest from modular files
echo "Building Cilium manifest from modular files..."
if [ -d "$CILIUM_DIR" ]; then
    first=true
    for f in "$CILIUM_DIR"/*.yaml; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ""
        fi
        cat "$f"
    done > "$CILIUM_MANIFEST"
    echo "✓ Combined $(ls -1 "$CILIUM_DIR"/*.yaml | wc -l | tr -d ' ') files into cilium-bootstrap.yaml"
fi

# Validate manifests exist
if [ ! -f "$GATEWAY_API_MANIFEST" ]; then
    echo "ERROR: Gateway API CRDs manifest not found at: $GATEWAY_API_MANIFEST"
    exit 1
fi

if [ ! -f "$CILIUM_MANIFEST" ]; then
    echo "ERROR: Cilium bootstrap manifest not found at: $CILIUM_MANIFEST"
    exit 1
fi

if [ ! -f "$CP_CONFIG" ]; then
    echo "ERROR: Control plane config not found at: $CP_CONFIG"
    exit 1
fi

echo "Embedding network manifests into control plane Talos config..."

# Remove existing inlineManifests if present
if grep -q "^[[:space:]]*inlineManifests:" "$CP_CONFIG"; then
    echo "⚠️  inlineManifests section already exists - removing old version"
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
    echo "✓ Old inlineManifests removed"
fi

# Find insertion point
LINE_NUM=$(grep -n "allowSchedulingOnControlPlanes:" "$CP_CONFIG" | cut -d: -f1)
if [ -z "$LINE_NUM" ]; then
    echo "ERROR: Could not find insertion point in control plane config"
    exit 1
fi

# Create inline manifests section with Gateway API CRDs FIRST, then Cilium
cat > /tmp/inline-manifest.yaml <<'EOF'
    # Network manifests for bootstrap
    # Gateway API CRDs must load BEFORE Cilium for Gateway API support
    inlineManifests:
        - name: gateway-api-crds
          contents: |
EOF

# Add Gateway API CRDs (12 spaces indentation)
sed 's/^/            /' "$GATEWAY_API_MANIFEST" >> /tmp/inline-manifest.yaml

# Add Cilium manifest
cat >> /tmp/inline-manifest.yaml <<'EOF'
        - name: cilium-bootstrap
          contents: |
EOF

sed 's/^/            /' "$CILIUM_MANIFEST" >> /tmp/inline-manifest.yaml

# Backup and insert
cp "$CP_CONFIG" "$CP_CONFIG.backup-$(date +%Y%m%d-%H%M%S)"

{
    head -n "$LINE_NUM" "$CP_CONFIG"
    cat /tmp/inline-manifest.yaml
    tail -n +$((LINE_NUM + 1)) "$CP_CONFIG"
} > /tmp/cp-config-new.yaml

mv /tmp/cp-config-new.yaml "$CP_CONFIG"
rm /tmp/inline-manifest.yaml

echo "✓ Gateway API CRDs and Cilium manifests embedded in control plane config"
echo "  Gateway API CRDs will load first, then Cilium"
echo "  Cilium will detect Gateway API support on startup"

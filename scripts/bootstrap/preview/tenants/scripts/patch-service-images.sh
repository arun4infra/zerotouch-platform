#!/bin/bash
set -euo pipefail

# ==============================================================================
# Platform Service Image Patcher
# ==============================================================================
# Purpose: Updates Kubernetes manifests to use the image built in the previous step
# Usage: ./patch-service-images.sh <service-name> <build-mode> <image-tag>
# ==============================================================================

SERVICE_NAME="${1:-}"
BUILD_MODE="${2:-test}"
IMAGE_TAG="${3:-ci-test}"

# Default registry to match build script
REGISTRY="${CONTAINER_REGISTRY:-ghcr.io/arun4infra}"

if [[ -z "$SERVICE_NAME" ]]; then
    echo "Usage: $0 <service-name> [build-mode] [image-tag]"
    exit 1
fi

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[PATCH]${NC} $*"; }
log_success() { echo -e "${GREEN}[PATCH]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[PATCH]${NC} $*"; }

main() {
    log_info "Patching deployment manifests..."
    log_info "  Service: ${SERVICE_NAME}"
    log_info "  Mode:    ${BUILD_MODE}"
    log_info "  Tag:     ${IMAGE_TAG}"

    # Construct the target image string based on mode
    local target_image=""
    if [[ "$BUILD_MODE" == "test" ]]; then
        # Local Kind cluster uses simple name
        target_image="${SERVICE_NAME}:${IMAGE_TAG}"
    elif [[ "$IMAGE_TAG" == *"/"* ]]; then
        # Image tag is already a full path (e.g., ghcr.io/org/service:sha-123)
        target_image="${IMAGE_TAG}"
    else
        # Registry for PR/Prod - construct full path
        target_image="${REGISTRY}/${SERVICE_NAME}:${IMAGE_TAG}"
    fi

    log_info "  Target:  ${target_image}"

    # Find all yaml files in platform/claims that reference the service image
    # We look for the service name in the image field
    local count=0
    local files_found=0

    # Check if platform/claims directory exists
    if [[ ! -d "platform/claims" ]]; then
        log_warn "platform/claims directory not found, skipping image patching"
        return 0
    fi

    # Using find to get files, then processing
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            files_found=$((files_found + 1))
            # Check if file actually contains an image definition for this service
            # Matches: image: something/service-name:something OR image: service-name:something
            if grep -qE "image:.*[ /]${SERVICE_NAME}:|image: ${SERVICE_NAME}:" "$file"; then
                log_info "Patching file: $file"
                
                # Create backup
                cp "$file" "$file.bak"
                
                # Use sed to replace the image line
                # Pattern handles: "image: repo/service:tag" or "image: service:tag"
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    sed -i '' "s|image: .*${SERVICE_NAME}:.*|image: ${target_image}|g" "$file"
                else
                    sed -i "s|image: .*${SERVICE_NAME}:.*|image: ${target_image}|g" "$file"
                fi
                
                # Remove backup if sed succeeded
                if [[ $? -eq 0 ]]; then
                    rm -f "$file.bak"
                    count=$((count + 1))
                else
                    # Restore backup if sed failed
                    mv "$file.bak" "$file"
                    log_warn "Failed to patch $file, restored backup"
                fi
            fi
        fi
    done < <(find platform/claims -name "*.yaml" -type f 2>/dev/null || true)

    if [[ $files_found -eq 0 ]]; then
        log_warn "No YAML files found in platform/claims directory"
    elif [[ $count -gt 0 ]]; then
        log_success "Updated $count manifests to use image: ${target_image}"
    else
        log_info "No manifests found requiring updates for service: ${SERVICE_NAME}"
    fi
}

main "$@"
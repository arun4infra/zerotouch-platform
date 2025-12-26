#!/bin/bash
set -euo pipefail

# ==============================================================================
# Platform Service Build Script
# ==============================================================================
# Purpose: Build and tag Docker images based on execution environment
# Modes (Auto-detected):
#   test - Local execution -> Build & Load into Kind (service:ci-test)
#   pr   - CI Pull Request -> Build & Push to Registry (service:branch-sha)
#   prod - CI Main Branch  -> Build & Push to Registry (service:latest + sha)
# ==============================================================================

SERVICE_NAME="${1:-}"

# Default registry, can be overridden by env var
REGISTRY="${CONTAINER_REGISTRY:-ghcr.io/arun4infra}"

# Default cluster name for local loading
CLUSTER_NAME="zerotouch-preview"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[BUILD]${NC} $*"; }
log_success() { echo -e "${GREEN}[BUILD]${NC} $*"; }
log_error() { echo -e "${RED}[BUILD]${NC} $*"; }

if [[ -z "$SERVICE_NAME" ]]; then
    log_error "Usage: $0 <service-name>"
    exit 1
fi

# 1. Auto-detect build mode
detect_mode() {
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then
            echo "pr"
        elif [[ "${GITHUB_REF_NAME:-}" == "main" ]]; then
            echo "prod"
        else
            echo "pr" # Default to PR behavior for other CI events
        fi
    else
        echo "test"
    fi
}

# 2. Get Git Metadata
get_git_info() {
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        echo "${GITHUB_SHA}|${GITHUB_REF_NAME}"
    else
        local sha
        local branch
        sha=$(git rev-parse HEAD 2>/dev/null || echo "local-sha")
        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "local-branch")
        echo "${sha}|${branch}"
    fi
}

main() {
    # Validate Dockerfile exists
    if [[ ! -f "Dockerfile" ]]; then
        log_error "Dockerfile not found in current directory"
        exit 1
    fi

    local mode
    mode=$(detect_mode)

    # Parse Git Info
    IFS='|' read -r commit_sha branch_name <<< "$(get_git_info)"
    local short_sha="${commit_sha:0:7}"
    local safe_branch="${branch_name//[^a-zA-Z0-9._-]/-}"

    echo "================================================================================"
    echo "Platform Service Build"
    echo "================================================================================"
    echo "  Service:    ${SERVICE_NAME}"
    echo "  Mode:       ${mode}"
    echo "  Registry:   ${REGISTRY}"
    echo "  Ref:        ${branch_name} (${short_sha})"
    echo "================================================================================"

    case "$mode" in
        "test")
            build_test_mode "${SERVICE_NAME}"
            ;;
        "pr")
            build_pr_mode "${SERVICE_NAME}" "${safe_branch}" "${short_sha}"
            ;;
        "prod")
            build_prod_mode "${SERVICE_NAME}" "${short_sha}"
            ;;
    esac
}

build_test_mode() {
    local name="$1"
    local tag="ci-test"
    local image="${name}:${tag}"

    log_info "Building for local testing (${image})..."
    
    if ! docker build -t "${image}" .; then
        log_error "Docker build failed"
        exit 1
    fi

    # Check if Kind cluster exists and load image
    if command -v kind &> /dev/null; then
        if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
            log_info "Loading image into Kind cluster '${CLUSTER_NAME}'..."
            if kind load docker-image "${image}" --name "${CLUSTER_NAME}"; then
                log_success "Image loaded into Kind"
            else
                log_error "Failed to load image into Kind cluster"
                exit 1
            fi
        else
            log_info "Kind cluster '${CLUSTER_NAME}' not found, skipping load."
        fi
    fi

    # Export vars for downstream scripts
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "BUILD_MODE=test" >> "$GITHUB_OUTPUT"
        echo "IMAGE_TAG=${tag}" >> "$GITHUB_OUTPUT"
    fi

    log_success "Test build complete: ${image}"
}

build_pr_mode() {
    local name="$1"
    local branch="$2"
    local sha="$3"
    local tag="${branch}-${sha}"
    local image="${REGISTRY}/${name}:${tag}"

    log_info "Building for Pull Request (${image})..."

    # Check docker login for registry push
    if ! docker info | grep -q "Username:" 2>/dev/null; then
        log_error "Docker registry login required for PR mode"
        exit 1
    fi

    if ! docker build -t "${image}" .; then
        log_error "Docker build failed"
        exit 1
    fi

    if ! docker push "${image}"; then
        log_error "Docker push failed"
        exit 1
    fi

    log_success "Pushed: ${image}"

    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "BUILD_MODE=pr" >> "$GITHUB_OUTPUT"
        echo "IMAGE_TAG=${tag}" >> "$GITHUB_OUTPUT"
    fi
}

build_prod_mode() {
    local name="$1"
    local sha="$2"
    local tag_sha="main-${sha}"
    local image_sha="${REGISTRY}/${name}:${tag_sha}"
    local image_latest="${REGISTRY}/${name}:latest"

    log_info "Building for Production..."

    # Check docker login for registry push
    if ! docker info | grep -q "Username:" 2>/dev/null; then
        log_error "Docker registry login required for production mode"
        exit 1
    fi

    if ! docker build -t "${image_sha}" -t "${image_latest}" .; then
        log_error "Docker build failed"
        exit 1
    fi

    if ! docker push "${image_sha}"; then
        log_error "Docker push failed for SHA tag"
        exit 1
    fi

    if ! docker push "${image_latest}"; then
        log_error "Docker push failed for latest tag"
        exit 1
    fi

    log_success "Pushed: ${image_sha}"
    log_success "Pushed: ${image_latest}"

    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "BUILD_MODE=prod" >> "$GITHUB_OUTPUT"
        echo "IMAGE_TAG=${tag_sha}" >> "$GITHUB_OUTPUT" # Use SHA tag for stability
    fi
}

main "$@"
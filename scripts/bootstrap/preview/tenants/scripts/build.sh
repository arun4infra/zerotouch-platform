#!/bin/bash
set -euo pipefail

# ==============================================================================
# Tier 2 CI Script: Build Docker Image
# ==============================================================================
# Purpose: Build Docker image for testing (Kind) or production (Registry push)
# Usage: ./scripts/ci/build.sh [--mode=test|production|local]
# Called by: GitHub Actions workflows or local development
#
# Modes:
#   test       - Build and load into Kind cluster (default)
#   production - Build multi-arch and push to registry (requires GITHUB_SHA, GITHUB_REF_NAME)
#   local      - Build multi-arch and push to registry using local git info
# ==============================================================================

# Configuration
SERVICE_NAME="${SERVICE_NAME:-ide-orchestrator}"  # Can be overridden by environment variable
REGISTRY="ghcr.io/arun4infra"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"  # Adjust path for new location
PLATFORM="linux/amd64"  # Target platform for production builds

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Parse arguments
MODE="test"  # Default mode
for arg in "$@"; do
    case $arg in
        --mode=*)
            MODE="${arg#*=}"
            shift
            ;;
        *)
            # Unknown option
            ;;
    esac
done

# Validate mode
if [[ "$MODE" != "test" && "$MODE" != "production" && "$MODE" != "local" ]]; then
    log_error "Invalid mode: $MODE. Use 'test', 'production', or 'local'"
    exit 1
fi

echo "================================================================================"
echo "Building Docker Image"
echo "================================================================================"
echo "  Service:   ${SERVICE_NAME}"
echo "  Mode:      ${MODE}"
echo "  Registry:  ${REGISTRY}"
echo "================================================================================"

cd "${REPO_ROOT}"

if [[ "$MODE" == "test" ]]; then
    # ========================================================================
    # TEST MODE: Build and load into Kind cluster
    # ========================================================================
    IMAGE_TAG="ci-test"
    CLUSTER_NAME="zerotouch-preview"
    
    log_info "Building Go binary for testing..."
    if [[ "$SERVICE_NAME" == "ide-orchestrator" ]]; then
        CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
            -ldflags="-w -s" \
            -o bin/ide-orchestrator \
            ./cmd/api
        
        log_info "Building Docker test image for testing..."
        docker build \
            -f Dockerfile.test \
            -t "${SERVICE_NAME}:${IMAGE_TAG}" \
            --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
            --build-arg GIT_COMMIT="${GITHUB_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')}" \
            .
    else
        # For other services (like deepagents-runtime)
        log_info "Building Docker test image for testing..."
        docker build \
            -f Dockerfile \
            -t "${SERVICE_NAME}:${IMAGE_TAG}" \
            --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
            --build-arg GIT_COMMIT="${GITHUB_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')}" \
            .
    fi
    
    log_success "Docker image built successfully"
    
    # Only load into Kind cluster if BUILD_ONLY is not set
    if [[ "${BUILD_ONLY:-false}" != "true" ]]; then
        log_info "Loading image into Kind cluster..."
        if ! kind load docker-image "${SERVICE_NAME}:${IMAGE_TAG}" --name "${CLUSTER_NAME}"; then
            log_error "Failed to load image into Kind cluster"
            exit 1
        fi
        log_success "Image loaded successfully into Kind cluster"
        log_success "Build and load complete: ${SERVICE_NAME}:${IMAGE_TAG}"
    else
        log_success "Build complete (skipping load): ${SERVICE_NAME}:${IMAGE_TAG}"
    fi

elif [[ "$MODE" == "production" || "$MODE" == "local" ]]; then
    # ========================================================================
    # PRODUCTION/LOCAL MODE: Build multi-arch and push to registry
    # ========================================================================
    
    if [[ "$MODE" == "production" ]]; then
        # Validate required environment variables for CI
        REQUIRED_VARS=("GITHUB_SHA" "GITHUB_REF_NAME")
        MISSING_VARS=()
        
        for var in "${REQUIRED_VARS[@]}"; do
            if [ -z "${!var:-}" ]; then
                MISSING_VARS+=("$var")
            fi
        done
        
        if [ ${#MISSING_VARS[@]} -gt 0 ]; then
            log_error "Missing required environment variables for production mode:"
            printf '  - %s\n' "${MISSING_VARS[@]}"
            exit 1
        fi
        
        GIT_SHA="${GITHUB_SHA}"
        GIT_REF="${GITHUB_REF_NAME}"
    else
        # Local mode: use git commands to get info
        log_info "Running in local mode - using git to determine version info"
        GIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        GIT_REF=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    fi
    
    # Determine image tags based on git ref
    TAGS=()
    SHORT_SHA=$(echo "${GIT_SHA}" | cut -c1-7)
    
    if [[ "${GIT_REF}" == "main" ]]; then
        # Main branch: tag with branch-sha and latest
        TAGS+=("${REGISTRY}/${SERVICE_NAME}:main-${SHORT_SHA}")
        TAGS+=("${REGISTRY}/${SERVICE_NAME}:latest")
    elif [[ "${GIT_REF}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+.*$ ]]; then
        # Version tag: use semantic versioning
        VERSION="${GIT_REF#v}"  # Remove 'v' prefix
        TAGS+=("${REGISTRY}/${SERVICE_NAME}:${VERSION}")
        TAGS+=("${REGISTRY}/${SERVICE_NAME}:${VERSION%.*}")  # Major.minor
        TAGS+=("${REGISTRY}/${SERVICE_NAME}:${VERSION%%.*}") # Major only
    else
        # Feature branch or PR: tag with branch-sha
        SAFE_BRANCH=$(echo "${GIT_REF}" | sed 's/[^a-zA-Z0-9._-]/-/g')
        TAGS+=("${REGISTRY}/${SERVICE_NAME}:${SAFE_BRANCH}-${SHORT_SHA}")
        # Also tag as latest for feature branches in local mode
        if [[ "$MODE" == "local" ]]; then
            TAGS+=("${REGISTRY}/${SERVICE_NAME}:latest")
        fi
    fi
    
    # Build Go binary for production
    log_info "Building Go binary for production..."
    if [[ "$SERVICE_NAME" == "ide-orchestrator" ]]; then
        CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
            -ldflags="-w -s -X main.version=${SHORT_SHA}" \
            -o bin/ide-orchestrator \
            ./cmd/api
    fi
    # Note: Other services may not need Go binary build step
    
    # Build Docker image with all tags using buildx for multi-arch
    log_info "Building Docker image for ${PLATFORM}..."
    TAG_ARGS=""
    for tag in "${TAGS[@]}"; do
        TAG_ARGS="${TAG_ARGS} -t ${tag}"
    done
    
    # Use buildx for cross-platform builds
    docker buildx build \
        --platform "${PLATFORM}" \
        -f Dockerfile \
        ${TAG_ARGS} \
        --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        --build-arg GIT_COMMIT="${GIT_SHA}" \
        --push \
        .
    
    log_success "Docker image built and pushed successfully"
    log_info "Pushed tags:"
    for tag in "${TAGS[@]}"; do
        echo "  - ${tag}"
    done
    
    # Update deployment manifest if on main branch (production mode only)
    if [[ "$MODE" == "production" && "${GIT_REF}" == "main" ]]; then
        log_info "Updating deployment manifest for main branch..."
        
        DEPLOYMENT_FILE="platform/claims/intelligence-orchestrator/ide-orchestrator-deployment.yaml"
        NEW_IMAGE="${REGISTRY}/${SERVICE_NAME}:main-${SHORT_SHA}"
        
        if [ -f "$DEPLOYMENT_FILE" ]; then
            # Update image tag in deployment file
            sed -i "s|image: ${REGISTRY}/${SERVICE_NAME}:.*|image: ${NEW_IMAGE}|g" "$DEPLOYMENT_FILE"
            
            log_success "Updated deployment manifest with image: ${NEW_IMAGE}"
            
            # Output for GitHub Actions to commit the change
            echo "DEPLOYMENT_UPDATED=true" >> "${GITHUB_OUTPUT:-/dev/null}"
            echo "NEW_IMAGE=${NEW_IMAGE}" >> "${GITHUB_OUTPUT:-/dev/null}"
        else
            log_error "Deployment file not found: $DEPLOYMENT_FILE"
            exit 1
        fi
    fi
    
    # Output primary image tag for downstream use
    PRIMARY_TAG="${TAGS[0]}"
    echo "PRIMARY_IMAGE=${PRIMARY_TAG}" >> "${GITHUB_OUTPUT:-/dev/null}"
    
    log_success "Build and push completed successfully"
    echo "Primary image: ${PRIMARY_TAG}"
fi
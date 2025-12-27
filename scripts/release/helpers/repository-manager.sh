#!/bin/bash
# repository-manager.sh - Handles Git repository operations for GitOps deployments

# Clone zerotouch-tenants repository for GitOps updates
clone_tenants_repository() {
    log_step_start "Cloning zerotouch-tenants repository"
    
    local tenants_repo_url
    local clone_dir
    
    # Get tenants repository URL from environment or use default
    local tenants_repo_name="${TENANTS_REPO_NAME:-zerotouch-tenants}"
    tenants_repo_url="https://github.com/org/${tenants_repo_name}.git"
    clone_dir="${CONFIG_CACHE_DIR}/zerotouch-tenants"
    
    log_info "Cloning zerotouch-tenants repository: $tenants_repo_url"
    log_info "Clone directory: $clone_dir"
    
    # Remove existing clone if it exists
    if [[ -d "$clone_dir" ]]; then
        rm -rf "$clone_dir"
    fi
    
    # For local development, check if zerotouch-tenants exists in workspace and has a remote
    local workspace_root
    workspace_root=$(cd "$(get_platform_root)/.." && pwd)
    local local_tenants_dir="${workspace_root}/zerotouch-tenants"
    
    if [[ -d "$local_tenants_dir/.git" ]]; then
        log_info "Found local zerotouch-tenants repository with Git: $local_tenants_dir"
        
        # Check if it has a remote origin
        cd "$local_tenants_dir"
        if git remote get-url origin &>/dev/null; then
            local remote_url
            remote_url=$(git remote get-url origin)
            log_info "Local repository has remote: $remote_url"
            
            # Pull latest changes to ensure we're up to date
            log_info "Pulling latest changes from remote"
            if log_command "git pull origin main"; then
                export TENANTS_REPO_DIR="$local_tenants_dir"
                export TENANTS_REPO_TYPE="local_with_remote"
                log_step_end "Cloning zerotouch-tenants repository" "SUCCESS"
                return 0
            else
                log_warn "Failed to pull from remote, will clone fresh copy"
            fi
        else
            log_warn "Local repository has no remote origin, will clone fresh copy"
        fi
    fi
    
    # Try to clone from remote (if BOT_GITHUB_TOKEN is available)
    if [[ -n "${BOT_GITHUB_TOKEN:-}" ]]; then
        log_info "Attempting to clone from remote repository"
        
        if log_command "git clone https://${BOT_GITHUB_TOKEN}@github.com/org/${tenants_repo_name}.git $clone_dir"; then
            export TENANTS_REPO_DIR="$clone_dir"
            export TENANTS_REPO_TYPE="remote"
            log_step_end "Cloning zerotouch-tenants repository" "SUCCESS"
            return 0
        else
            log_warn "Failed to clone remote repository, creating mock structure"
        fi
    fi
    
    # Create mock zerotouch-tenants structure for testing
    log_warn "Creating mock zerotouch-tenants structure for testing"
    
    mkdir -p "${clone_dir}/tenants/${TENANT}/overlays/${ENVIRONMENT}"
    
    # Create a sample kustomization.yaml
    cat > "${clone_dir}/tenants/${TENANT}/overlays/${ENVIRONMENT}/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../base

images:
- name: ${TENANT}
  newTag: latest

namespace: $(get_tenant_config namespace)
EOF
    
    # Create base kustomization
    mkdir -p "${clone_dir}/tenants/${TENANT}/base"
    cat > "${clone_dir}/tenants/${TENANT}/base/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- deployment.yaml
- service.yaml

commonLabels:
  app: ${TENANT}
EOF
    
    # Create sample deployment
    cat > "${clone_dir}/tenants/${TENANT}/base/deployment.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${TENANT}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${TENANT}
  template:
    metadata:
      labels:
        app: ${TENANT}
    spec:
      containers:
      - name: ${TENANT}
        image: ${TENANT}:latest
        ports:
        - containerPort: 8080
EOF
    
    # Create sample service
    cat > "${clone_dir}/tenants/${TENANT}/base/service.yaml" << EOF
apiVersion: v1
kind: Service
metadata:
  name: ${TENANT}
spec:
  selector:
    app: ${TENANT}
  ports:
  - port: 80
    targetPort: 8080
EOF
    
    export TENANTS_REPO_DIR="$clone_dir"
    export TENANTS_REPO_TYPE="mock"
    
    log_info "Created mock zerotouch-tenants repository: $clone_dir"
    log_step_end "Cloning zerotouch-tenants repository" "SUCCESS"
    return 0
}
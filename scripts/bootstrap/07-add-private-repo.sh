#!/bin/bash
set -e

# Script: Add Private Repository Credentials to ArgoCD
# Usage: ./06-add-private-repo.sh <repo-url> <username> <token>
#
# This script adds credentials for private Git repositories to ArgoCD.
# Required before ApplicationSet can access private tenant registries.

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check arguments
if [ "$#" -ne 3 ]; then
    print_error "Usage: $0 <repo-url> <username> <token>"
    echo ""
    echo "Example:"
    echo "  $0 https://github.com/arun4infra/zerotouch-tenants.git myuser ghp_xxxxx"
    echo ""
    echo "Arguments:"
    echo "  repo-url  : Full HTTPS URL of the Git repository"
    echo "  username  : GitHub username"
    echo "  token     : GitHub Personal Access Token (with repo scope)"
    exit 1
fi

REPO_URL="$1"
USERNAME="$2"
TOKEN="$3"

# Extract repository name from URL for secret naming
# Example: https://github.com/arun4infra/zerotouch-tenants.git -> zerotouch-tenants
REPO_NAME=$(echo "$REPO_URL" | sed -E 's|.*/([^/]+)\.git$|\1|')
SECRET_NAME="repo-${REPO_NAME}"

print_info "Adding repository credentials to ArgoCD"
print_info "Repository: $REPO_URL"
print_info "Secret Name: $SECRET_NAME"

# Check if ArgoCD namespace exists
if ! kubectl get namespace argocd &> /dev/null; then
    print_error "ArgoCD namespace not found. Is ArgoCD installed?"
    exit 1
fi

# Check if secret already exists
if kubectl get secret "$SECRET_NAME" -n argocd &> /dev/null; then
    print_warning "Secret $SECRET_NAME already exists in argocd namespace"
    read -p "Do you want to update it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipping update"
        exit 0
    fi
    print_info "Deleting existing secret..."
    kubectl delete secret "$SECRET_NAME" -n argocd
fi

# Create ArgoCD repository secret
print_info "Creating ArgoCD repository secret..."

kubectl create secret generic "$SECRET_NAME" \
    --namespace argocd \
    --from-literal=type=git \
    --from-literal=url="$REPO_URL" \
    --from-literal=username="$USERNAME" \
    --from-literal=password="$TOKEN"

# Add ArgoCD label so it's recognized as a repository credential
kubectl label secret "$SECRET_NAME" \
    -n argocd \
    argocd.argoproj.io/secret-type=repository

print_info "Repository credentials added successfully!"
print_info ""
print_info "Verification:"
echo "  kubectl get secret $SECRET_NAME -n argocd"
echo "  kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository"
print_info ""
print_info "ArgoCD will now be able to access: $REPO_URL"

# Optional: Verify ArgoCD can see the repository
print_info ""
print_info "Waiting 5 seconds for ArgoCD to discover repository..."
sleep 5

# Check if argocd CLI is available
if command -v argocd &> /dev/null; then
    print_info "Verifying repository connection with ArgoCD CLI..."
    if argocd repo list 2>/dev/null | grep -q "$REPO_URL"; then
        print_info "✓ Repository successfully registered with ArgoCD"
    else
        print_warning "Repository not yet visible in ArgoCD. This may take a few moments."
        print_info "You can verify manually with: argocd repo list"
    fi
else
    print_warning "ArgoCD CLI not found. Skipping verification."
    print_info "Install ArgoCD CLI: https://argo-cd.readthedocs.io/en/stable/cli_installation/"
fi

print_info ""
print_info "Done! Repository credentials configured."

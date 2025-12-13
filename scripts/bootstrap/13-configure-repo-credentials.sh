#!/bin/bash
set -e

# Script: Add Private Repository Credentials to ArgoCD
# Usage: ./07-add-private-repo.sh [<repo-url> <username> <token>]
#        ./07-add-private-repo.sh --auto
#
# This script adds credentials for private Git repositories to ArgoCD.
# Required before ApplicationSet can access private tenant registries.
#
# Modes:
#   1. Manual: Provide repo-url, username, and token as arguments
#   2. Auto: Use --auto flag to read from .env.ssm file
#   3. Interactive: Run without arguments to be prompted

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_blue() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_SSM_FILE="$SCRIPT_DIR/../../.env.ssm"

# Function to add a single repository
add_repository() {
    local repo_url="$1"
    local username="$2"
    local token="$3"
    
    # Extract repository name from URL for secret naming
    # Example: https://github.com/arun4infra/zerotouch-tenants.git -> zerotouch-tenants
    local repo_name=$(echo "$repo_url" | sed -E 's|.*/([^/]+)\.git$|\1|')
    local secret_name="repo-${repo_name}"
    
    print_info "Adding repository credentials to ArgoCD"
    print_info "Repository: $repo_url"
    print_info "Secret Name: $secret_name"
    
    # Check if ArgoCD namespace exists
    if ! kubectl get namespace argocd &> /dev/null; then
        print_error "ArgoCD namespace not found. Is ArgoCD installed?"
        return 1
    fi
    
    # Check if secret already exists
    if kubectl get secret "$secret_name" -n argocd &> /dev/null; then
        print_warning "Secret $secret_name already exists in argocd namespace"
        print_info "Skipping (already configured)"
        return 0
    fi
    
    # Create ArgoCD repository secret
    print_info "Creating ArgoCD repository secret..."
    
    kubectl create secret generic "$secret_name" \
        --namespace argocd \
        --from-literal=type=git \
        --from-literal=url="$repo_url" \
        --from-literal=username="$username" \
        --from-literal=password="$token"
    
    # Add ArgoCD label so it's recognized as a repository credential
    kubectl label secret "$secret_name" \
        -n argocd \
        argocd.argoproj.io/secret-type=repository
    
    print_info "✓ Repository credentials added successfully!"
    
    # Optional: Verify ArgoCD can see the repository
    sleep 2
    
    # Check if argocd CLI is available
    if command -v argocd &> /dev/null; then
        if argocd repo list 2>/dev/null | grep -q "$repo_url"; then
            print_info "✓ Repository successfully registered with ArgoCD"
        fi
    fi
    
    return 0
}

# Function to read credentials from .env.ssm
read_credentials_from_env() {
    if [ ! -f "$ENV_SSM_FILE" ]; then
        print_error ".env.ssm file not found at: $ENV_SSM_FILE"
        return 1
    fi
    
    print_blue "Reading GitHub credentials from .env.ssm..."
    
    # Read GitHub credentials
    GITHUB_USERNAME=$(grep "^/zerotouch/prod/platform/github/username=" "$ENV_SSM_FILE" | cut -d'=' -f2)
    GITHUB_TOKEN=$(grep "^/zerotouch/prod/platform/github/token=" "$ENV_SSM_FILE" | cut -d'=' -f2)
    
    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_TOKEN" ]; then
        print_error "GitHub credentials not found in .env.ssm"
        print_info "Required variables:"
        print_info "  /zerotouch/prod/platform/github/username=your-username"
        print_info "  /zerotouch/prod/platform/github/token=ghp_xxxxx"
        return 1
    fi
    
    print_info "✓ Found GitHub credentials"
    
    # Read private repositories
    print_blue "Reading private repositories from .env.ssm..."
    PRIVATE_REPOS=$(grep "^ARGOCD_PRIVATE_REPO_" "$ENV_SSM_FILE" | cut -d'=' -f2)
    
    if [ -z "$PRIVATE_REPOS" ]; then
        print_warning "No private repositories defined in .env.ssm"
        print_info "Add repositories with: ARGOCD_PRIVATE_REPO_1=https://github.com/org/repo.git"
        return 1
    fi
    
    REPO_COUNT=$(echo "$PRIVATE_REPOS" | wc -l | tr -d ' ')
    print_info "✓ Found $REPO_COUNT private repository/repositories"
    
    return 0
}

# Function to check if tenant ApplicationSet exists
check_tenant_appset() {
    if [ -f "$SCRIPT_DIR/../../bootstrap/components/99-tenants.yaml" ]; then
        return 0
    fi
    return 1
}

# Function to validate prerequisites
validate_prerequisites() {
    # Check if tenant ApplicationSet exists
    if check_tenant_appset; then
        print_blue "Found tenant ApplicationSet (99-tenants.yaml)"
        print_blue "This requires private repository credentials"
        return 0
    fi
    return 1
}

# Parse arguments and determine mode
MODE="interactive"
REPO_URL=""
USERNAME=""
TOKEN=""

if [ "$#" -eq 1 ] && [ "$1" = "--auto" ]; then
    MODE="auto"
elif [ "$#" -eq 3 ]; then
    MODE="manual"
    REPO_URL="$1"
    USERNAME="$2"
    TOKEN="$3"
elif [ "$#" -ne 0 ]; then
    print_error "Invalid arguments"
    echo ""
    echo "Usage:"
    echo "  $0 <repo-url> <username> <token>    # Manual mode"
    echo "  $0 --auto                            # Auto mode (read from .env.ssm)"
    echo "  $0                                   # Interactive mode"
    echo ""
    echo "Examples:"
    echo "  Manual:  $0 https://github.com/arun4infra/zerotouch-tenants.git myuser ghp_xxxxx"
    echo "  Auto:    $0 --auto"
    echo ""
    exit 1
fi

# Main execution logic
echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║   DEPRECATION NOTICE                                         ║${NC}"
echo -e "${YELLOW}║   This script is deprecated and only for emergency use.     ║${NC}"
echo -e "${YELLOW}║   Repository credentials are managed via ExternalSecrets.   ║${NC}"
echo -e "${YELLOW}║                                                              ║${NC}"
echo -e "${YELLOW}║   Normal workflow:                                           ║${NC}"
echo -e "${YELLOW}║   1. Add SSM parameters: /zerotouch/prod/argocd/repos/...   ║${NC}"
echo -e "${YELLOW}║   2. Create ExternalSecret manifest in Git                  ║${NC}"
echo -e "${YELLOW}║   3. ArgoCD syncs automatically                              ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   ArgoCD Private Repository Configuration (Emergency)        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Execute based on mode
case "$MODE" in
    manual)
        print_info "Mode: Manual (using provided credentials)"
        add_repository "$REPO_URL" "$USERNAME" "$TOKEN"
        exit_code=$?
        ;;
        
    auto)
        print_info "Mode: Auto (reading from .env.ssm)"
        
        # Validate prerequisites
        validate_prerequisites
        
        # Read credentials and repositories from .env.ssm
        if ! read_credentials_from_env; then
            print_error "Failed to read credentials from .env.ssm"
            echo ""
            print_info "To configure .env.ssm:"
            echo "  1. cp .env.ssm.example .env.ssm"
            echo "  2. Edit .env.ssm and set:"
            echo "     /zerotouch/prod/platform/github/username=your-username"
            echo "     /zerotouch/prod/platform/github/token=ghp_xxxxx"
            echo "     ARGOCD_PRIVATE_REPO_1=https://github.com/org/repo.git"
            exit 1
        fi
        
        # Add each repository
        exit_code=0
        while IFS= read -r repo_url; do
            if [ -n "$repo_url" ]; then
                echo ""
                if ! add_repository "$repo_url" "$GITHUB_USERNAME" "$GITHUB_TOKEN"; then
                    exit_code=1
                fi
            fi
        done <<< "$PRIVATE_REPOS"
        ;;
        
    interactive)
        print_info "Mode: Interactive"
        echo ""
        
        # Check if .env.ssm exists and offer auto mode
        if [ -f "$ENV_SSM_FILE" ]; then
            print_info "Found .env.ssm file"
            read -p "Do you want to use credentials from .env.ssm? (Y/n): " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                # Switch to auto mode
                if read_credentials_from_env; then
                    exit_code=0
                    while IFS= read -r repo_url; do
                        if [ -n "$repo_url" ]; then
                            echo ""
                            if ! add_repository "$repo_url" "$GITHUB_USERNAME" "$GITHUB_TOKEN"; then
                                exit_code=1
                            fi
                        fi
                    done <<< "$PRIVATE_REPOS"
                else
                    print_error "Failed to read from .env.ssm, falling back to manual input"
                    exit_code=1
                fi
            else
                # Manual input
                echo ""
                read -p "Repository URL: " REPO_URL
                read -p "Username: " USERNAME
                read -sp "Token: " TOKEN
                echo ""
                echo ""
                add_repository "$REPO_URL" "$USERNAME" "$TOKEN"
                exit_code=$?
            fi
        else
            # No .env.ssm, prompt for manual input
            print_warning ".env.ssm file not found"
            echo ""
            read -p "Repository URL: " REPO_URL
            read -p "Username: " USERNAME
            read -sp "Token: " TOKEN
            echo ""
            echo ""
            add_repository "$REPO_URL" "$USERNAME" "$TOKEN"
            exit_code=$?
        fi
        ;;
esac

# Final summary
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Configuration Complete                                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $exit_code -eq 0 ]; then
    print_info "✓ All repository credentials configured successfully"
    echo ""
    print_info "Verification commands:"
    echo "  kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository"
    echo "  argocd repo list"
else
    print_error "Some repositories failed to configure"
    exit 1
fi

echo ""
exit $exit_code

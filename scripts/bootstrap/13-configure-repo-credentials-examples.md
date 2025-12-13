# Add Private Repository Credentials to ArgoCD
# This script adds Git repository credentials so ArgoCD can access private repos

# Basic usage
./scripts/bootstrap/07-add-private-repo.sh <repo-url> <username> <token>

# Example 1: Add tenant registry repository
./scripts/bootstrap/07-add-private-repo.sh \
  https://github.com/arun4infra/zerotouch-tenants.git \
  arun4infra \
  ghp_1234567890abcdefghijklmnopqrstuvwxyz

# Example 2: Add bizmatters repository
./scripts/bootstrap/07-add-private-repo.sh \
  https://github.com/arun4infra/bizmatters.git \
  arun4infra \
  ghp_1234567890abcdefghijklmnopqrstuvwxyz

# Example 3: Add multiple repositories with same token
TOKEN="ghp_xxxxx"
USERNAME="arun4infra"

./scripts/bootstrap/07-add-private-repo.sh \
  https://github.com/arun4infra/zerotouch-tenants.git \
  $USERNAME \
  $TOKEN

./scripts/bootstrap/07-add-private-repo.sh \
  https://github.com/arun4infra/bizmatters.git \
  $USERNAME \
  $TOKEN

# Verify secrets were created
kubectl get secret -n argocd | grep repo-

# Check ArgoCD recognizes repositories
argocd repo list

# Update existing credentials (script will prompt for confirmation)
./scripts/bootstrap/07-add-private-repo.sh \
  https://github.com/arun4infra/zerotouch-tenants.git \
  arun4infra \
  ghp_new_token_here

# Troubleshooting: Check secret details
kubectl get secret repo-zerotouch-tenants -n argocd -o yaml

# Troubleshooting: Verify label is set
kubectl get secret repo-zerotouch-tenants -n argocd -o jsonpath='{.metadata.labels}'

# Creating GitHub Personal Access Token:
# 1. Go to GitHub → Settings → Developer settings → Personal access tokens
# 2. Generate new token (classic)
# 3. Select scopes: repo, read:packages
# 4. Copy token immediately

# Install ArgoCD
# This script installs ArgoCD and creates the platform-bootstrap Application

# Basic usage
./scripts/bootstrap/03-install-argocd.sh

# The script will:
# 1. Install ArgoCD in argocd namespace
# 2. Wait for ArgoCD to be ready
# 3. Create platform-bootstrap Application
# 4. Extract admin password

# Verify ArgoCD installation
kubectl get pods -n argocd
kubectl get application -n argocd

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port-forward to access ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Open browser to https://localhost:8080
# Username: admin
# Password: (from command above)

# Check platform-bootstrap Application status
kubectl get application platform-bootstrap -n argocd
kubectl describe application platform-bootstrap -n argocd

# Verify child Applications were created
kubectl get application -n argocd

# Expected Applications:
# - crossplane-operator
# - external-secrets
# - keda
# - kagent
# - intelligence
# - foundation-config
# - databases

# Troubleshooting: Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100

# Troubleshooting: Restart ArgoCD if needed
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout restart deployment argocd-application-controller -n argocd

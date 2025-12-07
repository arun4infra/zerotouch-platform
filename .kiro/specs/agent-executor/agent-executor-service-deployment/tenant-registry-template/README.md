# Tenant Registry Template

This directory contains template files for the `zerotouch-tenants` repository.

## Setup Instructions

1. **Create GitHub Repository**
   ```bash
   # Create private repository: zerotouch-tenants
   # Via GitHub UI or gh CLI:
   gh repo create zerotouch-tenants --private
   ```

2. **Initialize Repository**
   ```bash
   git clone https://github.com/arun4infra/zerotouch-tenants.git
   cd zerotouch-tenants
   
   # Copy template files from this directory
   cp -r <path-to-this-template>/* .
   
   git add .
   git commit -m "Initial commit: Tenant registry structure"
   git push origin main
   ```

3. **Add Tenant Configuration**
   ```bash
   # Copy example to create new tenant
   cp -r tenants/example tenants/bizmatters
   
   # Edit tenants/bizmatters/config.yaml with actual values
   vim tenants/bizmatters/config.yaml
   
   git add tenants/bizmatters/
   git commit -m "Add bizmatters tenant"
   git push origin main
   ```

4. **Configure Repository Credentials via ExternalSecrets**

   Repository credentials are synced from AWS SSM, not added imperatively.

   **In zerotouch-platform repo:**
   ```bash
   cd zerotouch-platform

   # Edit .env.ssm with repository credentials
   cat >> .env.ssm <<EOF
   /zerotouch/prod/argocd/repos/zerotouch-tenants/url=https://github.com/arun4infra/zerotouch-tenants.git
   /zerotouch/prod/argocd/repos/zerotouch-tenants/username=arun4infra
   /zerotouch/prod/argocd/repos/zerotouch-tenants/password=ghp_xxxxx

   /zerotouch/prod/argocd/repos/bizmatters/url=https://github.com/arun4infra/bizmatters.git
   /zerotouch/prod/argocd/repos/bizmatters/username=arun4infra
   /zerotouch/prod/argocd/repos/bizmatters/password=ghp_xxxxx
   EOF

   # Inject to SSM
   ./scripts/bootstrap/06-inject-ssm-parameters.sh
   ```

   **In zerotouch-tenants repo:**
   ```bash
   cd zerotouch-tenants

   # Create ExternalSecret for bizmatters repo
   mkdir -p repositories
   cat > repositories/bizmatters-repo.yaml <<EOF
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: repo-bizmatters
     namespace: argocd
   spec:
     refreshInterval: 1h
     secretStoreRef:
       name: aws-parameter-store
       kind: ClusterSecretStore
     target:
       name: repo-bizmatters
       template:
         metadata:
           labels:
             argocd.argoproj.io/secret-type: repository
         data:
           type: git
           url: "{{ .url }}"
           username: "{{ .username }}"
           password: "{{ .password }}"
     data:
       - secretKey: url
         remoteRef:
           key: /zerotouch/prod/argocd/repos/bizmatters/url
       - secretKey: username
         remoteRef:
           key: /zerotouch/prod/argocd/repos/bizmatters/username
       - secretKey: password
         remoteRef:
           key: /zerotouch/prod/argocd/repos/bizmatters/password
   EOF

   git add repositories/
   git commit -m "Add bizmatters repository credentials"
   git push
   ```

   ExternalSecrets sync automatically during bootstrap.
   See: [Private Repository Architecture](https://github.com/arun4infra/zerotouch-platform/blob/main/docs/architecture/private-repository-architecture.md)

5. **Deploy ApplicationSet**
   ```bash
   # Apply ApplicationSet to ArgoCD
   kubectl apply -f bootstrap/components/99-tenants.yaml
   
   # Verify ApplicationSet created
   kubectl get applicationset tenant-applications -n argocd
   
   # Wait for Application to be discovered
   kubectl get application -n argocd
   # Should see: bizmatters-workloads
   ```

## Directory Structure

```
zerotouch-tenants/
├── README.md
└── tenants/
    ├── example/
    │   └── config.yaml.example
    └── bizmatters/
        └── config.yaml
```

## Tenant Config Format

Each tenant directory must contain a `config.yaml` file:

```yaml
# Tenant identifier (used as Application name)
tenant: bizmatters-workloads

# Git repository containing tenant workloads
repoURL: https://github.com/arun4infra/bizmatters.git

# Branch or tag to sync
targetRevision: main

# Path within repository to Kubernetes manifests
path: services/agent_executor/platform

# Optional: Target namespace (defaults to "default")
namespace: intelligence-deepagents
```

## Adding New Tenants

1. Create new directory: `tenants/<tenant-name>/`
2. Create `config.yaml` with tenant configuration
3. Commit and push
4. ApplicationSet automatically discovers and creates Application
5. ArgoCD syncs tenant workloads

## Security Notes

- This repository is **private** - contains tenant configurations
- Repository credentials must be added to ArgoCD before ApplicationSet deployment
- Each tenant repository must also have credentials configured in ArgoCD
- Use GitHub Personal Access Tokens with minimal scopes (read:packages, repo)

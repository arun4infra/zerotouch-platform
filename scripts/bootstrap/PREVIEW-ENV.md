# Preview Environment Bootstrap

This document describes the preview environment setup for GitHub Actions integration testing.

## Overview

The preview environment uses **Kind (Kubernetes in Docker)** to create ephemeral clusters for testing. It's optimized for CI/CD with minimal resource requirements and fast bootstrap times.

## Architecture

```
GitHub Actions Runner
  └─ Kind Cluster (zerotouch-preview)
      ├─ ArgoCD (syncs from GitHub)
      ├─ External Secrets Operator (AWS SSM)
      ├─ Core Platform (kagent, databases, keda)
      └─ Test Services (deepagents-runtime)
```

## Key Differences from Production

| Component | Production | Preview |
|-----------|-----------|---------|
| **Cluster** | Talos Linux | Kind |
| **Networking** | Cilium | kindnet (built-in) |
| **Storage** | Rook/Ceph | local-path-provisioner |
| **Secrets** | Full SSM params | Core secrets only |
| **Tenant Repos** | Required | Optional (skipped) |

## Bootstrap Flow

1. **Setup Preview Cluster** (`helpers/setup-preview.sh`)
   - Creates Kind cluster with port mappings
   - Installs kubectl, helm, kind
   - Labels nodes for workload placement

2. **Inject ESO Secrets** (`07-inject-eso-secrets.sh`)
   - Injects AWS credentials with **session token** (OIDC support)
   - Creates `aws-access-token` secret in `external-secrets` namespace

3. **Inject SSM Parameters** (`08-inject-ssm-parameters.sh`)
   - Generates `.env.ssm` from environment variables
   - Creates core SSM parameters (LLM keys, GHCR credentials)
   - **Skips tenant repository credentials** (not needed for testing)

4. **Install ArgoCD** (`09-install-argocd.sh`)
   - Deploys ArgoCD with standard configuration
   - Syncs platform from GitHub repository

5. **Fix Kind Conflicts** (`helpers/fix-kind-conflicts.sh`)
   - Deletes `local-path-provisioner` deployment (immutable field fix)
   - Allows ArgoCD to recreate with correct labels

6. **Verify ESO** (`11-verify-eso.sh`)
   - Forces re-sync of all ExternalSecrets
   - **Tolerates tenant repository failures** (expected in preview)
   - Validates core secrets: LLM keys, GHCR credentials
   - **Early exit** when only tenant repos are pending (100s timeout)

7. **Wait for Apps** (`12a-wait-apps-healthy.sh`)
   - Waits for applications to be Synced & Healthy
   - **Preview mode tolerance**: Skips `cilium`, `argocd-repo-credentials`
   - Requires: `apis`, `intelligence`, `kagent`, `databases`, etc.

## Environment Variables Required

```bash
# AWS Credentials (OIDC from GitHub Actions)
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN  # Required for OIDC

# LLM API Keys
OPENAI_API_KEY
ANTHROPIC_API_KEY

# GitHub Credentials
PAT_GITHUB_USER
PAT_GITHUB
```

## Known Limitations

- **Cilium**: Excluded (Kind uses kindnet)
- **Tenant Repositories**: ExternalSecrets fail without SSM params (acceptable)
- **Performance**: Slower than production (single node, limited resources)
- **Persistence**: Ephemeral - cluster destroyed after tests

## Troubleshooting

### ESO Secrets Failing
- Check AWS credentials include session token
- Verify SSM parameters exist: `aws ssm get-parameters-by-path --path /zerotouch/prod`

### Applications Degraded
- Check pod status: `kubectl get pods -A`
- View application details: `kubectl describe application <name> -n argocd`

### Timeout Issues
- Increase timeout: `--timeout 900` (15 minutes)
- Check resource constraints on GitHub Actions runner

## Usage

```bash
# Run bootstrap in preview mode
./scripts/bootstrap/01-master-bootstrap.sh --mode preview

# Cleanup
kind delete cluster --name zerotouch-preview
```

## Files

- `helpers/setup-preview.sh` - Kind cluster setup
- `helpers/fix-kind-conflicts.sh` - Fix immutable field errors
- `07-inject-eso-secrets.sh` - AWS credentials with session token
- `11-verify-eso.sh` - ESO verification with preview tolerance
- `12a-wait-apps-healthy.sh` - App health check with preview mode

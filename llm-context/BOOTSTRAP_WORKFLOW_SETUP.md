# Bootstrap Cluster Workflow Setup

## Overview

The `bootstrap-cluster.yaml` workflow automates the complete cluster bootstrap process, including:
1. Enabling rescue mode on Hetzner servers
2. Waiting for servers to reboot
3. Running the full bootstrap sequence

## Required GitHub Secrets

Configure these secrets in your GitHub repository settings (`Settings > Secrets and variables > Actions`):

### Infrastructure Secrets (Required)

| Secret | Description | How to Get |
|--------|-------------|------------|
| `HETZNER_API_TOKEN` | Hetzner Cloud API token | [Hetzner Console](https://console.hetzner.cloud) > Security > API Tokens |
| `AWS_ACCESS_KEY_ID` | AWS access key for SSM | AWS IAM Console |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key for SSM | AWS IAM Console |

### GitHub Credentials (Required)

| Secret | Description | How to Get |
|--------|-------------|------------|
| `BOT_GITHUB_USERNAME` | GitHub username | Your GitHub username |
| `BOT_GITHUB_TOKEN` | GitHub PAT with `repo` + `read:packages` | [GitHub Tokens](https://github.com/settings/tokens) |
| `TENANTS_REPO_NAME` | Tenant repository name (e.g., `zerotouch-tenants`) | Your repo name |

### API Keys (Optional - for LLM services)

| Secret | Description | How to Get |
|--------|-------------|------------|
| `OPENAI_API_KEY` | OpenAI API key | [OpenAI Platform](https://platform.openai.com/api-keys) |
| `ANTHROPIC_API_KEY` | Anthropic API key | [Anthropic Console](https://console.anthropic.com/) |

## Environment Variable Mapping

The workflow generates `.env.ssm` from secrets using this mapping:

```
Secret Name                    -> SSM Parameter Path
─────────────────────────────────────────────────────────────
OPENAI_API_KEY                 -> /zerotouch/prod/openai_api_key
ANTHROPIC_API_KEY              -> /zerotouch/prod/anthropic_api_key
BOT_GITHUB_USERNAME            -> /zerotouch/prod/github/username
BOT_GITHUB_TOKEN               -> /zerotouch/prod/github/token
BOT_GITHUB_USERNAME            -> /zerotouch/prod/ghcr/username
BOT_GITHUB_TOKEN               -> /zerotouch/prod/ghcr/password
TENANTS_REPO_URL (auto-built)  -> /zerotouch/prod/argocd/repos/zerotouch-tenants/url
BOT_GITHUB_USERNAME            -> /zerotouch/prod/argocd/repos/zerotouch-tenants/username
BOT_GITHUB_TOKEN               -> /zerotouch/prod/argocd/repos/zerotouch-tenants/password
```

## Minimum Required Secrets

For a basic bootstrap, you need:

1. `HETZNER_API_TOKEN` - For server management
2. `AWS_ACCESS_KEY_ID` - For ESO/SSM
3. `AWS_SECRET_ACCESS_KEY` - For ESO/SSM
4. `BOT_GITHUB_USERNAME` - GitHub username
5. `BOT_GITHUB_TOKEN` - GitHub token for ArgoCD
6. `TENANTS_REPO_NAME` - Tenant repository name

## Workflow Inputs

When running the workflow manually:

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `environment` | Choice | dev | Environment to bootstrap (dev/staging/production) |
| `skip_rescue_mode` | Boolean | false | Skip rescue mode if servers already in rescue mode |

## Usage

1. Go to your repository on GitHub
2. Click `Actions` tab
3. Select `Bootstrap Cluster` workflow
4. Click `Run workflow` button
5. Select environment and options
6. Click `Run workflow`

## Security Notes

- Scripts detect `CI=true` and mask password output
- GitHub automatically masks secrets in logs
- Credentials are not logged

## Local Testing

```bash
export HETZNER_API_TOKEN="your-token"
export BOT_GITHUB_USERNAME="your-username"
export BOT_GITHUB_TOKEN="your-token"

./scripts/bootstrap/00-enable-rescue-mode.sh dev -y
sleep 90
./scripts/bootstrap/01-master-bootstrap.sh dev
```

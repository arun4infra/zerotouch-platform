# Environment Variables Setup Guide

## Required GitHub Secrets

The Twin Docs Workflow requires the following secrets to be configured in your GitHub repository.

### 1. OpenAI API Key

**Secret Name:** `OPENAI_API_KEY`

**Purpose:** Used by both Validator and Documentor agents to call OpenAI's gpt-4-mini model

**How to Get:**
1. Go to https://platform.openai.com/api-keys
2. Click "Create new secret key"
3. Copy the key (starts with `sk-...`)

**How to Add to GitHub:**
```bash
# Via GitHub CLI
gh secret set OPENAI_API_KEY

# Or via GitHub UI:
# 1. Go to your repository
# 2. Settings → Secrets and variables → Actions
# 3. Click "New repository secret"
# 4. Name: OPENAI_API_KEY
# 5. Value: <paste your key>
# 6. Click "Add secret"
```

---

### 2. GitHub Bot Token

**Secret Name:** `BOT_GITHUB_TOKEN`

**Note:** Secret names cannot start with `GITHUB_` (reserved prefix)

**Purpose:** Used by agents to:
- Read PR files and comments
- Post gatekeeper/summary comments
- Commit Twin Docs to PR branches
- Re-trigger workflows after commits

**Important:** Do NOT use the default `GITHUB_TOKEN` - it cannot re-trigger workflows!

**How to Get (Option A - Personal Access Token):**
1. Go to https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Select scopes:
   - `repo` (full control of private repositories)
   - `workflow` (update GitHub Action workflows)
4. Click "Generate token"
5. Copy the token (starts with `ghp_...`)

**How to Get (Option B - GitHub App - Recommended for Organizations):**
1. Create a GitHub App in your organization
2. Grant permissions:
   - Repository permissions:
     - Contents: Read and write
     - Pull requests: Read and write
     - Issues: Read and write
     - Workflows: Read and write
3. Install the app on your repository
4. Generate a private key
5. Use the app ID and private key to generate installation tokens

**How to Add to GitHub:**
```bash
# Via GitHub CLI
gh secret set BOT_GITHUB_TOKEN

# Or via GitHub UI:
# 1. Go to your repository
# 2. Settings → Secrets and variables → Actions
# 3. Click "New repository secret"
# 4. Name: BOT_GITHUB_TOKEN
# 5. Value: <paste your token>
# 6. Click "Add secret"
```

---

### 3. Qdrant Cloud URL

**Secret Name:** `QDRANT_URL`

**Purpose:** Endpoint for Qdrant Cloud vector database (used by Documentor agent for semantic search)

**Format:** `https://<your-cluster>.cloud.qdrant.io:6333`

**How to Get:**
1. Sign up at https://cloud.qdrant.io/
2. Create a new cluster
3. Copy the cluster URL from the dashboard

**How to Add to GitHub:**
```bash
# Via GitHub CLI
gh secret set QDRANT_URL

# Or via GitHub UI:
# 1. Go to your repository
# 2. Settings → Secrets and variables → Actions
# 3. Click "New repository secret"
# 4. Name: QDRANT_URL
# 5. Value: https://<your-cluster>.cloud.qdrant.io:6333
# 6. Click "Add secret"
```

---

### 4. Qdrant Cloud API Key

**Secret Name:** `QDRANT_API_KEY`

**Purpose:** Authentication for Qdrant Cloud (used by Documentor agent)

**How to Get:**
1. Go to your Qdrant Cloud dashboard
2. Navigate to your cluster settings
3. Go to "API Keys" section
4. Click "Create API Key"
5. Copy the key

**How to Add to GitHub:**
```bash
# Via GitHub CLI
gh secret set QDRANT_API_KEY

# Or via GitHub UI:
# 1. Go to your repository
# 2. Settings → Secrets and variables → Actions
# 3. Click "New repository secret"
# 4. Name: QDRANT_API_KEY
# 5. Value: <paste your key>
# 6. Click "Add secret"
```

---

## Quick Setup Script

Run this script to set all secrets at once (you'll be prompted for each value):

```bash
#!/bin/bash
# setup-secrets.sh

echo "Setting up GitHub Secrets for Twin Docs Workflow"
echo "================================================"
echo ""

echo "1. OpenAI API Key"
echo "   Get from: https://platform.openai.com/api-keys"
gh secret set OPENAI_API_KEY

echo ""
echo "2. GitHub Bot Token"
echo "   Get from: https://github.com/settings/tokens"
echo "   Required scopes: repo, workflow"
gh secret set BOT_GITHUB_TOKEN

echo ""
echo "3. Qdrant Cloud URL"
echo "   Format: https://<cluster>.cloud.qdrant.io:6333"
gh secret set QDRANT_URL

echo ""
echo "4. Qdrant Cloud API Key"
echo "   Get from: Qdrant Cloud dashboard → API Keys"
gh secret set QDRANT_API_KEY

echo ""
echo "✅ All secrets configured!"
echo ""
echo "Verify with: gh secret list"
```

**Usage:**
```bash
chmod +x setup-secrets.sh
./setup-secrets.sh
```

---

## Verification

After adding all secrets, verify they're configured:

```bash
# List all secrets
gh secret list

# Expected output:
# BOT_GITHUB_TOKEN    Updated YYYY-MM-DD
# OPENAI_API_KEY      Updated YYYY-MM-DD
# QDRANT_API_KEY      Updated YYYY-MM-DD
# QDRANT_URL          Updated YYYY-MM-DD
```

---

## How Agents Access These Secrets

### In GitHub Actions Workflow

The workflow passes secrets to agents as environment variables:

```yaml
# .github/workflows/librarian.yml
env:
  OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
  GITHUB_TOKEN: ${{ secrets.BOT_GITHUB_TOKEN }}
  QDRANT_URL: ${{ secrets.QDRANT_URL }}
  QDRANT_API_KEY: ${{ secrets.QDRANT_API_KEY }}

jobs:
  validate:
    steps:
      - name: Run Validator
        uses: ./.github/actions/validator
        with:
          pr_number: ${{ github.event.pull_request.number }}
          github_token: ${{ secrets.BOT_GITHUB_TOKEN }}
          openai_api_key: ${{ secrets.OPENAI_API_KEY }}
```

### In Agent Code

Agents read environment variables:

```python
# validator.py
import os

openai_api_key = os.environ["OPENAI_API_KEY"]
github_token = os.environ["GITHUB_TOKEN"]

# documentor.py
import os

openai_api_key = os.environ["OPENAI_API_KEY"]
github_token = os.environ["GITHUB_TOKEN"]
qdrant_url = os.environ["QDRANT_URL"]
qdrant_api_key = os.environ["QDRANT_API_KEY"]
```

### In MCP Servers

MCP servers receive credentials via environment variables:

```python
# Starting GitHub MCP server
github_mcp_process = subprocess.Popen(
    ["npx", "-y", "@modelcontextprotocol/server-github"],
    env={
        "GITHUB_PERSONAL_ACCESS_TOKEN": os.environ["GITHUB_TOKEN"]
    }
)

# Starting Qdrant MCP server
qdrant_mcp_process = subprocess.Popen(
    ["python", "-m", "mcp_server_qdrant"],
    env={
        "QDRANT_URL": os.environ["QDRANT_URL"],
        "QDRANT_API_KEY": os.environ["QDRANT_API_KEY"],
        "COLLECTION_NAME": "documentation"
    }
)
```

---

## Security Best Practices

1. **Never commit secrets to Git**
   - Add `.env` to `.gitignore`
   - Use GitHub Secrets for CI/CD
   - Use External Secrets Operator for cluster deployments

2. **Rotate tokens regularly**
   - OpenAI API keys: Every 90 days
   - GitHub tokens: Every 90 days
   - Qdrant API keys: Every 90 days

3. **Use minimal permissions**
   - GitHub token: Only `repo` and `workflow` scopes
   - Qdrant API key: Only access to `documentation` collection

4. **Monitor usage**
   - Set up billing alerts for OpenAI
   - Monitor GitHub API rate limits
   - Monitor Qdrant Cloud usage

---

## Troubleshooting

### "Secret not found" error

**Problem:** Workflow fails with "secret not found"

**Solution:**
```bash
# Check if secret exists
gh secret list

# If missing, add it
gh secret set SECRET_NAME
```

### "Invalid API key" error

**Problem:** Agent fails with authentication error

**Solution:**
1. Verify the secret value is correct
2. Check for extra spaces or newlines
3. Regenerate the key if needed
4. Update the secret:
   ```bash
   gh secret set SECRET_NAME --body "new-value"
   ```

### "Workflow not re-triggered" error

**Problem:** Documentor commits don't re-trigger validation

**Solution:**
- Ensure you're using `BOT_GITHUB_TOKEN` (PAT or App token)
- Do NOT use default `GITHUB_TOKEN`
- Verify token has `workflow` scope

---

## Summary

**Required Secrets:**
1. `OPENAI_API_KEY` - OpenAI API key for gpt-4-mini
2. `BOT_GITHUB_TOKEN` - GitHub PAT or App token (NOT default GITHUB_TOKEN)
3. `QDRANT_URL` - Qdrant Cloud endpoint
4. `QDRANT_API_KEY` - Qdrant Cloud API key

**Setup Command:**
```bash
gh secret set OPENAI_API_KEY
gh secret set BOT_GITHUB_TOKEN
gh secret set QDRANT_URL
gh secret set QDRANT_API_KEY
```

**Verification:**
```bash
gh secret list
```

**Next Steps:**
After setting up secrets, proceed with implementing the agents according to the tasks document.

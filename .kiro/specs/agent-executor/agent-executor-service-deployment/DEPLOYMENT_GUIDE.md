# Agent Executor Deployment Guide

This guide walks through deploying the agent-executor service using the ApplicationSet + Tenant Registry pattern.

## Prerequisites

- [x] Kubernetes cluster running
- [x] ArgoCD installed and configured
- [x] Crossplane installed with provider-kubernetes
- [x] External Secrets Operator (ESO) installed
- [x] KEDA installed
- [x] NATS with JetStream installed
- [ ] GitHub Personal Access Token with `read:packages` and `repo` scopes
- [ ] AWS credentials configured for ESO

## Phase 1: Platform Infrastructure (One-Time Setup)

### 1.1 Update Crossplane XRDs and Compositions

```bash
cd zerotouch-platform

# Apply updated XRDs
kubectl apply -f platform/05-databases/definitions/postgres-xrd.yaml
kubectl apply -f platform/05-databases/definitions/dragonfly-xrd.yaml

# Apply updated Compositions
kubectl apply -f platform/05-databases/compositions/postgres-composition.yaml
kubectl apply -f platform/05-databases/compositions/dragonfly-composition.yaml

# Verify
kubectl get xrd
kubectl get composition
```

### 1.2 Configure AWS SSM Parameters

```bash
cd zerotouch-platform

# Copy template
cp .env.ssm.example .env.ssm

# Edit .env.ssm with actual values:
# - GitHub username and PAT token
# - OpenAI API key
# - Anthropic API key
vim .env.ssm

# Inject parameters to AWS SSM
./scripts/bootstrap/06-inject-ssm-parameters.sh

# Verify
aws ssm get-parameters-by-path \
  --path /zerotouch/prod \
  --recursive \
  --region ap-south-1 \
  --query 'Parameters[*].[Name,Type]' \
  --output table
```

Expected parameters:
```
/zerotouch/prod/platform/ghcr/username
/zerotouch/prod/platform/ghcr/password
/zerotouch/prod/agent-executor/openai_api_key
/zerotouch/prod/agent-executor/anthropic_api_key
```

## Phase 2: Tenant Registry Setup

### 2.1 Create Tenant Registry Repository

```bash
# Create private GitHub repository
gh repo create zerotouch-tenants --private

# Clone repository
git clone https://github.com/arun4infra/zerotouch-tenants.git
cd zerotouch-tenants

# Copy template files
cp -r ../zerotouch-platform/.kiro/specs/agent-executor/agent-executor-service-deployment/tenant-registry-template/* .

# Commit and push
git add .
git commit -m "Initial commit: Tenant registry structure"
git push origin main
```

### 2.2 Configure ArgoCD Repository Credentials via ExternalSecrets

**CRITICAL**: Add credentials BEFORE deploying ApplicationSet to avoid sync failures.

Repository credentials are managed via ExternalSecrets syncing from AWS SSM.

**Step 1: Add SSM Parameters**

Edit `.env.ssm` in the platform repo:

```bash
cd zerotouch-platform

cat >> .env.ssm <<EOF
# Tenant Registry Credentials
/zerotouch/prod/argocd/repos/zerotouch-tenants/url=https://github.com/arun4infra/zerotouch-tenants.git
/zerotouch/prod/argocd/repos/zerotouch-tenants/username=arun4infra
/zerotouch/prod/argocd/repos/zerotouch-tenants/password=ghp_xxxxx

# Bizmatters Repository Credentials
/zerotouch/prod/argocd/repos/bizmatters/url=https://github.com/arun4infra/bizmatters.git
/zerotouch/prod/argocd/repos/bizmatters/username=arun4infra
/zerotouch/prod/argocd/repos/bizmatters/password=ghp_xxxxx
EOF
```

**Step 2: Inject to AWS SSM**

```bash
./scripts/bootstrap/06-inject-ssm-parameters.sh

# Verify
aws ssm get-parameter --name /zerotouch/prod/argocd/repos/zerotouch-tenants/url
aws ssm get-parameter --name /zerotouch/prod/argocd/repos/bizmatters/url
```

**Step 3: ExternalSecrets Sync (Automatic)**

During bootstrap, ExternalSecrets automatically:
1. Read credentials from SSM
2. Create ArgoCD repository secrets
3. Label secrets with `argocd.argoproj.io/secret-type=repository`

**Verify:**
```bash
# Check ExternalSecrets synced
kubectl get externalsecret -n argocd

# Check repository secrets created
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository

# Verify with ArgoCD
argocd repo list
```

Expected secrets:
```
repo-zerotouch-tenants
repo-bizmatters
```

**Architecture:** See [Private Repository Architecture](../../../docs/architecture/private-repository-architecture.md) for detailed flow.

### 2.3 Deploy ApplicationSet

```bash
cd zerotouch-platform

# Apply ApplicationSet
kubectl apply -f bootstrap/components/99-tenants.yaml

# Verify ApplicationSet created
kubectl get applicationset tenant-applications -n argocd

# Check for generated Applications (may take 1-3 minutes)
kubectl get application -n argocd
```

Expected output:
```
NAME                   SYNC STATUS   HEALTH STATUS
bizmatters-workloads   Synced        Healthy
```

## Phase 3: Verify Deployment

### 3.1 Check Namespace

```bash
kubectl get namespace intelligence-deepagents

# Verify labels
kubectl get namespace intelligence-deepagents -o yaml | grep -A 5 labels
```

Expected labels:
```yaml
labels:
  name: intelligence-deepagents
  layer: intelligence
  category: deepagents
```

### 3.2 Check Crossplane Claims

```bash
# Check PostgreSQL claim
kubectl get postgresinstance agent-executor-db -n intelligence-deepagents

# Check Dragonfly claim
kubectl get dragonflyinstance agent-executor-cache -n intelligence-deepagents

# Verify secrets created
kubectl get secret agent-executor-postgres -n intelligence-deepagents
kubectl get secret agent-executor-dragonfly -n intelligence-deepagents

# Inspect secret keys
kubectl get secret agent-executor-postgres -n intelligence-deepagents -o jsonpath='{.data}' | jq 'keys'
# Should show: ["database", "endpoint", "password", "port", "username"]

kubectl get secret agent-executor-dragonfly -n intelligence-deepagents -o jsonpath='{.data}' | jq 'keys'
# Should show: ["endpoint", "password", "port"]
```

### 3.3 Check ExternalSecrets

```bash
# Check ExternalSecrets
kubectl get externalsecret -n intelligence-deepagents

# Verify sync status
kubectl get externalsecret -n intelligence-deepagents -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'
# All should be "True"

# Check generated secrets
kubectl get secret agent-executor-llm-keys -n intelligence-deepagents
kubectl get secret ghcr-pull-secret -n intelligence-deepagents
```

### 3.4 Check NATS Stream

```bash
# Check Job completed
kubectl get job create-agent-execution-stream -n intelligence-deepagents

# Verify stream exists
kubectl exec -n nats nats-0 -- nats stream info AGENT_EXECUTION

# Verify consumer exists
kubectl exec -n nats nats-0 -- nats consumer info AGENT_EXECUTION agent-executor-workers
```

### 3.5 Check Deployment

```bash
# Check Deployment
kubectl get deployment agent-executor -n intelligence-deepagents

# Check pods
kubectl get pods -n intelligence-deepagents

# Check init container logs (migrations)
kubectl logs -n intelligence-deepagents <pod-name> -c run-migrations

# Check main container logs
kubectl logs -n intelligence-deepagents <pod-name> -c agent-executor -f
```

Expected log messages:
```
agent_executor_service_starting
NATS connection established
Listening for messages on agent.execute.*
```

### 3.6 Check Service and KEDA

```bash
# Check Service
kubectl get service agent-executor -n intelligence-deepagents

# Check KEDA ScaledObject
kubectl get scaledobject agent-executor-scaler -n intelligence-deepagents

# Check HPA created by KEDA
kubectl get hpa -n intelligence-deepagents
```

## Phase 4: Test End-to-End

### 4.1 Test Health Endpoints

```bash
# Port-forward to pod
kubectl port-forward -n intelligence-deepagents <pod-name> 8080:8080

# In another terminal:
# Test health
curl http://localhost:8080/health

# Test readiness
curl http://localhost:8080/ready

# Test metrics
curl http://localhost:8080/metrics | grep nats_messages
```

### 4.2 Test Message Processing

```bash
# Publish test message to NATS
kubectl exec -n nats nats-0 -- nats pub agent.execute.test-job-123 '{
  "job_id": "test-job-123",
  "agent_definition": {
    "name": "test-agent",
    "model": "gpt-4",
    "tools": []
  }
}'

# Watch agent-executor logs
kubectl logs -n intelligence-deepagents <pod-name> -c agent-executor -f

# Subscribe to result
kubectl exec -n nats nats-0 -- nats sub agent.status.completed
```

### 4.3 Test KEDA Autoscaling

```bash
# Publish multiple messages
for i in {1..10}; do
  kubectl exec -n nats nats-0 -- nats pub agent.execute.test-job-$i '{"job_id":"test-job-'$i'"}'
done

# Watch pod count (should scale up)
watch kubectl get pods -n intelligence-deepagents

# Wait for messages to be processed
# Watch pod count (should scale down after 5 minutes)
```

## Phase 5: Update Workflow

### 5.1 Update Service Image

```bash
cd bizmatters

# Edit deployment manifest
vim services/agent_executor/platform/claims/intelligence-deepagents/agent-executor-deployment.yaml

# Change image tag
# image: ghcr.io/arun4infra/agent-executor:v1.0.1

# Commit and push
git add services/agent_executor/platform/
git commit -m "chore: Update agent-executor to v1.0.1"
git push origin main

# Wait for ArgoCD sync (automatic, ~3 minutes)
# Or force sync:
argocd app sync bizmatters-workloads

# Verify new image
kubectl get deployment agent-executor -n intelligence-deepagents -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### 5.2 Scale Database Resources

```bash
cd bizmatters

# Edit claim
vim services/agent_executor/platform/claims/intelligence-deepagents/postgres-claim.yaml

# Change size: medium → large
# Or increase storageGB: 20 → 50

# Commit and push
git add services/agent_executor/platform/
git commit -m "feat: Scale postgres to large"
git push origin main

# Crossplane updates resources automatically
# Verify
kubectl get postgresinstance agent-executor-db -n intelligence-deepagents -o yaml
```

### 5.3 Rotate LLM API Keys

```bash
# Update AWS SSM parameter
aws ssm put-parameter \
  --name /zerotouch/prod/agent-executor/openai_api_key \
  --value "sk-new-key" \
  --type SecureString \
  --overwrite \
  --region ap-south-1

# ESO syncs automatically within 1 hour
# Or force sync by deleting secret:
kubectl delete secret agent-executor-llm-keys -n intelligence-deepagents

# ESO recreates immediately
kubectl get secret agent-executor-llm-keys -n intelligence-deepagents

# Restart pods to pick up new secret
kubectl rollout restart deployment agent-executor -n intelligence-deepagents
```

## Troubleshooting

### ApplicationSet Not Creating Application

```bash
# Check ApplicationSet status
kubectl get applicationset tenant-applications -n argocd -o yaml

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller

# Common issues:
# 1. Repository credentials not configured
# 2. Tenant config.yaml syntax error
# 3. Repository not accessible
```

### Crossplane Claims Not Provisioning

```bash
# Check claim status
kubectl get postgresinstance agent-executor-db -n intelligence-deepagents -o yaml

# Check Crossplane logs
kubectl logs -n crossplane-system -l app=crossplane

# Check provider-kubernetes logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-kubernetes

# Common issues:
# 1. XRD/Composition not applied
# 2. Provider-kubernetes not configured
# 3. RBAC permissions missing
```

### ExternalSecrets Not Syncing

```bash
# Check ExternalSecret status
kubectl get externalsecret -n intelligence-deepagents -o yaml

# Check ESO logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets

# Common issues:
# 1. AWS SSM parameters don't exist
# 2. ESO IAM role lacks permissions
# 3. ClusterSecretStore not configured
```

### Pods Not Starting

```bash
# Check pod events
kubectl describe pod <pod-name> -n intelligence-deepagents

# Check init container logs
kubectl logs <pod-name> -n intelligence-deepagents -c run-migrations

# Common issues:
# 1. ImagePullBackOff: ghcr-pull-secret not configured
# 2. Migration failure: Database not accessible
# 3. Secret not found: Crossplane/ESO not synced
```

## Rollback

### Rollback Deployment

```bash
# Via Git
cd bizmatters
git revert <commit-hash>
git push origin main

# Via kubectl (emergency)
kubectl rollout undo deployment agent-executor -n intelligence-deepagents
```

### Delete Tenant

```bash
# Remove tenant config
cd zerotouch-tenants
git rm -r tenants/bizmatters
git commit -m "Remove bizmatters tenant"
git push origin main

# ApplicationSet automatically deletes Application
# ArgoCD prunes all resources
```

## Security Checklist

- [ ] GitHub tokens have minimal scopes (read:packages, repo)
- [ ] AWS SSM parameters use SecureString type
- [ ] ESO IAM role follows least privilege
- [ ] Database credentials never in Git or SSM
- [ ] Secrets rotation policy defined
- [ ] Network policies configured (if required)
- [ ] Pod security standards enforced

## Next Steps

1. Set up monitoring and alerting
2. Configure backup policies for databases
3. Implement disaster recovery procedures
4. Add more tenants following the same pattern
5. Document runbooks for common operations

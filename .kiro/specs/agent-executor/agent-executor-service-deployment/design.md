# Design Document: Agent Executor Service Deployment

## 1. Overview

This design document describes the deployment architecture for the agent_executor service using GitOps with ApplicationSet + Tenant Registry pattern. This enables pluggable multi-tenant deployments where the public platform repo (zerotouch-platform) remains generic while private workloads (bizmatters) are deployed via ArgoCD's ApplicationSet.

**Note:** This spec should be moved to `bizmatters/.kiro/specs/agent-executor-deployment/` after creation.

### 1.1 Design Goals

1. **GitOps Native**: All deployments via ArgoCD, no manual kubectl commands
2. **Pluggable Multi-Tenant**: Public platform supports unlimited private repos via ApplicationSet
3. **Private Code**: Keep application logic and container images private
4. **Event-Driven**: Process NATS messages with KEDA autoscaling
5. **Stateful Execution**: PostgreSQL for checkpoints, Dragonfly for streaming
6. **Scalable**: Easy to add more private repos/tenants in the future

### 1.2 Architecture Principles

- **Consumer of Platform**: Use platform capabilities, don't redefine them
- **Separation of Concerns**: Application code separate from infrastructure
- **Declarative**: Manifests define desired state, ArgoCD handles provisioning
- **Secure**: Private registry, ESO-managed secrets
- **Open Source Friendly**: Public platform repo has no hardcoded private repo references

## 2. System Architecture

### 2.1 Repository Structure

**Three-Repo Pattern:**

```
zerotouch-platform/ (Public Repository - Generic Platform)
├── bootstrap/
│   └── components/
│       ├── 01-eso.yaml                    # External Secrets Operator
│       ├── 03-intelligence.yaml           # Intelligence layer
│       └── 99-tenants.yaml                # NEW: ApplicationSet for tenants
└── platform/
    ├── 01-foundation/                     # Platform foundation
    ├── 03-intelligence/                   # Intelligence workloads
    └── 05-databases/                      # Database compositions

zerotouch-tenants/ (Private Repository - Tenant Registry)
├── README.md                              # Tenant registry documentation
└── tenants/
    ├── example/
    │   └── config.yaml.example            # Template for new tenants
    └── bizmatters/
        └── config.yaml                    # Bizmatters tenant configuration

bizmatters/ (Private Repository - Application Code)
├── services/
│   └── agent_executor/
│       ├── api/
│       │   └── main.py                    # FastAPI app (HTTP + NATS consumer)
│       ├── services/
│       │   ├── nats_consumer.py           # NATS consumer
│       │   ├── cloudevents.py             # CloudEvent handling
│       │   └── redis.py                   # Dragonfly client
│       ├── scripts/
│       │   ├── ci/
│       │   │   ├── build.sh               # Docker image build
│       │   │   ├── run.sh                 # Service entrypoint
│       │   │   ├── run-tests.sh           # Integration tests
│       │   │   └── run-migrations.sh      # Database migrations
│       │   └── local/
│       │       └── run.sh                 # Local development
│       ├── tests/integration/
│       │   ├── docker-compose.test.yml    # Test infrastructure
│       │   └── test_api.py                # Integration tests
│       └── platform/                      # Co-located deployment manifests
│           ├── namespace.yaml
│           ├── image-pull-secret.yaml
│           ├── nats-stream.yaml
│           ├── agent-executor-deployment.yaml
│           └── external-secrets/
│               ├── postgres-es.yaml
│               ├── dragonfly-es.yaml
│               └── llm-keys-es.yaml
└── .github/workflows/
    └── agent-executor-integration-tests.yml  # CI/CD pipeline

Note: No ArgoCD Application manifest needed - ApplicationSet generates it automatically.
```

### 2.2 Data Flow

#### 2.2.1 Initial Setup Flow (One-Time)
```
1. Create zerotouch-tenants repo (private)
    ↓
2. Add ApplicationSet to zerotouch-platform (public)
    ↓
3. Bootstrap ArgoCD with tenant registry credentials
    ↓
4. Add tenant config to zerotouch-tenants/tenants/bizmatters/config.yaml
    ↓
5. ApplicationSet discovers tenant config
    ↓
6. ApplicationSet creates Application: bizmatters-workloads
    ↓
7. ArgoCD syncs manifests from bizmatters repo
    ↓
8. Kubernetes resources created (namespace, secrets, deployment)
```

#### 2.2.2 GitOps Deployment Flow (Ongoing)
```
Developer Updates Code
    ↓
CI Builds Image → ghcr.io/arun4infra/agent-executor:v1.2.0
    ↓
Developer Updates deployment.yaml (image: v1.2.0)
    ↓
Git Commit & Push to bizmatters repo
    ↓
ArgoCD Detects Change (polls bizmatters repo every 3 min)
    ↓
ArgoCD Syncs Updated Manifests
    ↓
Kubernetes Rolling Update (pulls new image with ImagePullSecret)
    ↓
New Pods Running
```

#### 2.2.2 Message Processing Flow
```
External System → NATS (agent.execute.job123)
    ↓
NATS JetStream (AGENT_EXECUTION stream)
    ↓
KEDA Monitors Queue Depth
    ↓ (if depth > 5)
KEDA Scales Up Pods
    ↓
NATS Consumer (in agent_executor)
    ↓
Parse CloudEvent → JobExecutionEvent
    ↓
Execute LangGraph Agent
    ├─→ PostgreSQL (checkpoints)
    └─→ Dragonfly (streaming events)
    ↓
Publish Result CloudEvent → NATS (agent.status.completed)
    ↓
Acknowledge Message (remove from queue)
```

### 2.3 Critical Implementation Notes ("Day 1" Gotchas)

#### 2.3.1 Credential Ordering (Chicken-and-Egg Problem)
**Problem**: ApplicationSet will fail to sync if tenant registry credentials don't exist.

**Solution**: Credentials MUST be added in this exact order:
1. Add `zerotouch-tenants` repo credentials to ArgoCD
2. Add `bizmatters` repo credentials to ArgoCD
3. Create ApplicationSet in `zerotouch-platform`
4. Commit tenant config to `zerotouch-tenants`

**Bootstrap Script**: The `03-install-argocd.sh` script should be updated to handle this ordering.

#### 2.3.2 Docker Image Must Include Migrations
**Problem**: Init container runs `run-migrations.sh` which expects `.sql` files in `/app/migrations/`.

**Solution**: Dockerfile MUST include:
```dockerfile
COPY migrations/ /app/migrations/
```

**Verification**: Check Dockerfile in `services/agent_executor/Dockerfile` includes migrations directory.

#### 2.3.3 NATS Stream Race Condition
**Problem**: Deployment may start before NATS stream exists, causing crash-loops.

**Solution**: Use ArgoCD sync-waves:
- NATS Stream Job: `argocd.argoproj.io/sync-wave: "1"`
- Deployment: `argocd.argoproj.io/sync-wave: "2"`

**Implementation**: Already added to manifests in tasks 3.8 and 3.9.

### 2.4 Secrets Management via AWS SSM Parameter Store

#### 2.4.1 Generic SSM Injection Mechanism

The platform provides a generic script (`scripts/bootstrap/06-inject-ssm-parameters.sh`) that reads secrets from a `.env.ssm` file and creates them in AWS Systems Manager Parameter Store.

**File Structure:**
```
zerotouch-platform/
├── .env.ssm.example          # Template (committed to git)
├── .env.ssm                  # Actual secrets (gitignored)
└── scripts/bootstrap/
    └── 06-inject-ssm-parameters.sh  # Generic injection script
```

**Workflow:**
```
1. Copy template: cp .env.ssm.example .env.ssm
    ↓
2. Edit .env.ssm with actual secret values
    ↓
3. Run: ./scripts/bootstrap/06-inject-ssm-parameters.sh
    ↓
4. Script creates parameters in AWS SSM (SecureString type)
    ↓
5. ESO automatically syncs parameters to Kubernetes Secrets
    ↓
6. Application pods mount secrets as environment variables
```

**Benefits:**
- **Generic**: Works for any service, not specific to agent-executor
- **Single Source of Truth**: All secrets in one file
- **Secure**: `.env.ssm` is gitignored, parameters encrypted at rest
- **Automated**: One command to inject all secrets
- **Idempotent**: Can be run multiple times (updates existing parameters)

**Example `.env.ssm` format:**
```bash
/zerotouch/prod/service-name/key=value
/zerotouch/prod/agent-executor/postgres/password=secure_password
/zerotouch/prod/agent-executor/openai_api_key=sk-...
```

#### 2.4.2 ESO Integration

External Secrets Operator (ESO) is configured with AWS credentials via `05-inject-secrets.sh` (one-time bootstrap). Once configured, ESO automatically:
1. Reads parameters from AWS SSM Parameter Store
2. Creates Kubernetes Secrets in target namespaces
3. Refreshes secrets periodically (default: 1h)

**ExternalSecret Example:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: agent-executor-postgres
  namespace: intelligence-deepagents
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-parameter-store
    kind: ClusterSecretStore
  target:
    name: agent-executor-postgres
    creationPolicy: Owner
  data:
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: /zerotouch/prod/agent-executor/postgres/password
```

### 2.5 Database Per Service Pattern (Crossplane-Based)

#### 2.5.1 Pattern Overview

The platform follows the "Database per Service" microservices pattern with **Zero-Touch provisioning**:
- Each service owns its own database instance or schema
- Databases are provisioned using Crossplane compositions
- Platform provides generic XRDs (Composite Resource Definitions)
- Services create claims to provision dedicated databases
- **Credentials are auto-generated** and written to secrets via `writeConnectionSecretToRef`

**Benefits:**
- **Isolation**: Service failures don't affect other services
- **Independent Scaling**: Each database can be sized appropriately
- **Schema Evolution**: Services can migrate schemas independently
- **Technology Choice**: Different services can use different database engines
- **Zero-Touch Security**: No manual credential management, no credentials in Git or SSM
- **GitOps Native**: Commit claim YAML, platform provisions infrastructure automatically

#### 2.5.2 Crossplane-Based Provisioning with Connection Secrets

The platform provides Crossplane compositions for common databases:
- `XPostgresInstance`: PostgreSQL database instances
- `XDragonflyInstance`: Dragonfly (Redis-compatible) cache instances

**Provisioning Flow:**
```
1. Service creates claim YAML with writeConnectionSecretToRef
    ↓
2. Commit claim to bizmatters repo
    ↓
3. ArgoCD syncs claim to cluster
    ↓
4. Crossplane provisions database resources:
   - StatefulSet (database pod)
   - Service (ClusterIP)
   - PersistentVolumeClaim (storage)
   - Connection Secret (auto-generated credentials)
    ↓
5. Database becomes available at: {instance-name}.databases.svc
6. Connection secret created in claim's namespace with keys:
   - PostgreSQL: endpoint, port, username, password, database
   - Dragonfly: endpoint, port, password
```

**Key Advantage**: The claim specifies `writeConnectionSecretToRef`, and Crossplane automatically:
1. Generates secure random passwords
2. Creates the connection secret in the service's namespace
3. Populates it with all connection details
4. No credentials ever touch Git, SSM, or human hands

#### 2.5.3 Agent Executor Database Claims

Agent executor requires two database instances:

**PostgreSQL (for LangGraph checkpoints):**
- Instance name: `agent-executor-db`
- Service DNS: `agent-executor-db.databases.svc:5432`
- Database: `langgraph_prod`
- User: `agent_executor`

**Dragonfly (for streaming events):**
- Instance name: `agent-executor-cache`
- Service DNS: `agent-executor-cache.databases.svc:6379`
- Purpose: Real-time event streaming via pub/sub

**Claim Location:**
```
bizmatters/services/agent_executor/platform/
├── postgres-claim.yaml      # XPostgresInstance claim
└── dragonfly-claim.yaml     # XDragonflyInstance claim
```

**Connection Configuration:**
Credentials are automatically generated by Crossplane and written to secrets via `writeConnectionSecretToRef`:

**PostgreSQL Secret** (`agent-executor-postgres`):
- `endpoint`: agent-executor-db.databases.svc.cluster.local
- `port`: 5432
- `database`: postgres
- `username`: postgres
- `password`: <auto-generated>

**Dragonfly Secret** (`agent-executor-dragonfly`):
- `endpoint`: agent-executor-cache.databases.svc.cluster.local
- `port`: 6379
- `password`: <auto-generated>

**Note**: Database credentials are NOT stored in AWS SSM. They are managed entirely by Crossplane.

## 3. Component Design

### 3.1 Application Code Changes

#### 3.1.1 Remove Vault Integration

**Delete:**
- `services/vault.py`

**Update `api/main.py`:**
```python
# BEFORE (with Vault)
from services.vault import VaultClient

vault_client = VaultClient(vault_url=os.getenv("VAULT_ADDR"))
postgres_password = vault_client.get_secret("database/postgres/password")

# AFTER (with environment variables)
postgres_password = os.getenv("POSTGRES_PASSWORD")
```

#### 3.1.2 Add NATS Consumer

**Create `services/nats_consumer.py`:**
```python
import asyncio
import json
import nats
from nats.js import JetStreamContext

class NATSConsumer:
    def __init__(self, nats_url: str, stream_name: str, consumer_group: str):
        self.nats_url = nats_url
        self.stream_name = stream_name
        self.consumer_group = consumer_group
        self.nc = None
        self.js = None
        self.running = False
    
    async def start(self):
        """Start consuming messages from NATS"""
        self.nc = await nats.connect(self.nats_url)
        self.js = self.nc.jetstream()
        
        # Create pull subscription
        psub = await self.js.pull_subscribe(
            subject="agent.execute.*",
            durable=self.consumer_group,
            stream=self.stream_name
        )
        
        self.running = True
        while self.running:
            try:
                msgs = await psub.fetch(batch=1, timeout=5)
                for msg in msgs:
                    await self.process_message(msg)
                    await msg.ack()
            except asyncio.TimeoutError:
                continue
            except Exception as e:
                logger.error(f"Error processing message: {e}")
    
    async def process_message(self, msg):
        """Process a single NATS message"""
        # Parse CloudEvent
        event_data = json.loads(msg.data)
        job_event = JobExecutionEvent(**event_data)
        
        # Execute agent (same logic as HTTP endpoint)
        result = await execute_agent(job_event)
        
        # Publish result CloudEvent to NATS
        await self.publish_result(result)
    
    async def publish_result(self, result):
        """Publish result CloudEvent to NATS"""
        subject = f"agent.status.{result.status}"
        await self.js.publish(subject, json.dumps(result).encode())
    
    async def stop(self):
        """Stop consuming messages"""
        self.running = False
        if self.nc:
            await self.nc.close()
```

**Update `api/main.py` lifespan:**
```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    logger.info("agent_executor_service_starting")
    
    # Read secrets from environment variables
    postgres_host = os.getenv("POSTGRES_HOST")
    postgres_password = os.getenv("POSTGRES_PASSWORD")
    dragonfly_host = os.getenv("DRAGONFLY_HOST")
    openai_api_key = os.getenv("OPENAI_API_KEY")
    
    # Initialize services
    redis_client = RedisClient(host=dragonfly_host, ...)
    execution_manager = ExecutionManager(redis_client, postgres_conn_str)
    
    # Start NATS consumer as background task
    nats_consumer = NATSConsumer(
        nats_url=os.getenv("NATS_URL"),
        stream_name="AGENT_EXECUTION",
        consumer_group="agent-executor-workers"
    )
    consumer_task = asyncio.create_task(nats_consumer.start())
    
    yield
    
    # Shutdown
    await nats_consumer.stop()
    await consumer_task
    redis_client.close()
```

#### 3.1.3 Update Migration Script

**Update `scripts/ci/run-migrations.sh`:**
```bash
#!/bin/bash
set -e

# Read from environment variables (no kubectl)
POSTGRES_HOST="${POSTGRES_HOST}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB}"
POSTGRES_USER="${POSTGRES_USER}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"

# Run migrations using psql directly
for migration in /app/migrations/*.up.sql; do
  echo "Applying migration: $(basename "$migration")"
  
  PGPASSWORD="$POSTGRES_PASSWORD" psql \
    -h "$POSTGRES_HOST" \
    -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    -v ON_ERROR_STOP=1 \
    -f "$migration"
done

echo "Migrations completed successfully"
```

### 3.2 Integration Tests

**Update `tests/integration/docker-compose.test.yml`:**
```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: test_user
      POSTGRES_PASSWORD: test_pass
      POSTGRES_DB: test_db
    ports:
      - "15433:5432"

  dragonfly:  # CHANGED: Replace redis with dragonfly
    image: docker.dragonflydb.io/dragonflydb/dragonfly:latest
    ports:
      - "16380:6379"

  nats:  # NEW: Add NATS for testing
    image: nats:latest
    command: ["-js"]  # Enable JetStream
    ports:
      - "14222:4222"
```

### 3.3 Deployment Configuration

#### 3.3.1 Namespace

**File: `platform/claims/intelligence-deepagents/namespace.yaml`**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: intelligence-deepagents
  labels:
    layer: intelligence
    category: deepagents
    name: intelligence-deepagents
```

#### 3.3.2 ImagePullSecret (via ESO)

**File: `platform/claims/intelligence-deepagents/external-secrets/image-pull-secret-es.yaml`**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ghcr-pull-secret
  namespace: intelligence-deepagents
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-parameter-store
    kind: ClusterSecretStore
  target:
    name: ghcr-pull-secret
    creationPolicy: Owner
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {
            "auths": {
              "ghcr.io": {
                "username": "{{ .username }}",
                "password": "{{ .password }}",
                "auth": "{{ printf "%s:%s" .username .password | b64enc }}"
              }
            }
          }
  data:
    - secretKey: username
      remoteRef:
        key: /zerotouch/prod/platform/ghcr/username
    - secretKey: password
      remoteRef:
        key: /zerotouch/prod/platform/ghcr/password
```

#### 3.3.3 Crossplane Database Claims

**File: `platform/claims/intelligence-deepagents/postgres-claim.yaml`**
```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: PostgresInstance
metadata:
  name: agent-executor-db
  namespace: intelligence-deepagents
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  size: medium
  version: "16"
  storageGB: 20
  writeConnectionSecretToRef:
    name: agent-executor-postgres
    namespace: intelligence-deepagents
```

**File: `platform/claims/intelligence-deepagents/dragonfly-claim.yaml`**
```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: DragonflyInstance
metadata:
  name: agent-executor-cache
  namespace: intelligence-deepagents
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  size: medium
  storageGB: 10
  writeConnectionSecretToRef:
    name: agent-executor-dragonfly
    namespace: intelligence-deepagents
```

#### 3.3.4 ExternalSecrets (LLM Keys Only)

**File: `platform/claims/intelligence-deepagents/external-secrets/llm-keys-es.yaml`**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: agent-executor-llm-keys
  namespace: intelligence-deepagents
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-parameter-store
    kind: ClusterSecretStore
  target:
    name: agent-executor-llm-keys
    creationPolicy: Owner
  data:
    - secretKey: OPENAI_API_KEY
      remoteRef:
        key: /zerotouch/prod/agent-executor/openai_api_key
    - secretKey: ANTHROPIC_API_KEY
      remoteRef:
        key: /zerotouch/prod/agent-executor/anthropic_api_key
```

#### 3.3.5 NATS Stream

**File: `platform/claims/intelligence-deepagents/nats-stream.yaml`**
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: create-agent-execution-stream
  namespace: intelligence-deepagents
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: nats-cli
        image: natsio/nats-box:latest
        command:
        - /bin/sh
        - -c
        - |
          # Create stream
          nats stream add AGENT_EXECUTION \
            --server=nats://nats.nats.svc:4222 \
            --subjects "agent.execute.*" \
            --retention limits \
            --max-msgs=-1 \
            --max-age=24h \
            --storage file \
            --replicas 1 \
            --discard old || true
          
          # Create consumer
          nats consumer add AGENT_EXECUTION agent-executor-workers \
            --server=nats://nats.nats.svc:4222 \
            --pull \
            --deliver all \
            --max-deliver=-1 \
            --ack explicit \
            --replay instant || true
```

#### 3.3.6 AgentExecutor Deployment

**File: `platform/claims/intelligence-deepagents/agent-executor-claim.yaml`**
```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentExecutor
metadata:
  name: agent-executor
  namespace: intelligence-deepagents
spec:
  image: ghcr.io/arun4infra/agent-executor:v1.0.0
  size: medium
  natsUrl: nats://nats.nats.svc:4222
  natsStreamName: AGENT_EXECUTION
  natsConsumerGroup: agent-executor-workers
  postgresConnectionSecret: agent-executor-postgres
  dragonflyConnectionSecret: agent-executor-dragonfly
  llmKeysSecret: agent-executor-llm-keys
  imagePullSecrets:
    - ghcr-pull-secret
```

**Note:** No ArgoCD Application manifest needed in bizmatters repo. The ApplicationSet in zerotouch-platform automatically generates the Application CRD from the tenant config in zerotouch-tenants.

## 4. Deployment Workflow

### 4.1 Initial Setup (One-Time)

**Step 1: Configure AWS SSM Parameter Store**
```bash
# GitHub registry credentials (platform-wide)
aws ssm put-parameter --name /zerotouch/prod/platform/ghcr/username --value "<github-username>" --type String
aws ssm put-parameter --name /zerotouch/prod/platform/ghcr/password --value "<github-token>" --type SecureString

# LLM API keys
aws ssm put-parameter --name /zerotouch/prod/agent-executor/openai_api_key --value "sk-..." --type SecureString
aws ssm put-parameter --name /zerotouch/prod/agent-executor/anthropic_api_key --value "sk-ant-..." --type SecureString
```

**Note**: Database credentials are NOT stored in AWS SSM. They are automatically generated by Crossplane.

**Step 2: Configure ArgoCD Repository Credentials**
```bash
# Add tenant registry repo credentials
./scripts/bootstrap/06-add-private-repo.sh \
  https://github.com/arun4infra/zerotouch-tenants.git \
  <github-username> \
  <github-token>

# Add bizmatters repo credentials
./scripts/bootstrap/06-add-private-repo.sh \
  https://github.com/arun4infra/bizmatters.git \
  <github-username> \
  <github-token>
```

**Step 3: Create Tenant Config**
```bash
# In zerotouch-tenants repo
cat > tenants/bizmatters/config.yaml <<EOF
tenant: bizmatters-workloads
repoURL: https://github.com/arun4infra/bizmatters.git
targetRevision: main
path: services/agent_executor/platform
EOF

git add tenants/bizmatters/config.yaml
git commit -m "Add bizmatters tenant"
git push
```

**Step 4: ApplicationSet Auto-Discovers and Deploys**
- ApplicationSet in zerotouch-platform detects new tenant config
- Automatically creates Application: bizmatters-workloads
- ArgoCD syncs manifests from bizmatters repo
- Kubernetes resources deployed

### 4.2 Updating Agent Executor

**Step 1: Update manifests in bizmatters repo**
```bash
cd bizmatters
git add services/agent_executor/platform/
git commit -m "feat: Deploy agent-executor service"
git push
```

**Step 2: ArgoCD syncs automatically**
- ArgoCD detects changes in private repo
- Syncs namespace, secrets, NATS stream, claim
- Crossplane provisions resources
- Kubernetes starts pods

### 4.3 Updating Image Version

**Step 1: Build new image**
```bash
cd bizmatters/services/agent_executor
./scripts/ci/build.sh  # Builds and pushes to ghcr.io
```

**Step 2: Update claim**
```bash
# Edit platform/claims/intelligence-deepagents/agent-executor-claim.yaml
# Change: image: ghcr.io/arun4infra/agent-executor:v1.1.0

git add platform/claims/intelligence-deepagents/agent-executor-claim.yaml
git commit -m "chore: Update agent-executor to v1.1.0"
git push
```

**Step 3: ArgoCD syncs, Crossplane updates, Kubernetes rolls out**

## 5. Testing Strategy

### 5.1 Integration Tests (Local)
- Run docker-compose with Dragonfly and NATS
- Test HTTP endpoint with CloudEvents
- Test NATS consumer with test messages
- Verify PostgreSQL checkpoints
- Verify Dragonfly streaming

### 5.2 Deployment Verification (Cluster)
- Verify namespace created
- Verify ExternalSecrets synced (check K8s secrets exist)
- Verify NATS stream created
- Verify claim created
- Verify Deployment, Service, ScaledObject created
- Verify pods running
- Test message processing end-to-end

## 6. References

- **Platform API Documentation**: `zerotouch-platform/platform/04-apis/README.md`
- **NATS Stream Configuration**: `zerotouch-platform/docs/standards/nats-stream-configuration.md`
- **Namespace Naming Convention**: `zerotouch-platform/docs/standards/namespace-naming-convention.md`

# EventDrivenService Platform API

A simplified Crossplane-based API for deploying NATS JetStream consumer services with KEDA autoscaling.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [API Reference](#api-reference)
- [Hybrid Secret Sources](#hybrid-secret-sources)
- [Resources Created](#resources-created)
- [Health Probes](#health-probes)
- [KEDA Autoscaling](#keda-autoscaling)
- [Migration Guide](#migration-guide)
- [Troubleshooting](#troubleshooting)
- [IDE Integration](#ide-integration)
- [Examples](#examples)

## Overview

The EventDrivenService API reduces deployment complexity from 212 lines of explicit Kubernetes manifests to approximately 30 lines of declarative YAML while maintaining full Zero-Touch compliance.

**Key Features:**
- ✅ No custom functions - uses standard Crossplane patches only
- ✅ Zero memory overhead - no additional pods required
- ✅ Hybrid Secret Sources - supports Crossplane, ESO, and manual secrets
- ✅ Simple API - pre-defined secret slots (up to 5 secrets)
- ✅ KEDA autoscaling - based on NATS queue depth
- ✅ Optional init containers - for database migrations
- ✅ Security hardened - Pod Security Standards compliant
- ✅ Schema validation - IDE autocomplete and CI validation

**Architecture:**
- **Crossplane XRD** - Defines the API schema
- **Crossplane Composition** - Provisions Kubernetes resources
- **Standard patches only** - No custom functions required
- **Zero-Touch principles** - Accepts Crossplane/ESO-generated secrets as-is

## Quick Start

### Prerequisites

Before deploying an EventDrivenService, ensure the following exist:

1. **NATS with JetStream** - Deployed in `nats` namespace
2. **KEDA** - Installed and operational
3. **Crossplane** - With kubernetes provider configured
4. **Secrets** - Created via Crossplane, ESO, or manually
5. **NATS Stream** - JetStream stream must exist before deployment

### Minimal Example

The simplest possible deployment with just image and NATS configuration:

```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: EventDrivenService
metadata:
  name: simple-worker
  namespace: workers
spec:
  image: ghcr.io/org/simple-worker:v1.0.0
  size: small
  nats:
    stream: SIMPLE_JOBS
    consumer: simple-workers
```

**Resources Created:**
- Deployment (1 replica, KEDA-managed)
- Service (ClusterIP:8080)
- ScaledObject (1-10 replicas based on NATS queue depth)
- ServiceAccount

### Full Example

Complete deployment with secrets, init container, and private registry:

```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: EventDrivenService
metadata:
  name: agent-executor
  namespace: intelligence-deepagents
spec:
  image: ghcr.io/arun4infra/agent-executor:latest
  size: medium
  
  nats:
    stream: AGENT_EXECUTION
    consumer: agent-executor-workers
  
  # Secrets (envFrom - bulk mounting)
  secret1Name: agent-executor-db-conn      # Crossplane-generated
  secret2Name: agent-executor-cache-conn   # Crossplane-generated
  secret3Name: agent-executor-llm-keys     # ESO-synced
  
  imagePullSecrets:
    - name: ghcr-pull-secret
  
  initContainer:
    command: ["/bin/bash", "-c"]
    args: ["cd /app && ./scripts/ci/run-migrations.sh"]
```

See [examples/](examples/) directory for more examples.

## API Reference

### Complete Spec Schema

```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: EventDrivenService
metadata:
  name: <service-name>
  namespace: <namespace>
spec:
  # Required: Container image
  image: string
    # Example: ghcr.io/org/my-service:v1.0.0
    # Supports: registry/repository:tag or registry/repository@sha256:digest
  
  # Optional: Resource size (default: medium)
  size: enum [small, medium, large]
  
  # Required: NATS configuration
  nats:
    url: string (default: "nats://nats.nats.svc:4222")
    stream: string (required)
    consumer: string (required)
  
  # Optional: Secret references (up to 5 secrets)
  secret1Name: string
  secret2Name: string
  secret3Name: string
  secret4Name: string
  secret5Name: string
  
  # Optional: Image pull secrets
  imagePullSecrets:
    - name: string
  
  # Optional: Init container
  initContainer:
    command: array[string]
    args: array[string]
```

### Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `image` | string | **Yes** | Container image reference (registry/repository:tag) |
| `size` | enum | No | Resource size: `small`, `medium`, `large` (default: `medium`) |
| `nats.url` | string | No | NATS server URL (default: `nats://nats.nats.svc:4222`) |
| `nats.stream` | string | **Yes** | JetStream stream name (must exist before deployment) |
| `nats.consumer` | string | **Yes** | Consumer group name for this service |
| `secret1Name` | string | No | First secret name (envFrom bulk mounting) |
| `secret2Name` | string | No | Second secret name (envFrom bulk mounting) |
| `secret3Name` | string | No | Third secret name (envFrom bulk mounting) |
| `secret4Name` | string | No | Fourth secret name (envFrom bulk mounting) |
| `secret5Name` | string | No | Fifth secret name (envFrom bulk mounting) |
| `imagePullSecrets` | array | No | Array of image pull secret names for private registries |
| `initContainer.command` | array | No | Init container command (uses same image as main container) |
| `initContainer.args` | array | No | Init container arguments |

### Resource Sizing

The `size` field maps to predefined CPU and memory allocations based on production tuning:

| Size | CPU Request | CPU Limit | Memory Request | Memory Limit | Use Case |
|------|-------------|-----------|----------------|--------------|----------|
| `small` | 250m | 1000m | 512Mi | 2Gi | Lightweight workers, simple tasks |
| `medium` | 500m | 2000m | 1Gi | 4Gi | Standard workloads, typical services |
| `large` | 1000m | 4000m | 2Gi | 8Gi | Heavy processing, LLM inference |

**Notes:**
- Both requests and limits are set for predictable pod scheduling
- Allocations are based on proven agent-executor production tuning
- Default is `medium` if not specified

## Hybrid Secret Sources

The EventDrivenService API supports secrets from multiple sources without requiring consolidation. This respects Zero-Touch principles by accepting Crossplane-generated and ESO-synced secrets as-is.

### Crossplane-Generated Secrets

Crossplane automatically creates secrets when you provision database or cache instances:

```yaml
# PostgresInstance creates secret automatically
apiVersion: database.bizmatters.io/v1alpha1
kind: PostgresInstance
metadata:
  name: my-service-db
  namespace: my-namespace
spec:
  writeConnectionSecretToRef:
    name: my-service-db-conn  # ← Reference this in EventDrivenService
    namespace: my-namespace
```

```yaml
# DragonflyInstance creates secret automatically
apiVersion: cache.bizmatters.io/v1alpha1
kind: DragonflyInstance
metadata:
  name: my-service-cache
  namespace: my-namespace
spec:
  writeConnectionSecretToRef:
    name: my-service-cache-conn  # ← Reference this in EventDrivenService
    namespace: my-namespace
```

**Reference in EventDrivenService:**
```yaml
spec:
  secret1Name: my-service-db-conn
  secret2Name: my-service-cache-conn
```

### ESO-Synced Secrets

External Secrets Operator syncs secrets from AWS SSM Parameter Store:

```yaml
# ExternalSecret syncs from AWS SSM
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-service-llm-keys
  namespace: my-namespace
spec:
  secretStoreRef:
    name: aws-parameter-store
  target:
    name: my-service-llm-keys  # ← Reference this in EventDrivenService
  data:
    - secretKey: OPENAI_API_KEY
      remoteRef:
        key: /app/openai_api_key
    - secretKey: ANTHROPIC_API_KEY
      remoteRef:
        key: /app/anthropic_api_key
```

**Reference in EventDrivenService:**
```yaml
spec:
  secret3Name: my-service-llm-keys
```

### Secret Mounting (envFrom)

All secrets are mounted using `envFrom` (bulk mounting). This approach:
- ✅ Mounts all keys in the secret as environment variables
- ✅ Requires key names to match desired environment variable names
- ✅ Simple and predictable behavior
- ✅ No custom Crossplane functions needed

**Example:** If `my-service-db-conn` contains:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-service-db-conn
data:
  POSTGRES_HOST: cG9zdGdyZXMuc3Zj
  POSTGRES_PORT: NTQzMg==
  POSTGRES_DB: bXlkYg==
  POSTGRES_USER: dXNlcg==
  POSTGRES_PASSWORD: cGFzc3dvcmQ=
```

Then the container will have these environment variables:
- `POSTGRES_HOST=postgres.svc`
- `POSTGRES_PORT=5432`
- `POSTGRES_DB=mydb`
- `POSTGRES_USER=user`
- `POSTGRES_PASSWORD=password`

**Important:** Secret keys must be named as valid environment variable names (uppercase, underscores allowed).

### Multiple Secrets Example

You can reference up to 5 secrets from different sources:

```yaml
spec:
  secret1Name: my-service-db-conn      # Crossplane PostgresInstance
  secret2Name: my-service-cache-conn   # Crossplane DragonflyInstance
  secret3Name: my-service-llm-keys     # ESO from AWS SSM
  secret4Name: my-service-app-config   # ESO from AWS SSM
  secret5Name: my-service-webhooks     # Manual Kubernetes secret
```

All environment variables from all 5 secrets will be available in the container.

## Resources Created

The Composition automatically creates 4 Kubernetes resources:

### 1. ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: <claim-name>
  namespace: <claim-namespace>
  labels:
    app.kubernetes.io/name: <claim-name>
    app.kubernetes.io/component: event-driven-worker
    app.kubernetes.io/managed-by: crossplane
automountServiceAccountToken: false
```

**Purpose:** Pod identity for Kubernetes RBAC (no special permissions by default)

### 2. Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <claim-name>
  namespace: <claim-namespace>
spec:
  replicas: 1  # KEDA controls scaling
  template:
    spec:
      serviceAccountName: <claim-name>
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      
      # Optional init container (if specified)
      initContainers:
        - name: init
          image: <spec.image>
          command: <spec.initContainer.command>
          args: <spec.initContainer.args>
          envFrom: [all secrets]
      
      containers:
        - name: main
          image: <spec.image>
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: NATS_URL
              value: <spec.nats.url>
            - name: NATS_STREAM_NAME
              value: <spec.nats.stream>
            - name: NATS_CONSUMER_GROUP
              value: <spec.nats.consumer>
          envFrom:
            - secretRef:
                name: <spec.secret1Name>
            # ... up to secret5Name
          resources:
            requests:
              cpu: <based on size>
              memory: <based on size>
            limits:
              cpu: <based on size>
              memory: <based on size>
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
            seccompProfile:
              type: RuntimeDefault
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 2
```

**Security Features:**
- Pod Security Standards compliant (Restricted policy)
- Non-root user (UID 1000)
- No privilege escalation
- All capabilities dropped
- Seccomp profile enabled

### 3. Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <claim-name>
  namespace: <claim-namespace>
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: <claim-name>
  ports:
    - name: http
      port: 8080
      targetPort: http
      protocol: TCP
```

**Purpose:** Internal cluster networking on port 8080

### 4. ScaledObject (KEDA)

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: <claim-name>-scaler
  namespace: <claim-namespace>
spec:
  scaleTargetRef:
    name: <claim-name>
  minReplicaCount: 1
  maxReplicaCount: 10
  triggers:
    - type: nats-jetstream
      metadata:
        natsServerMonitoringEndpoint: "nats-headless.nats.svc.cluster.local:8222"
        account: "$SYS"
        stream: <spec.nats.stream>
        consumer: <spec.nats.consumer>
        lagThreshold: "5"
```

**Purpose:** Automatic scaling based on NATS queue depth

## Health Probes

Your service **must** implement these HTTP endpoints:

### Liveness Probe

- **Endpoint:** `GET /health`
- **Port:** 8080
- **Purpose:** Kubernetes restarts the pod if this fails 3 consecutive times
- **Timing:** 
  - Initial delay: 10 seconds
  - Period: 10 seconds
  - Timeout: 5 seconds
  - Failure threshold: 3

**Example Response:**
```json
{
  "status": "healthy",
  "timestamp": "2025-12-08T10:30:00Z"
}
```

### Readiness Probe

- **Endpoint:** `GET /ready`
- **Port:** 8080
- **Purpose:** Kubernetes removes pod from Service endpoints if this fails
- **Timing:**
  - Initial delay: 5 seconds
  - Period: 5 seconds
  - Timeout: 3 seconds
  - Failure threshold: 2

**Example Response:**
```json
{
  "status": "ready",
  "checks": {
    "database": "ok",
    "nats": "ok",
    "cache": "ok"
  }
}
```

**Best Practice:** The readiness probe should verify connectivity to dependencies (database, NATS, cache).

## KEDA Autoscaling

The EventDrivenService automatically configures KEDA autoscaling based on NATS queue depth.

### Scaling Behavior

- **Min replicas:** 1 (always at least one pod running)
- **Max replicas:** 10 (scales up to 10 pods under load)
- **Lag threshold:** 5 messages (scales up when queue depth > 5)
- **Monitoring endpoint:** `nats-headless.nats.svc.cluster.local:8222`

### How It Works

1. KEDA monitors the NATS JetStream consumer lag
2. When lag > 5 messages, KEDA scales up the Deployment
3. When lag drops below threshold, KEDA scales down
4. Scaling is gradual and respects Kubernetes HPA behavior

### Monitoring Endpoint

**Critical:** The composition uses `nats-headless.nats.svc.cluster.local:8222` (not `nats`). This is because:
- The `nats` service does NOT expose port 8222
- The `nats-headless` service DOES expose port 8222
- This fix was proven in agent-executor debugging

### Verifying Autoscaling

```bash
# Check ScaledObject status
kubectl get scaledobject <service-name>-scaler -n <namespace>

# Watch pods scale up/down
watch kubectl get pods -n <namespace> -l app.kubernetes.io/name=<service-name>

# Check KEDA metrics
kubectl get hpa -n <namespace>
```

## Migration Guide

This guide helps you migrate from direct Kubernetes manifests to the EventDrivenService API.

### Prerequisites

Before migrating, ensure you have:

1. ✅ **Existing secrets** - Database, cache, and application secrets already created
2. ✅ **Database claims** - PostgresInstance or DragonflyInstance claims deployed
3. ✅ **NATS stream** - JetStream stream already exists
4. ✅ **Image pull secrets** - If using private registries
5. ✅ **Backup** - Git commit of current working manifests

### Step-by-Step Migration

#### Step 1: Identify Current Resources

List all resources for your service:

```bash
# Find Deployment
kubectl get deployment <service-name> -n <namespace> -o yaml > backup-deployment.yaml

# Find Service
kubectl get service <service-name> -n <namespace> -o yaml > backup-service.yaml

# Find ScaledObject
kubectl get scaledobject <service-name>-scaler -n <namespace> -o yaml > backup-scaledobject.yaml

# Find ServiceAccount
kubectl get serviceaccount <service-name> -n <namespace> -o yaml > backup-serviceaccount.yaml
```

#### Step 2: Extract Configuration

From your Deployment manifest, extract:

- **Image:** `spec.template.spec.containers[0].image`
- **Resource size:** Map CPU/memory to small/medium/large
- **NATS config:** Environment variables `NATS_URL`, `NATS_STREAM_NAME`, `NATS_CONSUMER_GROUP`
- **Secrets:** Look for `envFrom` or `env` with `secretKeyRef`
- **Init container:** Check `spec.template.spec.initContainers`
- **Image pull secrets:** `spec.template.spec.imagePullSecrets`

#### Step 3: Create EventDrivenService Claim

Create a new file `<service-name>-claim.yaml`:

```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: EventDrivenService
metadata:
  name: <service-name>
  namespace: <namespace>
spec:
  image: <extracted-image>
  size: <small|medium|large>
  
  nats:
    stream: <extracted-stream>
    consumer: <extracted-consumer>
  
  # Add secrets (up to 5)
  secret1Name: <db-secret-name>
  secret2Name: <cache-secret-name>
  secret3Name: <app-secret-name>
  
  # If using private registry
  imagePullSecrets:
    - name: <pull-secret-name>
  
  # If you have init container
  initContainer:
    command: <extracted-command>
    args: <extracted-args>
```

#### Step 4: Validate the Claim

```bash
# Validate against schema
./scripts/validate-claim.sh <service-name>-claim.yaml

# Check for validation errors
echo $?  # Should be 0
```

#### Step 5: Apply the Claim (Dry Run)

```bash
# Dry run to see what will be created
kubectl apply -f <service-name>-claim.yaml --dry-run=server

# Check for any errors
```

#### Step 6: Delete Old Resources

```bash
# Delete old Deployment (this will cause downtime)
kubectl delete deployment <service-name> -n <namespace>

# Delete old Service
kubectl delete service <service-name> -n <namespace>

# Delete old ScaledObject
kubectl delete scaledobject <service-name>-scaler -n <namespace>

# Delete old ServiceAccount
kubectl delete serviceaccount <service-name> -n <namespace>
```

#### Step 7: Apply the Claim

```bash
# Apply EventDrivenService claim
kubectl apply -f <service-name>-claim.yaml

# Wait for resources to be created
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=<service-name> -n <namespace> --timeout=180s
```

#### Step 8: Verify Migration

```bash
# Check claim status
kubectl get eventdrivenservice <service-name> -n <namespace>

# Check all resources created
kubectl get deployment,service,scaledobject,serviceaccount -l app.kubernetes.io/name=<service-name> -n <namespace>

# Check pods are running
kubectl get pods -l app.kubernetes.io/name=<service-name> -n <namespace>

# Check logs
kubectl logs -l app.kubernetes.io/name=<service-name> -n <namespace> --tail=50

# Test health endpoints
kubectl port-forward svc/<service-name> 8080:8080 -n <namespace>
curl http://localhost:8080/health
curl http://localhost:8080/ready
```

#### Step 9: Verify KEDA Autoscaling

```bash
# Check ScaledObject status
kubectl describe scaledobject <service-name>-scaler -n <namespace>

# Publish test messages to NATS
kubectl exec -n nats nats-0 -c nats-box -- \
  nats pub <stream-name> '{"test":"message"}'

# Watch pods scale up
watch kubectl get pods -l app.kubernetes.io/name=<service-name> -n <namespace>
```

### Rollback Procedure

If the migration fails, you can rollback to the original manifests:

```bash
# Delete EventDrivenService claim
kubectl delete eventdrivenservice <service-name> -n <namespace>

# Wait for Crossplane to delete resources
sleep 30

# Restore original manifests
kubectl apply -f backup-deployment.yaml
kubectl apply -f backup-service.yaml
kubectl apply -f backup-scaledobject.yaml
kubectl apply -f backup-serviceaccount.yaml

# Verify rollback
kubectl get pods -l app=<service-name> -n <namespace>
```

### Migration Comparison

**Before (Direct Manifests):**
- 4 separate YAML files
- ~212 lines total
- Manual updates for each resource
- Boilerplate duplication

**After (EventDrivenService API):**
- 1 YAML file
- ~30 lines total
- Single source of truth
- 85% reduction in complexity

### Common Migration Issues

#### Issue: Secret keys don't match environment variable names

**Problem:** Crossplane-generated secrets use keys like `endpoint`, `port`, but your app expects `POSTGRES_HOST`, `POSTGRES_PORT`.

**Solution:** The EventDrivenService uses `envFrom` which mounts all keys as-is. You need to either:
1. Update your application to use the Crossplane key names
2. Create a wrapper secret with the correct key names
3. Use environment variable mapping in your application

#### Issue: Init container needs different image

**Problem:** Your init container uses a different image than the main container.

**Solution:** The EventDrivenService uses the same image for init and main containers. You need to either:
1. Include migration scripts in your main image
2. Use a multi-stage Dockerfile
3. Keep the init container as a separate manifest (not migrated)

#### Issue: Need more than 5 secrets

**Problem:** Your service needs more than 5 secrets.

**Solution:** 
1. Consolidate secrets where possible
2. Create a wrapper secret that combines multiple secrets
3. Fork the Composition to add more secret slots

## Troubleshooting

This section provides comprehensive troubleshooting guidance for common EventDrivenService deployment issues.

### Quick Diagnosis

```bash
# Check claim status
kubectl get eventdrivenservice <name> -n <namespace> -o yaml

# Check all resources
kubectl get deployment,service,scaledobject,serviceaccount -l app.kubernetes.io/name=<name> -n <namespace>

# Check pod status
kubectl get pods -l app.kubernetes.io/name=<name> -n <namespace>

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>

# Check KEDA status
kubectl describe scaledobject <name>-scaler -n <namespace>
```

### Error: ImagePullBackOff

**Symptom:**
```bash
$ kubectl get pods -n <namespace>
NAME                        READY   STATUS             RESTARTS   AGE
my-service-abc123-xyz       0/1     ImagePullBackOff   0          5m
```

**Cause:**
- Image pull secret is missing or invalid
- Image pull secret is not referenced in the claim
- Image doesn't exist in the registry
- Registry credentials are expired

**Diagnosis:**
```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Look for:
# Warning  Failed  Failed to pull image "ghcr.io/org/my-service:v1.0.0":
#   Error response from daemon: pull access denied

# Check if image pull secret exists
kubectl get secret <pull-secret-name> -n <namespace>

# Check if secret is referenced in claim
kubectl get eventdrivenservice <name> -n <namespace> -o yaml | grep imagePullSecrets
```

**Resolution:**

1. **Verify secret exists:**
```bash
kubectl get secret <pull-secret-name> -n <namespace>
```

2. **If secret is missing, create it:**
```bash
# For GitHub Container Registry
kubectl create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=<github-username> \
  --docker-password=<github-token> \
  -n <namespace>
```

3. **Update claim to reference secret:**
```yaml
spec:
  imagePullSecrets:
    - name: ghcr-pull-secret
```

4. **Test credentials manually:**
```bash
docker login ghcr.io -u <username> --password-stdin
docker pull <image>
```

### Error: CreateContainerConfigError

**Symptom:**
```bash
$ kubectl get pods -n <namespace>
NAME                        READY   STATUS                       RESTARTS   AGE
my-service-abc123-xyz       0/1     CreateContainerConfigError   0          2m
```

**Cause:**
- Referenced secret doesn't exist
- Secret is in wrong namespace
- Crossplane claim hasn't created the secret yet
- Secret name is misspelled in the claim

**Diagnosis:**
```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Look for:
# Warning  Failed  Error: secret "my-service-db-conn" not found

# Check if secret exists
kubectl get secret <secret-name> -n <namespace>

# Check Crossplane claim status
kubectl get postgresinstance <name> -n <namespace> -o yaml
kubectl get dragonflyinstance <name> -n <namespace> -o yaml

# Check ExternalSecret status
kubectl get externalsecret <name> -n <namespace> -o yaml
```

**Resolution:**

1. **For Crossplane-generated secrets:**
```bash
# Check if PostgresInstance claim exists
kubectl get postgresinstance <name> -n <namespace>

# Check if claim is ready
kubectl get postgresinstance <name> -n <namespace> -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# Check if secret was created
kubectl get secret <secret-name> -n <namespace>

# If claim is not ready, check events
kubectl describe postgresinstance <name> -n <namespace>
```

2. **For ESO-synced secrets:**
```bash
# Check ExternalSecret status
kubectl get externalsecret <name> -n <namespace>

# Check if secret was synced
kubectl describe externalsecret <name> -n <namespace>

# Check ESO operator logs
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets
```

3. **Verify secret name in claim:**
```bash
# Check claim configuration
kubectl get eventdrivenservice <name> -n <namespace> -o yaml | grep secretName
```

4. **Wait for Crossplane to create secret:**
```bash
# Crossplane may take 30-60 seconds to provision resources
kubectl wait --for=condition=ready postgresinstance <name> -n <namespace> --timeout=180s
```

### Error: Init:CrashLoopBackOff

**Symptom:**
```bash
$ kubectl get pods -n <namespace>
NAME                        READY   STATUS                  RESTARTS   AGE
my-service-abc123-xyz       0/1     Init:CrashLoopBackOff   3          10m
```

**Cause:**
- Init container command failed
- Database migrations failed
- Missing environment variables
- Database is unreachable
- Init container script has bugs

**Diagnosis:**
```bash
# Check init container logs
kubectl logs <pod-name> -n <namespace> -c init

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Look for:
# Warning  BackOff  Back-off restarting failed container init in pod

# Check init container exit code
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.status.initContainerStatuses[0].lastState.terminated.exitCode}'
```

**Resolution:**

1. **Check init container logs for errors:**
```bash
kubectl logs <pod-name> -n <namespace> -c init
```

2. **Verify database connectivity:**
```bash
# Check if database is ready
kubectl get postgresinstance <name> -n <namespace>

# Test database connection from a debug pod
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql -h <db-host> -U <db-user> -d <db-name>
```

3. **Verify environment variables are set:**
```bash
# Check if secrets are mounted
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 10 envFrom

# Verify secret contains required keys
kubectl get secret <secret-name> -n <namespace> -o yaml
```

4. **Check migration script:**
```bash
# Verify script exists in image
kubectl run -it --rm debug --image=<your-image> --restart=Never -- \
  ls -la /app/scripts/ci/run-migrations.sh

# Test script manually
kubectl run -it --rm debug --image=<your-image> --restart=Never -- \
  /bin/bash -c "cd /app && ./scripts/ci/run-migrations.sh"
```

5. **Common init container issues:**
- **Exit code 127:** Command not found (check command path)
- **Exit code 1:** Script failed (check script logic)
- **Exit code 2:** Database connection failed (check database is ready)
- **Exit code 126:** Permission denied (check file permissions)

### Error: KEDA TriggerError

**Symptom:**
```bash
$ kubectl get scaledobject -n <namespace>
NAME                    READY   ACTIVE   TRIGGERS
my-service-scaler       False   False    nats-jetstream
```

**Cause:**
- Wrong NATS endpoint (using `nats` instead of `nats-headless`)
- NATS stream doesn't exist
- Consumer group name mismatch
- NATS monitoring port not accessible
- NATS account configuration incorrect

**Diagnosis:**
```bash
# Check ScaledObject status
kubectl describe scaledobject <name>-scaler -n <namespace>

# Look for:
# Message: Triggers defined in ScaledObject are not working correctly
# Reason: TriggerError

# Check KEDA operator logs
kubectl logs -n keda -l app=keda-operator | grep -i error

# Verify NATS endpoint in ScaledObject
kubectl get scaledobject <name>-scaler -n <namespace> -o yaml | grep natsServerMonitoringEndpoint

# Should show: nats-headless.nats.svc.cluster.local:8222
```

**Resolution:**

1. **Verify NATS endpoint (CRITICAL):**
```bash
# Check if using correct endpoint
kubectl get scaledobject <name>-scaler -n <namespace> -o jsonpath='{.spec.triggers[0].metadata.natsServerMonitoringEndpoint}'

# Should be: nats-headless.nats.svc.cluster.local:8222
# NOT: nats.nats.svc.cluster.local:8222

# The composition uses nats-headless by default (port 8222 is exposed)
```

2. **Verify NATS stream exists:**
```bash
# Check NATS stream
kubectl exec -n nats nats-0 -c nats-box -- \
  nats stream info <stream-name>

# If stream doesn't exist, create it
kubectl exec -n nats nats-0 -c nats-box -- \
  nats stream add <stream-name> \
    --subjects="<subject-pattern>" \
    --retention=workqueue \
    --max-age=24h
```

3. **Verify consumer group:**
```bash
# List consumers for stream
kubectl exec -n nats nats-0 -c nats-box -- \
  nats consumer list <stream-name>

# Check if consumer matches claim
kubectl get eventdrivenservice <name> -n <namespace> -o jsonpath='{.spec.nats.consumer}'
```

4. **Test NATS monitoring endpoint:**
```bash
# Port-forward to nats-headless
kubectl port-forward -n nats svc/nats-headless 8222:8222

# Test monitoring endpoint
curl http://localhost:8222/jsz

# Should return JSON with JetStream stats
```

5. **Check KEDA NATS scaler logs:**
```bash
# Check KEDA metrics server logs
kubectl logs -n keda -l app=keda-metrics-apiserver | grep nats

# Check for connection errors
```

**Common KEDA Issues:**
- **Connection refused:** Using wrong endpoint (nats vs nats-headless)
- **Stream not found:** NATS stream doesn't exist yet
- **Consumer not found:** Consumer group name mismatch
- **Authentication failed:** Account configuration incorrect (should be `$SYS`)

### Error: Pod Pending

**Symptom:**
```bash
$ kubectl get pods -n <namespace>
NAME                        READY   STATUS    RESTARTS   AGE
my-service-abc123-xyz       0/1     Pending   0          15m
```

**Cause:**
- Resource quota exceeded
- Node capacity issues
- Insufficient CPU or memory available
- Pod affinity/anti-affinity constraints
- No nodes match pod requirements

**Diagnosis:**
```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Look for:
# Warning  FailedScheduling  0/2 nodes are available: 2 Insufficient cpu

# Check node resources
kubectl top nodes

# Check resource quotas
kubectl get resourcequota -n <namespace>

# Check pod resource requests
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 5 resources
```

**Resolution:**

1. **Check node capacity:**
```bash
# View node resources
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check if nodes have enough capacity
kubectl top nodes
```

2. **Reduce resource requests:**
```yaml
# Change size from large to medium or small
spec:
  size: medium  # Instead of large
```

3. **Check resource quotas:**
```bash
# View namespace quotas
kubectl describe resourcequota -n <namespace>

# If quota is exceeded, request increase or delete unused resources
```

4. **Add more nodes:**
```bash
# Scale up cluster (platform-specific)
# For Talos: Add worker nodes to cluster
```

### Error: CrashLoopBackOff (Main Container)

**Symptom:**
```bash
$ kubectl get pods -n <namespace>
NAME                        READY   STATUS             RESTARTS   AGE
my-service-abc123-xyz       0/1     CrashLoopBackOff   5          10m
```

**Cause:**
- Application code has bugs
- Missing required environment variables
- Cannot connect to dependencies (database, NATS, cache)
- Health probe failing immediately
- Application exits with error

**Diagnosis:**
```bash
# Check container logs
kubectl logs <pod-name> -n <namespace>

# Check previous container logs (if restarted)
kubectl logs <pod-name> -n <namespace> --previous

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check exit code
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'
```

**Resolution:**

1. **Check application logs:**
```bash
kubectl logs <pod-name> -n <namespace> --tail=100
```

2. **Verify environment variables:**
```bash
# Check if all required env vars are set
kubectl exec <pod-name> -n <namespace> -- env | grep -E "POSTGRES|NATS|DRAGONFLY"
```

3. **Test dependencies:**
```bash
# Test database connection
kubectl exec <pod-name> -n <namespace> -- \
  nc -zv <db-host> 5432

# Test NATS connection
kubectl exec <pod-name> -n <namespace> -- \
  nc -zv nats.nats.svc 4222

# Test cache connection
kubectl exec <pod-name> -n <namespace> -- \
  nc -zv <cache-host> 6379
```

4. **Disable health probes temporarily:**
```bash
# Edit Deployment to remove probes for debugging
kubectl edit deployment <name> -n <namespace>

# Remove livenessProbe and readinessProbe sections
# This allows container to stay running for debugging
```

5. **Common exit codes:**
- **Exit code 0:** Clean exit (check why app is exiting)
- **Exit code 1:** General error (check application logs)
- **Exit code 137:** Killed by OOM (increase memory limits)
- **Exit code 143:** Terminated by SIGTERM (graceful shutdown)

### Diagnostic Commands Reference

Quick reference for common diagnostic commands:

```bash
# Check claim status
kubectl get eventdrivenservice <name> -n <namespace> -o yaml

# Check all resources created by claim
kubectl get deployment,service,scaledobject,serviceaccount \
  -l app.kubernetes.io/name=<name> -n <namespace>

# Check pod status and events
kubectl get pods -l app.kubernetes.io/name=<name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace>

# Check logs (current container)
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> -c init  # Init container

# Check logs (previous container after restart)
kubectl logs <pod-name> -n <namespace> --previous

# Check environment variables
kubectl exec <pod-name> -n <namespace> -- env

# Check secrets
kubectl get secret <secret-name> -n <namespace> -o yaml

# Check KEDA status
kubectl get scaledobject <name>-scaler -n <namespace>
kubectl describe scaledobject <name>-scaler -n <namespace>

# Check NATS stream
kubectl exec -n nats nats-0 -c nats-box -- nats stream info <stream-name>

# Check NATS consumer
kubectl exec -n nats nats-0 -c nats-box -- nats consumer list <stream-name>

# Test health endpoints
kubectl port-forward svc/<name> 8080:8080 -n <namespace>
curl http://localhost:8080/health
curl http://localhost:8080/ready

# Check resource usage
kubectl top pod <pod-name> -n <namespace>
kubectl top nodes

# Check Crossplane claim status
kubectl get postgresinstance <name> -n <namespace> -o yaml
kubectl get dragonflyinstance <name> -n <namespace> -o yaml

# Check ExternalSecret status
kubectl get externalsecret <name> -n <namespace>
kubectl describe externalsecret <name> -n <namespace>

# Check KEDA operator logs
kubectl logs -n keda -l app=keda-operator --tail=50

# Check Crossplane logs
kubectl logs -n crossplane-system -l app=crossplane --tail=50
```

## IDE Integration

Enable IDE autocomplete and validation for EventDrivenService claims.

### VSCode YAML Extension

1. **Install Extension:**
   - Install "YAML" extension by Red Hat

2. **Configure Schema:**

Add to `.vscode/settings.json`:

```json
{
  "yaml.schemas": {
    "./platform/04-apis/schemas/eventdrivenservice.schema.json": [
      "**/eventdrivenservice*.yaml",
      "**/claims/**/*-claim.yaml"
    ]
  }
}
```

3. **Benefits:**
   - ✅ Field autocomplete
   - ✅ Inline validation
   - ✅ Hover documentation
   - ✅ Error highlighting

### IntelliJ IDEA / PyCharm

1. **Configure Schema:**

Add to `.idea/jsonSchemas.xml`:

```xml
<project version="4">
  <component name="JsonSchemaMappingsProjectConfiguration">
    <state>
      <map>
        <entry key="EventDrivenService">
          <value>
            <SchemaInfo>
              <option name="name" value="EventDrivenService" />
              <option name="relativePathToSchema" value="platform/04-apis/schemas/eventdrivenservice.schema.json" />
              <option name="patterns">
                <list>
                  <Item>
                    <option name="pattern" value="**/eventdrivenservice*.yaml" />
                  </Item>
                  <Item>
                    <option name="pattern" value="**/claims/**/*-claim.yaml" />
                  </Item>
                </list>
              </option>
            </SchemaInfo>
          </value>
        </entry>
      </map>
    </state>
  </component>
</project>
```

### Schema Validation in CI

Add to `.github/workflows/validate-claims.yml`:

```yaml
name: Validate EventDrivenService Claims
on: [pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
      
      - name: Install dependencies
        run: |
          npm install -g ajv-cli yq
      
      - name: Validate claims
        run: |
          for claim in platform/04-apis/examples/*.yaml; do
            echo "Validating $claim..."
            ./scripts/validate-claim.sh "$claim"
          done
```

## Examples

The `examples/` directory contains reference implementations:

### minimal-claim.yaml

Simplest possible deployment with just image and NATS configuration. No secrets, no init container, suitable for public images and stateless workers.

**Use case:** Lightweight workers, simple message processors

### full-claim.yaml

Complete deployment demonstrating all features including multiple secrets from different sources (Crossplane + ESO), init container for migrations, and private registry.

**Use case:** Production services with database, cache, and external API dependencies

### agent-executor-claim.yaml

Reference implementation demonstrating migration from 212 lines of direct Kubernetes manifests to ~30 lines using the EventDrivenService API.

**Use case:** Complex production service with all features (database, cache, LLM keys, migrations)

**Migration status:** Validated and ready for deployment (deferred until 2nd NATS service per ARCHITECTURE_DECISION.md)

## Additional Resources

- **XRD Definition:** `definitions/xeventdrivenservices.yaml`
- **Composition:** `compositions/event-driven-service-composition.yaml`
- **JSON Schema:** `schemas/eventdrivenservice.schema.json`
- **Validation Script:** `../../scripts/validate-claim.sh`
- **Requirements:** `../../.kiro/specs/agent-executor/enhanced-platform/requirements.md`
- **Design:** `../../.kiro/specs/agent-executor/enhanced-platform/design.md`

## Support

For issues or questions:

1. Check this documentation first
2. Review the troubleshooting section
3. Check example claims for reference
4. Review KEDA and Crossplane documentation
5. Check platform logs (KEDA, Crossplane, ArgoCD)

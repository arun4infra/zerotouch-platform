# Dragonfly (Redis-compatible) - Zero-Touch Provisioning

## Overview

Dragonfly is a Redis-compatible in-memory database provisioned via Crossplane with **zero-touch credential management**. No SSM, no ExternalSecrets, no manual passwords.

## Quick Start

Create a DragonflyInstance claim - that's it:

```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: DragonflyInstance
metadata:
  name: my-cache
  namespace: my-namespace
spec:
  size: small      # small, medium, large
  storageGB: 10    # optional, default: 10
```

**No credentials to manage. No secret name to specify.**

## Convention Over Configuration

The system uses **predictable naming conventions**:

| You Provide | System Creates |
|-------------|----------------|
| Claim: `my-cache` | Dragonfly StatefulSet: `my-cache` |
| | Service: `my-cache` |
| | Connection Secret: `my-cache-conn` |

**Rule**: Connection secret name = `{claim-name}-conn`

## What Happens Automatically

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Zero-Touch Flow                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   1. You create DragonflyInstance claim                             │
│      └─ name: my-cache                                              │
│                           │                                          │
│                           ▼                                          │
│   2. Crossplane creates Dragonfly resources                         │
│      ├─ StatefulSet: my-cache                                       │
│      └─ Service: my-cache                                           │
│                           │                                          │
│                           ▼                                          │
│   3. Crossplane auto-generates password                             │
│      └─ Creates: my-cache-password secret (internal)                │
│                           │                                          │
│                           ▼                                          │
│   4. Crossplane copies credentials                                   │
│      └─ To: my-cache-conn (your namespace)                          │
│                           │                                          │
│                           ▼                                          │
│   5. Your app reads from secret                                     │
│      └─ secretKeyRef: my-cache-conn                                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**No SSM. No ExternalSecrets. No manual passwords.**

## Connection Secret Format

The auto-created secret `{claim-name}-conn` contains:

| Key | Value |
|-----|-------|
| `endpoint` | `{claim-name}.{namespace}.svc.cluster.local` |
| `port` | `6379` |
| `password` | Auto-generated (UUID) |

## Application Usage

Reference the connection secret in your deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-namespace
spec:
  template:
    spec:
      containers:
        - name: app
          env:
            - name: REDIS_HOST
              valueFrom:
                secretKeyRef:
                  name: my-cache-conn  # {claim-name}-conn
                  key: endpoint
            - name: REDIS_PORT
              valueFrom:
                secretKeyRef:
                  name: my-cache-conn
                  key: port
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: my-cache-conn
                  key: password
```

## Size Options

| Size | Memory (request/limit) | CPU (request/limit) |
|------|------------------------|---------------------|
| small | 512Mi / 2Gi | 250m / 1000m |
| medium | 1Gi / 4Gi | 500m / 2000m |
| large | 2Gi / 8Gi | 1000m / 4000m |

## Complete Example: agent-executor cache

**Claim:**
```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: DragonflyInstance
metadata:
  name: agent-executor-cache
  namespace: intelligence-deepagents
spec:
  size: medium
  storageGB: 10
```

**Result:**
- Dragonfly StatefulSet: `agent-executor-cache`
- Service: `agent-executor-cache`
- Password: Auto-generated
- Connection Secret: `agent-executor-cache-conn`
- Endpoint: `agent-executor-cache.intelligence-deepagents.svc.cluster.local`

**Deployment references:**
```yaml
secretKeyRef:
  name: agent-executor-cache-conn  # Convention: {claim-name}-conn
  key: endpoint
```

## Notes

- Password is auto-generated from composite UID (no SSM required)
- Pods scheduled on nodes with label `workload-type=stateful`
- Uses `local-path` storage class
- Data persisted to `/data` via PVC

## Troubleshooting

### Claim stuck in "Creating"
Check if the StatefulSet is ready:
```bash
kubectl get statefulset <claim-name> -n <namespace>
```

### Connection secret not created
Verify the password secret exists:
```bash
kubectl get secret <claim-name>-password -n <namespace>
```

### Check secret contents
```bash
kubectl get secret <claim-name>-conn -n <namespace> -o jsonpath='{.data.endpoint}' | base64 -d
```

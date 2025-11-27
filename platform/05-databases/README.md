# Database Layer - Crossplane Compositions

This directory contains Crossplane-based database provisioning for the BizMatters platform.

## Structure

```
platform/05-databases/
├── namespace.yaml              # databases namespace
├── provider-config.yaml        # Crossplane Kubernetes provider
├── definitions/                # XRDs (what developers can request)
│   ├── postgres-xrd.yaml
│   └── dragonfly-xrd.yaml
├── compositions/               # How to provision (platform logic)
│   ├── postgres-composition.yaml
│   └── dragonfly-composition.yaml
└── claims/                     # Actual database instances
    ├── postgres-default.yaml
    └── dragonfly-default.yaml
```

## How It Works

### 1. Platform Team Defines (One Time)
- **XRDs** (`definitions/`): Define what developers can request
- **Compositions** (`compositions/`): Define how to provision databases

### 2. Developers Request Databases
Create a simple claim file:

```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: PostgresInstance
metadata:
  name: my-app-db
  namespace: my-app
spec:
  size: medium      # small, medium, large
  version: "16"
  storageGB: 50
```

Crossplane automatically creates:
- StatefulSet (with node affinity, taints, resources)
- Service (with correct naming)
- PVC (with correct storage class)
- Secret (with generated credentials)

## Creating a New Database Instance

### PostgreSQL
```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: PostgresInstance
metadata:
  name: app2-postgres
  namespace: app2
spec:
  size: small       # small: 256Mi-1Gi, medium: 512Mi-2Gi, large: 1Gi-4Gi
  version: "16"     # PostgreSQL version
  storageGB: 20     # Storage size (10-1000 GB)
```

### Dragonfly (Redis-compatible)
```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: DragonflyInstance
metadata:
  name: app2-cache
  namespace: app2
spec:
  size: small       # small: 512Mi-2Gi, medium: 1Gi-4Gi, large: 2Gi-8Gi
  storageGB: 10     # Storage size (5-500 GB)
```

## Size Mappings

### PostgreSQL
| Size   | Memory Request | Memory Limit | CPU Request | CPU Limit | Default Storage |
|--------|---------------|--------------|-------------|-----------|-----------------|
| small  | 256Mi         | 1Gi          | 250m        | 1000m     | 20Gi            |
| medium | 512Mi         | 2Gi          | 500m        | 2000m     | 50Gi            |
| large  | 1Gi           | 4Gi          | 1000m       | 4000m     | 100Gi           |

### Dragonfly
| Size   | Memory Request | Memory Limit | CPU Request | CPU Limit | Default Storage |
|--------|---------------|--------------|-------------|-----------|-----------------|
| small  | 512Mi         | 2Gi          | 250m        | 1000m     | 10Gi            |
| medium | 1Gi           | 4Gi          | 500m        | 2000m     | 25Gi            |
| large  | 2Gi           | 8Gi          | 1000m       | 4000m     | 50Gi            |

## Connection Information

### PostgreSQL
- **DNS**: `<instance-name>.databases.svc.cluster.local:5432`
- **Credentials**: Secret `<instance-name>-secret` in `databases` namespace
  - `POSTGRES_DB`
  - `POSTGRES_USER`
  - `POSTGRES_PASSWORD`

### Dragonfly
- **DNS**: `<instance-name>.databases.svc.cluster.local:6379`
- **Credentials**: Secret `<instance-name>-secret` in `databases` namespace
  - `DRAGONFLY_PASSWORD`

## Scaling

To scale an existing instance:

```yaml
# Edit the claim file
spec:
  size: large        # Change from small to large
  storageGB: 100     # Increase storage
```

Crossplane will automatically:
- Update StatefulSet resources
- Expand PVC (if supported by storage class)
- Maintain data integrity

## Benefits Over Direct StatefulSets

1. **Self-Service**: Developers request databases with simple YAML
2. **Standardization**: All instances follow platform standards
3. **Consistency**: No configuration drift
4. **Lifecycle Management**: Crossplane handles updates, deletions
5. **Scalability**: Easy to create many instances
6. **Abstraction**: Platform team controls implementation details

## Backup

The old direct StatefulSet manifests are preserved in:
```
platform/05-databases.backup/
```

These can be used as reference for the Composition logic.

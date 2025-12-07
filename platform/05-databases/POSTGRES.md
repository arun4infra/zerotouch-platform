# PostgreSQL (CNPG) Database Provisioning

## Quick Start

### 1. Add SSM Parameters

```bash
# .env.ssm
/zerotouch/prod/my-service/postgres/user=my_service_user
/zerotouch/prod/my-service/postgres/password=<secure-password>

# Inject to SSM
./scripts/bootstrap/08-inject-ssm-parameters.sh
```

### 2. Create ExternalSecret

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-service-db-credentials
  namespace: my-namespace
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-parameter-store
    kind: ClusterSecretStore
  target:
    name: my-service-db-credentials
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: /zerotouch/prod/my-service/postgres/user
    - secretKey: password
      remoteRef:
        key: /zerotouch/prod/my-service/postgres/password
```

### 3. Create PostgresInstance Claim

```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: PostgresInstance
metadata:
  name: my-service-db
  namespace: my-namespace
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  size: medium                          # small, medium, large
  version: "16"
  storageGB: 20
  databaseName: my_service_db           # Database to create
  databaseOwner: my_service_user        # MUST match SSM username
  connectionSecretName: my-service-postgres
  credentialsSecretName: my-service-db-credentials
```

> **Important**: `databaseOwner` must match the `username` in SSM.

## Connection Secret

Applications use `connectionSecretName` secret:

| Key | Value |
|-----|-------|
| `endpoint` | `{name}-rw.{namespace}.svc.cluster.local` |
| `port` | `5432` |
| `database` | From `databaseName` |
| `username` | From SSM |
| `password` | From SSM |

## Application Usage

```yaml
env:
  - name: POSTGRES_HOST
    valueFrom:
      secretKeyRef:
        name: my-service-postgres
        key: endpoint
  - name: POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: my-service-postgres
        key: password
```

## Size Options

| Size | Memory | CPU |
|------|--------|-----|
| small | 256Mi-1Gi | 250m-1000m |
| medium | 512Mi-2Gi | 500m-2000m |
| large | 1Gi-4Gi | 1000m-4000m |

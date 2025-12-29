# WebService XRD

The WebService XRD provides a platform abstraction for deploying HTTP services with ingress and database support.

## Features

- **HTTP Services**: Deploy web applications with configurable ports and health checks
- **Database Integration**: Optional PostgreSQL database provisioning
- **External Ingress**: HTTPRoute configuration for external HTTPS access
- **Secret Management**: Support for up to 5 secrets via envFrom
- **Resource Sizing**: Predefined resource allocation (micro/small/medium/large)
- **Init Containers**: Database migrations and pre-start tasks
- **Security**: Pod security contexts and image pull secrets

## Quick Start

### Minimal Example

```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: WebService
metadata:
  name: my-web-service
  namespace: default
spec:
  image: "nginx:1.25"
  port: 80
```

### Full Example

```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: WebService
metadata:
  name: my-api
  namespace: production
spec:
  image: "ghcr.io/org/my-api:v1.0.0"
  port: 8080
  size: medium
  replicas: 3
  databaseName: "my_api"
  secret1Name: my-api-db-conn
  hostname: "api.example.com"
  pathPrefix: "/v1"
```

## Validation

```bash
./scripts/validate-claim.sh examples/minimal-claim.yaml
./scripts/validate-claim.sh --test  # Run test suite
```
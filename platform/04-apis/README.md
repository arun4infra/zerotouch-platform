# Platform APIs (Layer 04)

Crossplane-based platform APIs for deploying and managing application workloads.

## Directory Structure

```
04-apis/
├── event-driven-service/    # NATS JetStream consumer services with KEDA autoscaling
│   ├── compositions/
│   ├── definitions/
│   ├── schemas/
│   ├── examples/
│   ├── tests/
│   ├── docs/
│   └── README.md
└── webservice/              # (Future) HTTP-based web services
```

## Available APIs

### EventDrivenService

Platform API for deploying NATS JetStream consumer services with KEDA autoscaling.

**Features:**
- KEDA autoscaling based on consumer lag
- NATS JetStream pull consumer integration
- Resource sizing presets (small/medium/large)
- Secret management (up to 5 secrets)
- Init container support
- Security hardening

**Quick Start:**
```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: EventDrivenService
metadata:
  name: my-worker
  namespace: workers
spec:
  image: ghcr.io/org/my-worker:v1.0.0
  size: medium
  nats:
    stream: "MY_JOBS"
    consumer: "my-workers"
```

**Documentation:** [event-driven-service/README.md](./event-driven-service/README.md)

## Adding New APIs

When adding a new platform API:

1. Create a new directory: `04-apis/<api-name>/`
2. Use this structure:
   ```
   <api-name>/
   ├── compositions/      # Crossplane Composition
   ├── definitions/       # XRD (Composite Resource Definition)
   ├── schemas/          # JSON Schema for validation
   ├── examples/         # Example claims
   ├── tests/            # Test scripts
   ├── docs/             # Documentation
   └── README.md         # API documentation
   ```
3. Update this README with the new API

## Testing

Each API has its own test suite in its `tests/` directory.

### Run All Tests

```bash
# EventDrivenService tests
./event-driven-service/tests/test-autoscaling.sh
./event-driven-service/tests/test-full-deployment.sh
./event-driven-service/tests/test-minimal-deployment.sh
```

## Shared Resources

- `compositions/` - Compositions used by multiple APIs
- `definitions/` - XRDs used by multiple APIs
- `schemas/` - Schemas used by multiple APIs
- `tests/` - Generic test utilities

## Related Documentation

- [EventDrivenService API](./event-driven-service/README.md)
- [Platform Architecture](../../README.md)

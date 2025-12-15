# EventDrivenService API

Platform API for deploying NATS JetStream consumer services with KEDA autoscaling.

## Directory Structure

```
event-driven-service/
├── compositions/           # Crossplane Composition
├── definitions/           # XRD (Composite Resource Definition)
├── schemas/              # JSON Schema for validation
├── examples/             # Example claims
├── tests/                # Test scripts
└── docs/                 # Documentation
```

## Quick Start

### 1. Deploy a Simple Worker

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

### 2. Run Tests

```bash
# Test autoscaling
./event-driven-service/tests/test-autoscaling.sh

# Test full deployment
./event-driven-service/tests/test-full-deployment.sh

# Test minimal deployment
./event-driven-service/tests/test-minimal-deployment.sh
```

## Features

- ✅ **KEDA Autoscaling** - Scales based on NATS JetStream consumer lag
- ✅ **NATS JetStream Integration** - Pull-based message consumption
- ✅ **Resource Sizing** - Small, medium, large presets
- ✅ **Secret Management** - Up to 5 secret slots via envFrom
- ✅ **Init Containers** - For migrations or pre-start tasks
- ✅ **Security** - Non-root, read-only filesystem, dropped capabilities

## Configuration

### Resource Sizes

| Size   | CPU Request | CPU Limit | Memory Request | Memory Limit |
|--------|-------------|-----------|----------------|--------------|
| small  | 250m        | 1000m     | 512Mi          | 2Gi          |
| medium | 500m        | 2000m     | 1Gi            | 4Gi          |
| large  | 1000m       | 4000m     | 2Gi            | 8Gi          |

### Autoscaling

- **Min Replicas:** 1
- **Max Replicas:** 10
- **Lag Threshold:** 5 messages per pod
- **Cooldown Period:** 30s (testing), 120-300s (production)
- **Polling Interval:** 5s

## Documentation

- [RCA: Autoscaling Fix](./docs/RCA-AUTOSCALING-FIX.md) - Root cause analysis and fixes

## Examples

See [examples/](./examples/) directory for:
- `minimal-claim.yaml` - Minimal configuration
- `full-claim.yaml` - All features enabled
- `agent-executor-claim.yaml` - Real-world example

## Testing

All tests are located in [tests/](./tests/) directory:
- `test-autoscaling.sh` - Validates KEDA autoscaling (scale-up and scale-down)
- `test-full-deployment.sh` - Tests full feature set
- `test-minimal-deployment.sh` - Tests minimal configuration
- `verify-composition.sh` - Validates Crossplane composition
- `verify-keda-config.sh` - Validates KEDA configuration

## Related Files

- Composition: `compositions/event-driven-service-composition.yaml`
- XRD: `definitions/xeventdrivenservices.yaml`
- Schema: `schemas/eventdrivenservice.schema.json`

## Standards

- [NATS Stream Configuration Standard](../../../docs/standards/nats-stream-configuration.md) - How to create streams for your service
- [Namespace Naming Convention](../../../docs/standards/namespace-naming-convention.md) - Namespace naming patterns

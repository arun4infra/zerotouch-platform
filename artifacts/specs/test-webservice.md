---
schema_version: "1.0"
category: spec
resource: test-webservice
api_version: platform.bizmatters.io/v1alpha1
kind: TestWebService
composition_file: platform/03-intelligence/test-webservice.yaml
created_at: 2025-11-29T10:00:00Z
last_updated: 2025-11-29T10:00:00Z
tags:
  - test
  - webservice
---

# TestWebService API Specification

## Overview

| Property | Value |
|:---------|:------|
| **API Group** | `platform.bizmatters.io` |
| **API Version** | `v1alpha1` |
| **Kind** | `TestWebService` |
| **Scope** | Namespaced (via Claim) |
| **Composition** | `test-webservice` |

## Purpose

This is a test composition for validating the Twin Docs workflow:
- Simple web service deployment
- Configurable replicas
- Basic storage configuration

## Configuration Parameters

| Parameter | Type | Required | Default | Validation | Description |
|:----------|:-----|:---------|:--------|:-----------|:------------|
| `spec.parameters.replicas` | integer | No | `1` | 1-10 | Number of pod replicas |
| `spec.parameters.storageSize` | string | No | `10Gi` | Valid k8s quantity | PVC storage size |
| `spec.parameters.image` | string | Yes | `-` | Valid container image | Container image to deploy |

## Managed Resources

| Resource Type | Name Pattern | Namespace | Lifecycle |
|:--------------|:-------------|:----------|:----------|
| Deployment | `{claim-name}` | Same as claim | Deleted with claim |
| Service | `{claim-name}-svc` | Same as claim | Deleted with claim |
| PersistentVolumeClaim | `{claim-name}-data` | Same as claim | Deleted with claim |

## Example Usage

```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: TestWebService
metadata:
  name: my-test-service
  namespace: production
spec:
  parameters:
    replicas: 3
    storageSize: 20Gi
    image: nginx:latest
```

## Dependencies

| Dependency | Required For | Notes |
|:-----------|:-------------|:------|
| StorageClass | PVC provisioning | Uses default StorageClass |
| LoadBalancer | External access | Optional, uses ClusterIP by default |

## Version History

| Version | Date | Changes | PR |
|:--------|:-----|:--------|:---|
| v1alpha1 | 2025-11-29 | Initial test composition | #TBD |

## Related Documentation

- [Twin Docs Workflow Spec](../../.kiro/specs/twin-docs-workflow/overview.md)
- [Intelligence Layer](../../../platform/03-intelligence/README.md)

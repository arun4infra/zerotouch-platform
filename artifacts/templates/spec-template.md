---
schema_version: "1.0"
category: spec
resource: RESOURCE_NAME              # Must match composition filename (kebab-case)
api_version: platform.bizmatters.io/v1alpha1
kind: ResourceKind                   # e.g., WebService, PostgreSQL, Dragonfly
composition_file: platform/apis/compositions/RESOURCE_NAME.yaml
created_at: YYYY-MM-DDTHH:MM:SSZ
last_updated: YYYY-MM-DDTHH:MM:SSZ
tags:
  - api
  - category
---

# {Resource Kind} API Specification

## Overview

| Property | Value |
|:---------|:------|
| **API Group** | `platform.bizmatters.io` |
| **API Version** | `v1alpha1` |
| **Kind** | `ResourceKind` |
| **Scope** | Namespaced (via Claim) |
| **Composition** | `composition-name` |

## Purpose

Brief description of what this resource provisions (use bullet list):
- Component 1
- Component 2
- Optional: Component 3

## Configuration Parameters

| Parameter | Type | Required | Default | Validation | Description |
|:----------|:-----|:---------|:--------|:-----------|:------------|
| `spec.fieldName` | string/integer/boolean | Yes/No | value or `-` | Constraints | What this parameter controls |

## Managed Resources

| Resource Type | Name Pattern | Namespace | Lifecycle |
|:--------------|:-------------|:----------|:----------|
| Deployment | `{claim-name}` | Same as claim | Deleted with claim |
| Service | `{claim-name}-svc` | Same as claim | Deleted with claim |

## Example Usage

```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: ResourceKind
metadata:
  name: example-name
  namespace: production
spec:
  # Example configuration
  field1: value1
  field2: value2
```

## Dependencies

| Dependency | Required For | Notes |
|:-----------|:-------------|:------|
| Component name | Feature or parameter | Details about dependency |

## Version History

| Version | Date | Changes | PR |
|:--------|:-----|:--------|:---|
| v1alpha1 | YYYY-MM-DD | Initial release | #PR_NUMBER |

## Related Documentation

- [Link to related architecture docs](../architecture/xxx.md)
- [Link to related runbooks](../runbooks/xxx.md)

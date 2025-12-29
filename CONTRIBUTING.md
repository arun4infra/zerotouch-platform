# Contributing to ZeroTouch Platform

This guide covers key patterns, architectural decisions, and best practices for contributing to the ZeroTouch Platform. It's based on real implementation experience from creating new platform APIs like the WebService XRD.

## Philosophy

- README.md
- docs/architecture/platform-overview.md

## Table of Contents

- [Platform Architecture Overview](#platform-architecture-overview)
- [Creating New Platform APIs (XRDs)](#creating-new-platform-apis-xrds)
- [Directory Structure Patterns](#directory-structure-patterns)
- [Crossplane XRD Best Practices](#crossplane-xrd-best-practices)
- [Composition Patterns](#composition-patterns)
- [Validation and Testing](#validation-and-testing)
- [ArgoCD Integration](#argocd-integration)
- [Secret Management Patterns](#secret-management-patterns)
- [Resource Sizing Standards](#resource-sizing-standards)
- [Common Pitfalls and Solutions](#common-pitfalls-and-solutions)

## Platform Architecture Overview

The ZeroTouch Platform follows a layered GitOps architecture:

```
┌─────────────────────────────────────────────────────────────┐
│ ArgoCD (GitOps Controller)                                  │
├─────────────────────────────────────────────────────────────┤
│ Layer 1: Foundation (Crossplane, KEDA, Cilium)             │
│ Layer 2: Databases (PostgreSQL, Dragonfly)                 │
│ Layer 3: Platform APIs (EventDrivenService, WebService)    │
│ Layer 4: Intelligence (deepagents-runtime, IDE Orchestrator)│
│ Layer 5: Observability (Monitoring, Logging)               │
└─────────────────────────────────────────────────────────────┘
```

### Key Principles

1. **GitOps-First**: All infrastructure is declared in Git and managed by ArgoCD
2. **Crossplane Abstractions**: Platform APIs hide Kubernetes complexity
3. **Consistent Patterns**: Standardized approaches across all components
4. **Validation-Driven**: Comprehensive testing at every layer
5. **Security by Default**: Pod security contexts, RBAC, secret management

## Creating New Platform APIs (XRDs)

### 1. Directory Structure Pattern

When creating a new platform API, follow this exact structure:

```
platform/apis/your-service/
├── definitions/
│   └── xyourservices.yaml          # XRD definition
├── compositions/
│   └── your-service-composition.yaml # Composition implementation
├── examples/
│   ├── minimal-claim.yaml          # Simplest possible example
│   ├── full-claim.yaml             # All features demonstrated
│   └── reference-claim.yaml        # Real-world reference
├── tests/
│   └── fixtures/
│       ├── valid-*.yaml            # Valid test cases
│       └── invalid-*.yaml          # Invalid test cases (should fail)
├── scripts/
│   └── validate-claim.sh           # Validation script
└── README.md                       # Documentation
```

### 2. XRD Naming Conventions

- **XRD Name**: `x{servicename}s.platform.bizmatters.io`
- **Claim Name**: `{ServiceName}` (PascalCase)
- **Claim Plural**: `{servicename}s` (lowercase)
- **Composition Name**: `{servicename}` (lowercase, matches directory)

Example:
```yaml
# XRD
metadata:
  name: xwebservices.platform.bizmatters.io
spec:
  names:
    kind: XWebService
    plural: xwebservices
  claimNames:
    kind: WebService
    plural: webservices
```

### 2. Enum Validation for Consistency

Use enums for standardized values:

```yaml
size:
  type: string
  enum: [micro, small, medium, large]  # Matches resource sizing standard
  
databaseSize:
  type: string
  enum: [micro, small, medium, large]  # Consistent across all services
```

## Validation and Testing

### 1. Bootstrap Validation Script Pattern

Create validation scripts following this template:

```bash
#!/bin/bash
# Verify YourService Platform API
# Usage: ./XX-verify-yourservice-api.sh

# Standard validation checks:
# 1. ArgoCD Application sync status
# 2. XRD installation and version
# 3. Composition existence and resource count
# 4. Dry-run claim validation
# 5. Integration dependencies (database XRDs, Gateway API)
# 6. Test suite execution
```

### 2. Claim Validation Script Pattern

```bash
#!/bin/bash
# YourService Claim Validation Script
# Features:
# - Individual claim validation
# - Test suite execution (--test flag)
# - Detailed error reporting
# - Prerequisites checking
# - Summary with next steps
```

### 3. Test Fixture Patterns

Always create these test fixtures:

```yaml
# tests/fixtures/valid-minimal.yaml - Absolute minimum
spec:
  image: "nginx:1.25"
  port: 80

# tests/fixtures/valid-full.yaml - All features
spec:
  image: "ghcr.io/org/service:v1.0.0"
  port: 8080
  size: medium
  # ... all optional fields

# tests/fixtures/invalid-*.yaml - Various failure modes
# - missing required fields
# - invalid enum values  
# - malformed patterns
```

## ArgoCD Integration

### 1. Automatic Deployment

Platform APIs are automatically deployed by ArgoCD via the `04-apis.yaml` application:

```yaml
# bootstrap/argocd/base/04-apis.yaml
spec:
  source:
    path: platform/apis
    directory:
      recurse: true
      exclude: '{**/schemas/*,**/tests/*,**/examples/*,**/*.md,**/*.json}'
```

**Key Points:**
- No manual deployment scripts needed
- XRDs and Compositions are automatically applied
- Examples and tests are excluded from deployment
- Changes are automatically synced via GitOps

### 2. Sync Wave Ordering

Platform APIs deploy in wave 5 (after foundation and databases):

```
Wave 0: Crossplane, KEDA, External Secrets
Wave 1: Database XRDs  
Wave 5: Platform APIs (EventDrivenService, WebService)
Wave 10: Application deployments
```

## Secret Management Patterns

### 1. Standard Secret Slots

Always use this exact pattern for secret management:

```yaml
# XRD Schema
secret1Name:
  type: string
  description: "First secret (typically database credentials)"
secret2Name:
  type: string  
  description: "Second secret (typically JWT keys)"
secret3Name:
  type: string
  description: "Third secret (typically application secrets)"
secret4Name:
  type: string
  description: "Fourth secret (optional)"
secret5Name:
  type: string
  description: "Fifth secret (optional)"
```

### 2. EnvFrom Pattern

Always use `envFrom` for bulk secret mounting:

```yaml
# Composition
envFrom:
  - secretRef:
      name: placeholder-secret1
      optional: true
  - secretRef:
      name: placeholder-secret2  
      optional: true
  # ... up to secret5
```

### 3. Secret Naming Convention

Follow this pattern for secret names:

```yaml
# Format: {service-name}-{purpose}
secret1Name: "my-service-db-conn"      # Database credentials
secret2Name: "my-service-jwt-keys"     # JWT signing keys
secret3Name: "my-service-app-secrets"  # Application configuration
```

## Resource Sizing Standards

### 1. Standard Size Definitions

Always use these exact resource allocations:

```yaml
size_map:
  micro:
    cpu_request: "100m"
    cpu_limit: "500m"
    memory_request: "256Mi"
    memory_limit: "1Gi"
  small:
    cpu_request: "250m"
    cpu_limit: "1000m"
    memory_request: "512Mi"
    memory_limit: "2Gi"
  medium:
    cpu_request: "500m"
    cpu_limit: "2000m"
    memory_request: "1Gi"
    memory_limit: "4Gi"
  large:
    cpu_request: "1000m"
    cpu_limit: "4000m"
    memory_request: "2Gi"
    memory_limit: "8Gi"
```

## Development Workflow

### 1. Creating a New Platform API

1. **Create directory structure** following the pattern
2. **Define XRD schema** with proper validation
3. **Implement composition** with all resource templates
4. **Create examples** (minimal, full, reference)
5. **Write test fixtures** (valid and invalid cases)
6. **Create validation scripts** (bootstrap and claim validation)
7. **Test locally** with dry-run validation

**COMMAND TO RUN LOCAL CLUSTER WITH ALL SERVICES DEPLOYED:**
- kubectl edit to remove the automated section
  - kubectl get application apis -n argocd -o yaml > /tmp/apis-app.yaml && sed '/automated:/,/selfHeal: true/d' /tmp/apis-app.yaml > /tmp/apis-app-modified.yaml && kubectl apply -f /tmp/apis-app-modified.yaml

- Verify Auto Sync is Now Disabled
  - kubectl get application apis -n argocd -o jsonpath='{.spec.syncPolicy}' | jq .

8. **Submit PR** with comprehensive testing

### 2. Testing Checklist

Before submitting a PR, verify:

- [ ] XRD validates with `kubectl apply --dry-run=client`
- [ ] Composition validates with `kubectl apply --dry-run=client`
- [ ] All examples validate successfully
- [ ] Invalid test fixtures are properly rejected
- [ ] Validation scripts execute without errors
- [ ] Documentation is complete and accurate
- [ ] Follows all naming conventions and patterns

### 3. Integration Testing

After deployment to cluster:

- [ ] Run bootstrap validation script
- [ ] Deploy minimal example and verify resources
- [ ] Deploy full example and test all features
- [ ] Verify ArgoCD sync status
- [ ] Test claim validation script
- [ ] Run full test suite

## Getting Help

- **Architecture Questions**: Review existing XRDs (EventDrivenService, WebService)
- **Crossplane Issues**: Check Crossplane documentation and GitHub issues
- **Platform Patterns**: This guide covers most common patterns
- **Validation Problems**: Use the validation scripts for debugging

## Contributing Guidelines

1. **Follow Patterns**: Use existing XRDs as templates
2. **Comprehensive Testing**: Include validation scripts and test fixtures
3. **Clear Documentation**: Examples and README are essential
4. **Security First**: Always include proper security contexts
5. **Consistent Naming**: Follow the established conventions
6. **GitOps Ready**: Ensure ArgoCD can deploy automatically

This guide reflects real implementation experience and should be updated as new patterns emerge.
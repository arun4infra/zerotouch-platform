# Bootstrap and Validation Scripts Context

## Overview

The `scripts/` directory contains the critical automation that enables ZeroTouch Platform's "Zero-Touch Operations" philosophy. These scripts implement the complete deployment lifecycle from bare-metal provisioning to post-deployment validation.

## Directory Structure

```
scripts/
├── bootstrap/
│   ├── 01-master-bootstrap.sh          # Main entry point - orchestrates entire platform deployment
│   ├── wait/                           # Asynchronous resource readiness scripts
│   ├── validation/                     # Post-deployment stability validation
│   │   ├── 99-validate-cluster.sh      # Main validation entry point
│   │   └── 04-apis/                    # Platform API validation scripts
│   └── helpers/                        # Shared utilities and diagnostics
```

## Core Principles

### 1. Zero-Touch Operations
- **Purpose**: Eliminate all manual intervention in platform management
- **Implementation**: Fully automated deployment, validation, and troubleshooting
- **Result**: Platform can be deployed and validated without human SSH access

### 2. Crash-Only Recovery
- **Purpose**: Enable complete platform rebuild from Git in <15 minutes
- **Implementation**: Bootstrap scripts recreate entire platform from scratch
- **Result**: Disaster recovery is faster than debugging broken systems

### 3. GitOps Validation
- **Purpose**: Ensure desired state in Git matches actual cluster state
- **Implementation**: Post-deployment validation verifies ArgoCD sync success
- **Result**: Confidence that platform matches Git configuration

## Bootstrap Scripts (`scripts/bootstrap/`)

### Master Bootstrap (`01-master-bootstrap.sh`)
- **Role**: Single entry point for complete platform deployment
- **Modes**: 
  - Production: Bare-metal Talos clusters
  - Preview: Kind clusters for CI/CD testing
- **Process**: Orchestrates Talos installation → ArgoCD → Platform components
- **Idempotency**: Can be run multiple times safely

### Wait Scripts (`scripts/bootstrap/wait/`)
- **Purpose**: Handle asynchronous Kubernetes deployment nature
- **Critical Function**: Prevent race conditions during bootstrap
- **Examples**: Wait for ArgoCD sync, pods ready, XRDs established
- **Why Essential**: Later bootstrap steps depend on earlier components being fully operational

### Helper Scripts (`scripts/bootstrap/helpers/`)
- **Purpose**: Shared functionality across bootstrap and validation scripts
- **Key Component**: `diagnostics.sh` - provides detailed troubleshooting when failures occur
- **Functions**: kubectl utilities, ArgoCD diagnostics, resource status checks

## Validation Scripts (`scripts/bootstrap/validation/`)

### Critical Understanding: These are POST-DEPLOYMENT INTEGRATION TESTS
- **NOT unit tests** - they validate real environment stability
- **Method**: Apply actual configurations to live environment and test functionality
- **Scope**: Validate services deployed ON the platform, not core platform components
- **Timing**: Run after each deployment to ensure stability

### Main Validation Entry Point (`99-validate-cluster.sh`)
**Validates deployed services:**
- ArgoCD Applications (sync/health status)
- External Secrets (credential sync from AWS SSM)
- ClusterSecretStore (AWS Parameter Store connectivity)
- Platform APIs (EventDrivenService, WebService functionality)
- Configuration drift detection

**Does NOT validate core platform components** (Talos, Kubernetes, Cilium, etc.)

### Platform API Validation (`04-apis/`)
**Purpose**: Validate custom Platform APIs that are core to platform functionality

**Validation Method:**
1. Verify XRDs (Custom Resource Definitions) are installed
2. Verify Compositions (Crossplane) are deployed
3. Test actual resource creation with real claims
4. Validate generated Kubernetes resources meet standards
5. Test service functionality and communication

## Critical Rules

### 1. Mandatory Validation Coverage
**Rule**: No platform changes (additions, removals, modifications) can be implemented without corresponding post-deployment validations.

**Why**: Ensures platform stability and prevents broken deployments from reaching production.

**Implementation**: Every new service, API, or component must include validation scripts that verify its functionality in the deployed environment.

### 2. CI/CD Integration
**Rule**: All validation scripts must pass in CI before deployment to production.

**Why**: Prevents broken deployments and maintains platform reliability.

**Implementation**: GitHub Actions runs complete bootstrap + validation cycle for every change.

### 3. Environment Parity
**Rule**: Validation scripts must work in both preview (Kind) and production (Talos) modes.

**Why**: Ensures CI testing accurately reflects production behavior.

**Implementation**: Scripts detect environment and adapt behavior accordingly.

## Platform Stability Impact

### Bootstrap Scripts Enable:
- **Rapid Recovery**: Complete platform rebuild in <15 minutes
- **Consistency**: Identical deployments across environments
- **Automation**: Zero manual intervention required

### Validation Scripts Ensure:
- **Reliability**: Every deployment is verified functional before use
- **Confidence**: Changes don't break existing functionality
- **Debugging**: Detailed diagnostics when issues occur

### Combined Result:
- **Zero-Touch Operations**: Platform manages itself
- **Crash-Only Recovery**: Rebuild faster than debug
- **GitOps Compliance**: Git state matches cluster state

## Development Guidelines

### Adding New Services
1. Implement service deployment manifests
2. Create corresponding validation scripts in `scripts/bootstrap/validation/`
3. Ensure validation covers all service functionality
4. Test in both preview and production modes
5. Integrate into CI/CD pipeline

### Modifying Existing Services
1. Update deployment manifests
2. Update corresponding validation scripts
3. Ensure backward compatibility or migration path
4. Verify all existing validations still pass

### Validation Script Requirements
- Must test actual functionality, not just resource existence
- Must provide detailed diagnostics on failure
- Must work in both Kind (CI) and Talos (production) environments
- Must be idempotent and safe to run multiple times
- Must fail fast with clear error messages

## Troubleshooting

### When Bootstrap Fails
1. Check individual script logs for specific failure points
2. Use diagnostic helpers to inspect cluster state
3. Verify prerequisites (AWS credentials, network access)
4. Check for resource conflicts or insufficient permissions

### When Validation Fails
1. Run individual validation scripts to isolate issues
2. Use `kubectl describe` on failing resources
3. Check ArgoCD application sync status
4. Review recent events and logs
5. Verify external dependencies (AWS SSM, GitHub access)

This automation is the foundation that enables ZeroTouch Platform's autonomous operation and rapid recovery capabilities.
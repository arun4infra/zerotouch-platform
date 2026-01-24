# Inter-Service Testing in Kubernetes Cluster

## Overview
Testing communication between services within a Kubernetes cluster using validation jobs.

## Pattern: Kubernetes Job-Based Validation

### Structure
```
scripts/bootstrap/validation/{service}/
├── Dockerfile                    # Validation container
├── {NN}-validate-{feature}.py   # Python validation script
├── {NN}-{feature}-job.yaml      # Kubernetes Job manifest
└── {NN}-run-{feature}.sh        # Execution wrapper
```

### Key Components

**1. Validation Script (Python)**
- Uses cluster DNS for service discovery
- Implements retry logic with exponential backoff
- Provides detailed logging for debugging
- Returns proper exit codes (0=success, 1=failure)

**2. Kubernetes Job Manifest**
- Runs in target namespace with proper RBAC
- Uses `imagePullPolicy: Never` for local images
- Includes environment variables for service hosts
- Sets `backoffLimit: 0` for immediate failure reporting

**3. Service Discovery**
```python
# Priority order for service discovery
service_host = os.getenv('SERVICE_HOST')  # Environment override
if not service_host:
    # Cluster DNS: service.namespace.svc.cluster.local:port
    service_host = f"{service_name}.{namespace}.svc.cluster.local:{port}"
```

## Testing Patterns

### HTTP Service Communication
- Test endpoint accessibility and response codes
- Validate request/response headers and body content
- Check error handling and timeout behavior
- Verify service health endpoints

### Service Dependencies
- Test service-to-service API calls
- Validate data flow between components
- Check authentication/authorization between services
- Verify configuration and environment variables

### Common Test Scenarios
1. **Service Availability** - Target service responds to health checks
2. **API Functionality** - Endpoints return expected responses
3. **Error Handling** - Services handle failures gracefully
4. **Configuration** - Services use correct settings and secrets
5. **Integration** - Multi-service workflows function correctly

## Debugging Common Issues

**Service Discovery Problems**
- Verify service exists: `kubectl get svc -n {namespace}`
- Check DNS resolution from within cluster
- Validate port configuration and service labels

**Network Connectivity**
- Use HTTP for in-cluster communication (not HTTPS unless configured)
- Check NetworkPolicies that might block traffic
- Verify service mesh configuration if applicable

**Authentication/Authorization**
- Distinguish between 401 (unauthenticated) and 403 (unauthorized)
- Validate headers, cookies, and tokens in requests
- Check RBAC permissions for service accounts

## Execution Pattern

```bash
# Build validation image
docker build -t validation-{service}:latest .

# Load into cluster
kind load docker-image validation-{service}:latest --name {cluster-name}

# Run validation job
kubectl apply -f {job-manifest}.yaml

# Check results
kubectl logs -l job-name={job-name} -n {namespace}

# Cleanup
kubectl delete job {job-name} -n {namespace}
```

## Best Practices

1. **Environment Detection** - Adapt tests based on deployment environment
2. **Detailed Logging** - Include request/response details for debugging
3. **Proper Cleanup** - Jobs auto-delete with `ttlSecondsAfterFinished`
4. **Resource Limits** - Set appropriate CPU/memory limits
5. **RBAC Minimal** - Grant only required permissions for testing
6. **Retry Logic** - Handle transient network issues gracefully
7. **Test Isolation** - Ensure tests don't interfere with each other
8. **Clear Assertions** - Provide specific error messages for failures
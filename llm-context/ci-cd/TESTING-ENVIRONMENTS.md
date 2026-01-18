# Identity Service Testing Environments

## Environment-Specific Database Configuration

### Local Development & PR Branch Testing
- **Database Source**: In-cluster PostgreSQL via platform claim
- **Configuration**: `zerotouch-tenants/tenants/identity-service/overlays/pr/postgres-claim.yaml`
- **Testing Method**: In-cluster integration tests
- **External Dependencies**: None - uses cluster infrastructure

### Main Branch (DEV Environment)
- **Database Source**: Neon PostgreSQL (external)
- **Configuration**: Environment variables from AWS SSM via ExternalSecrets
- **Testing Method**: CI pipeline with external Neon DB
- **External Dependencies**: Neon PostgreSQL connection

## Testing Strategy

### Local/PR Testing Flow
1. Apply PostgreSQL claim to cluster
2. Run in-cluster integration tests using cluster DB
3. Validate against real PostgreSQL infrastructure
4. No external database URLs required

### Main Branch Testing Flow
1. Use Neon DB URL from environment variables
2. Run integration tests against external Neon instance
3. Production-like database configuration
4. External dependency on Neon service

## Key Differences
- **Local/PR**: Self-contained cluster testing with platform-provided PostgreSQL
- **Main**: External Neon DB for production-like validation
- **Isolation**: Local/PR tests don't affect production data
- **Speed**: Local/PR tests faster due to cluster-local database
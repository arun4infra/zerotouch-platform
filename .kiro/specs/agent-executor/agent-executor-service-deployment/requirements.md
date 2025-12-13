# Requirements Document: Agent Executor Service Deployment

## Introduction

This specification defines the requirements for deploying the agent_executor service using the AgentExecutor platform API. This specification is intended for the **private bizmatters repository** and covers application-specific code changes, claim creation, and deployment configuration.

**Note:** This spec should be moved to `bizmatters/.kiro/specs/agent-executor-deployment/` after creation.

The agent_executor is a Python-based LangGraph agent execution service that processes agent execution requests via NATS messaging, maintains state in PostgreSQL, and streams real-time events via Dragonfly (Redis-compatible cache).

## Glossary

- **Agent Executor**: A Python service that executes LangGraph agents with stateful checkpointing
- **NATS Consumer**: A process that subscribes to NATS subjects and processes messages
- **Dragonfly**: Modern Redis-compatible in-memory data store used for real-time event streaming
- **PostgreSQL**: Relational database for LangGraph checkpoint persistence
- **ESO**: External Secrets Operator - Kubernetes operator that syncs secrets from external sources
- **CloudEvents**: Standardized event format for cross-platform event communication
- **LangGraph**: Framework for building stateful, multi-actor applications with LLMs
- **Claim**: A namespace-scoped request for platform resources (AgentExecutor instance)
- **ImagePullSecret**: Kubernetes secret for authenticating to private container registries

## Requirements

### Requirement 1

**User Story:** As a backend developer, I want agent_executor to support both HTTP and NATS invocation patterns, so that the service can handle direct HTTP requests for testing and NATS messages for production workloads.

#### Acceptance Criteria

1. THE agent_executor service SHALL run as a single Python process with both HTTP server and NATS consumer
2. WHEN the service starts THEN the system SHALL establish a NATS connection and start consuming messages in a background task
3. THE service SHALL keep the existing HTTP CloudEvent endpoint at POST / for direct invocation
4. THE service SHALL expose HTTP endpoints for /health, /ready, and /metrics on port 8080
5. WHEN a NATS message arrives THEN the system SHALL parse it as a CloudEvent and execute the agent using the same logic as the HTTP endpoint

### Requirement 2

**User Story:** As a backend developer, I want database migrations to run automatically before the service starts, so that schema changes are applied without manual intervention.

#### Acceptance Criteria

1. THE migration script SHALL be located at scripts/ci/run-migrations.sh
2. THE script SHALL execute database migrations using psql directly (no kubectl)
3. THE script SHALL read database credentials from environment variables
4. THE script SHALL exit with non-zero code if migrations fail
5. THE script SHALL work inside a Kubernetes init container without cluster access

### Requirement 3

**User Story:** As a backend developer, I want integration tests to use Dragonfly instead of Redis, so that tests match the production environment.

#### Acceptance Criteria

1. THE integration test docker-compose.test.yml SHALL use Dragonfly container instead of Redis
2. THE Python code SHALL continue using the redis library for Dragonfly connectivity
3. WHEN integration tests run THEN the system SHALL connect to Dragonfly on localhost:16380
4. THE Dragonfly container SHALL be Redis-compatible and support pub/sub operations
5. THE test fixtures SHALL verify Dragonfly connectivity before running tests

### Requirement 4

**User Story:** As a backend developer, I want agent_executor to process CloudEvents from NATS messages, so that the service integrates with the platform's event-driven architecture.

#### Acceptance Criteria

1. WHEN a NATS message arrives THEN the system SHALL parse it as a CloudEvent
2. THE CloudEvent data SHALL contain a JobExecutionEvent with job_id and agent_definition
3. WHEN execution completes THEN the system SHALL publish a result CloudEvent to NATS
4. THE result CloudEvent SHALL be published to subject agent.status.completed or agent.status.failed
5. THE system SHALL acknowledge NATS messages only after successful processing

### Requirement 5

**User Story:** As a backend developer, I want agent_executor to persist execution state in PostgreSQL, so that agent executions can be resumed after failures.

#### Acceptance Criteria

1. WHEN an agent execution starts THEN the system SHALL create a checkpoint in PostgreSQL
2. THE system SHALL use the job_id as the thread_id for LangGraph checkpointing
3. WHEN execution progresses THEN the system SHALL update checkpoints incrementally
4. IF the service restarts THEN the system SHALL resume executions from the last checkpoint
5. THE system SHALL connect to PostgreSQL using credentials from environment variables

### Requirement 6

**User Story:** As a backend developer, I want agent_executor to stream real-time events via Dragonfly, so that clients can monitor execution progress.

#### Acceptance Criteria

1. WHEN an agent execution produces events THEN the system SHALL publish to Dragonfly pub/sub channels
2. THE system SHALL use channel pattern langgraph:stream:{thread_id}
3. WHEN execution completes THEN the system SHALL publish an end event
4. THE system SHALL support streaming of LLM tokens, tool calls, and state transitions
5. THE system SHALL connect to Dragonfly using credentials from environment variables

### Requirement 7

**User Story:** As a backend developer, I want Vault client code removed from agent_executor, so that the service uses Kubernetes Secrets managed by External Secrets Operator.

#### Acceptance Criteria

1. THE agent_executor SHALL remove the services/vault.py module completely
2. THE api/main.py SHALL read secrets from environment variables
3. THE system SHALL read PostgreSQL credentials from environment variables (POSTGRES_HOST, POSTGRES_PORT, etc.)
4. THE system SHALL read Dragonfly credentials from environment variables (DRAGONFLY_HOST, DRAGONFLY_PORT, etc.)
5. THE system SHALL read LLM API keys from environment variables (OPENAI_API_KEY, ANTHROPIC_API_KEY)

### Requirement 8

**User Story:** As a backend developer, I want agent_executor code to support NATS consumer as a background task, so that the service can process messages from both HTTP and NATS sources.

#### Acceptance Criteria

1. THE agent_executor SHALL add a new services/nats_consumer.py module for NATS message consumption
2. THE NATS consumer SHALL run as an asyncio background task started by FastAPI lifespan
3. THE NATS consumer SHALL call the same process_execution_request function as the HTTP endpoint
4. THE NATS consumer SHALL publish result CloudEvents back to NATS
5. THE scripts/ci/run.sh SHALL start uvicorn which initializes both HTTP server and NATS consumer

### Requirement 9

**User Story:** As a backend developer, I want integration tests updated for NATS architecture, so that tests validate the complete message processing flow.

#### Acceptance Criteria

1. THE integration tests SHALL add NATS service to docker-compose.test.yml
2. THE integration tests SHALL remove K_SINK HTTP POST mocking
3. THE integration tests SHALL verify result CloudEvents are published to NATS
4. THE integration tests SHALL add test case for NATS consumer message processing
5. THE integration tests SHALL verify Dragonfly streaming events are published

### Requirement 10

**User Story:** As a platform operator, I want agent_executor deployed in the intelligence-deepagents namespace, so that it follows the platform's namespace naming convention.

#### Acceptance Criteria

1. THE agent_executor service SHALL be deployed in the intelligence-deepagents namespace
2. THE namespace SHALL follow the pattern {layer}-{category}
3. THE namespace SHALL have labels: layer=intelligence, category=deepagents
4. THE namespace definition SHALL be in platform/claims/intelligence-deepagents/namespace.yaml
5. THE namespace SHALL be created before deploying the claim

### Requirement 11

**User Story:** As a platform operator, I want databases provisioned via Crossplane claims, so that infrastructure follows the "Database per Service" pattern with zero-touch provisioning.

#### Acceptance Criteria

1. THE system SHALL create PostgresInstance claim for agent_executor database
2. THE system SHALL create DragonflyInstance claim for agent_executor cache
3. THE claims SHALL use writeConnectionSecretToRef to generate connection secrets
4. THE Crossplane-generated secrets SHALL be created in the intelligence-deepagents namespace
5. THE claims SHALL be in platform/claims/intelligence-deepagents/ directory

### Requirement 11b

**User Story:** As a security engineer, I want LLM API keys and registry credentials managed via External Secrets Operator (ESO), so that credentials are stored securely in AWS SSM Parameter Store and synced automatically to the cluster.

#### Acceptance Criteria

1. THE system SHALL create ExternalSecret resource for LLM API keys
2. THE system SHALL create ExternalSecret resource for GitHub registry credentials
3. THE ExternalSecrets SHALL reference the ClusterSecretStore aws-parameter-store
4. THE ExternalSecrets SHALL be in platform/claims/intelligence-deepagents/external-secrets/ directory
5. THE database credentials SHALL NOT be stored in AWS SSM (managed by Crossplane)

### Requirement 12

**User Story:** As a backend developer, I want agent_executor deployed via AgentExecutor claim, so that the service uses the platform API for deployment.

#### Acceptance Criteria

1. THE agent_executor SHALL be deployed by creating an AgentExecutor claim
2. THE claim SHALL specify the private container image from ghcr.io
3. THE claim SHALL specify size: medium for resource allocation
4. THE claim SHALL reference the ExternalSecret-created secrets
5. THE claim SHALL be in platform/claims/intelligence-deepagents/agent-executor-claim.yaml

### Requirement 13

**User Story:** As a backend developer, I want NATS stream and consumer configured for agent_executor, so that the service can process execution requests.

#### Acceptance Criteria

1. THE NATS stream SHALL be named AGENT_EXECUTION
2. THE stream SHALL subscribe to subject pattern agent.execute.*
3. THE consumer group SHALL be named agent-executor-workers
4. THE stream configuration SHALL be in platform/claims/intelligence-deepagents/nats-stream.yaml
5. THE stream SHALL be created before deploying the agent_executor claim

### Requirement 14

**User Story:** As a backend developer, I want ImagePullSecret configured for private registry access via ESO, so that Kubernetes can pull the agent_executor image without hardcoded credentials.

#### Acceptance Criteria

1. THE namespace SHALL contain an ImagePullSecret for ghcr.io registry
2. THE ImagePullSecret SHALL be named ghcr-pull-secret
3. THE deployment SHALL reference ghcr-pull-secret in imagePullSecrets field
4. THE ImagePullSecret SHALL be generated by ESO from AWS SSM parameters
5. THE ExternalSecret SHALL be in platform/claims/intelligence-deepagents/external-secrets/image-pull-secret-es.yaml

### Requirement 15 (REMOVED - Replaced by ApplicationSet Pattern)

**Note:** This requirement is obsolete. In the ApplicationSet + Tenant Registry pattern, the ArgoCD Application is generated automatically by the ApplicationSet in zerotouch-platform. The tenant config in zerotouch-tenants replaces the need for an Application manifest in the bizmatters repo.

### Requirement 16

**User Story:** As a backend developer, I want deployment triggered by Git commits, so that image updates follow GitOps principles.

#### Acceptance Criteria

1. WHEN the claim image field is updated THEN ArgoCD SHALL sync the change
2. WHEN ArgoCD syncs THEN Crossplane SHALL update the Deployment
3. WHEN the Deployment updates THEN Kubernetes SHALL perform rolling update
4. THE deployment process SHALL NOT use shell scripts
5. WHERE image updates are needed THEN developers SHALL edit the claim YAML and commit to Git

### Requirement 17

**User Story:** As a backend developer, I want health and metrics endpoints implemented, so that Kubernetes can monitor service health.

#### Acceptance Criteria

1. THE service SHALL expose a /health endpoint for liveness probes on port 8080
2. THE service SHALL expose a /ready endpoint for readiness probes on port 8080
3. THE /ready endpoint SHALL verify PostgreSQL, Dragonfly, and NATS connectivity
4. THE service SHALL expose a /metrics endpoint in Prometheus format on port 8080
5. THE metrics SHALL include NATS-specific counters (messages processed, failed, etc.)

### Requirement 18

**User Story:** As a backend developer, I want AWS SSM Parameter Store configured with application secrets, so that ESO can sync them to Kubernetes.

#### Acceptance Criteria

1. THE AWS SSM Parameter Store SHALL contain GitHub registry credentials at /zerotouch/prod/platform/ghcr/*
2. THE AWS SSM Parameter Store SHALL contain LLM API keys at /zerotouch/prod/agent-executor/openai_api_key and anthropic_api_key
3. THE parameters SHALL use SecureString type for sensitive values
4. THE ESO SHALL have IAM permissions to read these parameters
5. THE database credentials SHALL NOT be in AWS SSM (managed by Crossplane instead)

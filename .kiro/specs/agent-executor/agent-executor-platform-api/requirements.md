# Requirements Document: EventDrivenService Platform API

## Introduction

This specification defines the requirements for creating a reusable EventDrivenService platform API in the zerotouch-platform repository. The EventDrivenService API enables consumers to deploy event-driven services that process NATS messages with KEDA autoscaling.

This is a **platform-level specification** that defines the infrastructure machinery (XRD, Composition, NATS) without any application-specific logic. The platform is designed to be open-source and reusable by any consumer who wants to deploy event-driven services consuming from NATS JetStream.

## Glossary

- **EventDrivenService API**: A Crossplane XRD that defines how consumers can request event-driven service deployments
- **Platform Repository**: The public zerotouch-platform repository containing infrastructure definitions
- **Consumer**: Any developer or organization using the platform to deploy their services
- **XRD**: Crossplane Composite Resource Definition - defines the API contract
- **Composition**: Crossplane template that provisions Kubernetes resources based on XRD claims
- **NATS**: Lightweight messaging system for event-driven communication
- **JetStream**: NATS persistence layer for reliable message streaming
- **KEDA**: Kubernetes Event-Driven Autoscaling for scaling based on NATS queue depth
- **Init Container**: Kubernetes container that runs before main container starts
- **ImagePullSecrets**: Kubernetes secrets for authenticating to private container registries

## Requirements

### Requirement 1

**User Story:** As a platform engineer, I want NATS deployed with JetStream enabled in the foundation layer, so that consumers can use reliable message streaming for their services.

#### Acceptance Criteria

1. THE platform SHALL deploy NATS via an ArgoCD Application in bootstrap/components/01-nats.yaml
2. THE NATS deployment SHALL use the official NATS Helm chart from https://nats-io.github.io/k8s/helm/charts/
3. THE NATS deployment SHALL enable JetStream for persistent streaming
4. THE NATS server SHALL be deployed in a dedicated nats namespace
5. THE NATS deployment SHALL use sync-wave "0" to deploy before application layers

### Requirement 2

**User Story:** As a platform engineer, I want NATS stream configuration documented with industry standards, so that consumers know how to configure their streams.

#### Acceptance Criteria

1. THE platform documentation SHALL provide examples of NATS stream creation
2. THE documentation SHALL specify recommended stream naming patterns
3. THE documentation SHALL specify recommended consumer group naming patterns
4. THE documentation SHALL provide examples of subject patterns (e.g., "service.action.*")
5. THE documentation SHALL specify recommended retention policies (time-based, limits-based)

### Requirement 3

**User Story:** As a platform engineer, I want an EventDrivenService XRD defined in the 04-apis layer, so that consumers have a declarative API for deploying event-driven services.

#### Acceptance Criteria

1. THE XRD SHALL be defined at platform/04-apis/definitions/xeventdrivenservices.yaml
2. THE XRD SHALL use group platform.bizmatters.io with API version v1alpha1
3. THE XRD SHALL define kind XEventDrivenService for composite resources
4. THE XRD SHALL define kind EventDrivenService for namespace-scoped claims
5. THE XRD spec SHALL include fields: image, size, nats (url, stream, consumer), secretName, imagePullSecrets, initContainer (optional)

### Requirement 4

**User Story:** As a platform consumer, I want to specify resource size as small/medium/large, so that I can easily request appropriate resources without knowing Kubernetes details.

#### Acceptance Criteria

1. THE XRD SHALL define a size field with enum values: small, medium, large
2. THE size field SHALL default to medium if not specified
3. THE XRD SHALL document resource allocations for each size in the description
4. THE Composition SHALL map size values to CPU and memory limits
5. THE size mapping SHALL be consistent across all platform APIs

### Requirement 5

**User Story:** As a platform consumer, I want to reference a single secret containing all my service configuration, so that I can manage all environment variables in one place.

#### Acceptance Criteria

1. THE XRD SHALL define a secretName field (string) for referencing a Kubernetes secret
2. THE Composition SHALL mount this secret using envFrom to inject all keys as environment variables
3. THE XRD SHALL document that consumers should bundle all config (database URLs, API keys, etc.) into a single secret
4. THE platform documentation SHALL provide examples using ExternalSecrets Operator to sync from AWS SSM
5. WHERE secretName is not specified THEN the service SHALL run without secret injection

### Requirement 6

**User Story:** As a platform consumer, I want to use private container registries, so that I can deploy proprietary application code on the platform.

#### Acceptance Criteria

1. THE XRD SHALL define an imagePullSecrets field as an array of secret names
2. THE Composition SHALL configure imagePullSecrets in the Deployment spec
3. THE platform documentation SHALL provide examples of creating ImagePullSecrets
4. WHERE imagePullSecrets are not specified THEN the Deployment SHALL use default service account credentials
5. THE Composition SHALL support multiple imagePullSecrets for different registries

### Requirement 7

**User Story:** As a platform engineer, I want an EventDrivenService Composition that provisions all required resources, so that consumers get a complete deployment from a single claim.

#### Acceptance Criteria

1. THE Composition SHALL be defined at platform/04-apis/compositions/event-driven-service-composition.yaml
2. THE Composition SHALL create a Deployment with init container and main container
3. THE Composition SHALL create a Service exposing port 8080
4. THE Composition SHALL create a KEDA ScaledObject for autoscaling
5. THE Composition SHALL create a ServiceAccount for pod identity

### Requirement 8

**User Story:** As a platform consumer, I want an init container that runs database migrations, so that schema changes are applied automatically before my service starts.

#### Acceptance Criteria

1. THE XRD SHALL define an optional initContainer object with image and command fields
2. WHEN initContainer.image is not specified THEN the Composition SHALL use the main container image
3. WHEN initContainer.command is specified THEN the Composition SHALL create an init container with that command
4. THE init container SHALL have access to the same secret via envFrom
5. WHEN init container fails THEN the pod SHALL not start and SHALL report the error

### Requirement 9

**User Story:** As a platform consumer, I want the main container configured with environment variables from a secret, so that my application can access required services securely.

#### Acceptance Criteria

1. THE Composition SHALL mount the secret specified in secretName using envFrom
2. ALL keys in the referenced secret SHALL be available as environment variables
3. THE Composition SHALL set NATS_URL environment variable from the nats.url field in the claim spec
4. WHERE secretName is not provided THEN only NATS_URL SHALL be set
5. THE consumer SHALL be responsible for creating the secret with appropriate key names for their application

### Requirement 10

**User Story:** As a platform consumer, I want resource limits based on size parameter, so that my service gets appropriate CPU and memory allocation.

#### Acceptance Criteria

1. WHEN size is small THEN the Composition SHALL allocate 250m-1000m CPU and 512Mi-2Gi memory
2. WHEN size is medium THEN the Composition SHALL allocate 500m-2000m CPU and 1Gi-4Gi memory
3. WHEN size is large THEN the Composition SHALL allocate 1000m-4000m CPU and 2Gi-8Gi memory
4. THE Composition SHALL set both requests and limits for predictable scheduling
5. THE resource mappings SHALL be documented in the platform API documentation

### Requirement 11

**User Story:** As a platform consumer, I want KEDA autoscaling based on NATS queue depth, so that my service scales automatically with workload.

#### Acceptance Criteria

1. THE Composition SHALL create a KEDA ScaledObject resource
2. THE ScaledObject SHALL use NATS JetStream scaler type
3. THE ScaledObject SHALL scale up when queue depth exceeds 5 messages
4. THE ScaledObject SHALL scale down when queue depth is less than 1 message
5. THE ScaledObject SHALL support scaling from 1 to 10 replicas

### Requirement 12

**User Story:** As a platform consumer, I want KEDA to monitor a specific NATS stream and consumer group, so that scaling is based on my service's actual message backlog.

#### Acceptance Criteria

1. THE Composition SHALL configure KEDA to monitor a NATS stream specified by the consumer
2. THE Composition SHALL configure KEDA to monitor a consumer group specified by the consumer
3. THE XRD SHALL define nats.stream field for stream configuration
4. THE XRD SHALL define nats.consumer field for consumer group configuration
5. THE KEDA configuration SHALL use the nats.url from the claim spec

### Requirement 13

**User Story:** As a platform consumer, I want health and readiness probes configured, so that Kubernetes can manage my service lifecycle automatically.

#### Acceptance Criteria

1. THE Composition SHALL configure a liveness probe on /health endpoint
2. THE Composition SHALL configure a readiness probe on /ready endpoint
3. THE probes SHALL use HTTP GET on port 8080
4. THE liveness probe SHALL restart unhealthy pods
5. THE readiness probe SHALL prevent traffic to unready pods

### Requirement 14

**User Story:** As a platform engineer, I want the 04-apis layer enabled in ArgoCD, so that XRDs and Compositions are deployed to the cluster.

#### Acceptance Criteria

1. THE platform SHALL enable 04-apis layer by renaming platform/04-apis.yaml.disabled to platform/04-apis.yaml
2. THE 04-apis ArgoCD Application SHALL use sync-wave "1" to deploy after foundation
3. THE 04-apis Application SHALL sync from platform/04-apis directory
4. THE 04-apis Application SHALL use automated sync with prune and selfHeal
5. WHERE XRD or Composition changes are committed THEN ArgoCD SHALL sync automatically

### Requirement 15

**User Story:** As a platform engineer, I want platform naming and labeling conventions documented, so that all resources follow consistent standards.

#### Acceptance Criteria

1. THE Composition SHALL apply standard labels: app.kubernetes.io/name, app.kubernetes.io/component
2. THE Composition SHALL use consistent naming: {claim-name}-{resource-type}
3. THE platform documentation SHALL document required labels and naming patterns
4. THE Composition SHALL propagate labels from claim to all created resources
5. THE labels SHALL enable querying resources by standard selectors

### Requirement 16

**User Story:** As a platform engineer, I want namespace naming conventions documented, so that consumers create namespaces following platform standards.

#### Acceptance Criteria

1. THE platform SHALL document namespace naming convention at docs/standards/namespace-naming-convention.md
2. THE naming pattern SHALL be {layer}-{category} (e.g., intelligence-deepagents, services-api)
3. THE documentation SHALL specify required labels: layer and category
4. THE documentation SHALL provide examples for different use cases
5. THE documentation SHALL explain rationale and benefits of the convention

### Requirement 17

**User Story:** As a platform consumer, I want comprehensive API documentation, so that I can understand how to use the EventDrivenService API without reading implementation code.

#### Acceptance Criteria

1. THE platform SHALL provide API documentation at platform/04-apis/README.md
2. THE documentation SHALL include the complete XRD schema with field descriptions
3. THE documentation SHALL provide example claims for different use cases
4. THE documentation SHALL document required secrets and their expected structure
5. THE documentation SHALL include troubleshooting guidance for common issues

### Requirement 18

**User Story:** As a platform consumer, I want example NATS stream creation manifests, so that I can set up message streaming for my services.

#### Acceptance Criteria

1. THE platform documentation SHALL provide example NATS stream Job manifests
2. THE examples SHALL demonstrate different retention policies
3. THE examples SHALL demonstrate subject pattern configuration
4. THE examples SHALL demonstrate consumer group setup
5. THE examples SHALL include comments explaining each configuration option

# Requirements Document

## Introduction

This document specifies the requirements for Zero-Touch PostgreSQL Database Provisioning using Crossplane and CloudNative-PG (CNPG). The system enables developers to provision PostgreSQL databases without manual credential management - no SSM parameters, no ExternalSecrets, no human-known passwords. Developers simply create a claim with a name and `writeConnectionSecretToRef`, and the platform handles credential generation and delivery.

## Glossary

- **Crossplane**: Kubernetes-native infrastructure provisioning framework that extends Kubernetes with custom resource definitions (XRDs) and compositions
- **CNPG (CloudNative-PG)**: Kubernetes operator for managing PostgreSQL clusters
- **XRD (CompositeResourceDefinition)**: Crossplane schema defining the API for infrastructure claims
- **Composition**: Crossplane resource that defines how to fulfill an XRD claim by creating managed resources
- **Claim**: A namespaced Crossplane resource requesting infrastructure (e.g., PostgresInstance)
- **writeConnectionSecretToRef**: Crossplane field specifying where to write connection credentials
- **Zero-Touch**: Provisioning pattern where credentials are auto-generated and delivered without human intervention
- **App Namespace**: The Kubernetes namespace where the application workload runs
- **Infrastructure Namespace**: The namespace where CNPG clusters are deployed (e.g., `databases`)

## Requirements

### Requirement 1

**User Story:** As a developer, I want to provision a PostgreSQL database by creating a simple claim, so that I can get a working database without managing credentials manually.

#### Acceptance Criteria

1. WHEN a developer creates a PostgresInstance claim with `writeConnectionSecretToRef` THEN the Crossplane Composition SHALL create a CNPG Cluster with auto-generated credentials
2. WHEN the CNPG Cluster becomes ready THEN the Crossplane Composition SHALL copy the credentials to the secret specified in `writeConnectionSecretToRef`
3. WHEN a developer specifies only `metadata.name` and `writeConnectionSecretToRef` THEN the Crossplane Composition SHALL auto-derive the database name and owner from the claim name
4. WHEN the claim name contains hyphens THEN the Crossplane Composition SHALL convert hyphens to underscores for PostgreSQL-compatible database and owner names

### Requirement 2

**User Story:** As a developer, I want the connection secret to contain all necessary connection details, so that my application can connect to the database using standard environment variable patterns.

#### Acceptance Criteria

1. WHEN the connection secret is created THEN the secret SHALL contain keys: `endpoint`, `port`, `username`, `password`, and `database`
2. WHEN the endpoint is generated THEN the Crossplane Composition SHALL format it as `{cluster-name}-rw.{namespace}.svc.cluster.local`
3. WHEN the port is set THEN the Crossplane Composition SHALL use the standard PostgreSQL port `5432`
4. WHEN credentials are copied THEN the Crossplane Composition SHALL copy `username`, `password`, and `database` from the CNPG-generated `-app` secret

### Requirement 3

**User Story:** As a platform operator, I want the XRD to have a minimal API surface, so that developers cannot misconfigure database provisioning.

#### Acceptance Criteria

1. WHEN defining the XRD schema THEN the XRD SHALL require only `size` as a mandatory field in the spec
2. WHEN defining optional fields THEN the XRD SHALL support `version` (default: "16") and `storageGB` (default: 20) as optional parameters
3. WHEN a developer omits `databaseName` or `databaseOwner` THEN the Crossplane Composition SHALL auto-derive these values from the claim name
4. WHEN the XRD is applied THEN the XRD SHALL NOT include fields for `credentialsSecretName`, `databaseName`, or `databaseOwner`

### Requirement 4

**User Story:** As a platform operator, I want CNPG to auto-generate secure passwords, so that no human ever knows or handles database credentials.

#### Acceptance Criteria

1. WHEN the CNPG Cluster is bootstrapped THEN the Cluster SHALL NOT reference an external credentials secret
2. WHEN CNPG initializes the database THEN CNPG SHALL auto-generate a secure random password for the application user
3. WHEN CNPG creates the `-app` secret THEN the secret SHALL contain `username`, `password`, `dbname`, `host`, and `port` keys
4. WHEN the Composition copies credentials THEN the Composition SHALL read from the CNPG-generated `-app` secret in the same namespace as the cluster

### Requirement 5

**User Story:** As a developer, I want my application deployment to reference the connection secret, so that credentials are injected at runtime without hardcoding.

#### Acceptance Criteria

1. WHEN a deployment references the connection secret THEN the deployment SHALL use `secretKeyRef` to inject environment variables
2. WHEN the connection secret is updated THEN the deployment SHALL receive updated credentials on pod restart
3. WHEN the claim is deleted THEN the Crossplane Composition SHALL delete the connection secret

### Requirement 6

**User Story:** As a platform operator, I want to remove all SSM and ExternalSecret dependencies, so that the system is purely zero-touch.

#### Acceptance Criteria

1. WHEN implementing zero-touch provisioning THEN the Composition SHALL NOT create or reference ExternalSecret resources
2. WHEN implementing zero-touch provisioning THEN the Composition SHALL NOT reference AWS SSM parameters
3. WHEN migrating existing claims THEN the platform team SHALL remove ExternalSecret YAML files from the repository

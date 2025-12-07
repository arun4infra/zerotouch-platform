# Implementation Plan

- [x] 1. Update XRD to minimal API surface
  - [x] 1.1 Remove deprecated fields from XRD schema
    - Remove `databaseName`, `databaseOwner`, `credentialsSecretName`, `connectionSecretName` fields
    - Keep only `size` (required), `version` (optional, default "16"), `storageGB` (optional, default 20)
    - _Requirements: 3.1, 3.2, 3.4_
  - [ ]* 1.2 Write property test for XRD schema validation
    - **Property 3: Name Auto-Derivation** - Verify claim names transform correctly (hyphens → underscores)
    - **Validates: Requirements 1.3, 1.4, 3.3**

- [x] 2. Update Composition for zero-touch credential flow
  - [x] 2.1 Update CNPG Cluster resource in composition
    - Remove `spec.bootstrap.initdb.secret` reference (enables CNPG auto-generation)
    - Add patches to auto-derive `database` and `owner` from claim name with hyphen-to-underscore transform
    - Use `spec.claimRef.namespace` for cluster namespace (same-namespace pattern)
    - _Requirements: 1.1, 1.3, 1.4, 4.1_
  - [ ]* 2.2 Write property test for zero-touch credential generation
    - **Property 1: Zero-Touch Credential Generation** - Verify CNPG manifest has no `initdb.secret`
    - **Validates: Requirements 1.1, 4.1**
  - [x] 2.3 Update connection-secret resource in composition
    - Use Crossplane Object provider with `references` to copy from CNPG `-app` secret
    - Copy `username`, `password`, `dbname` from `{claim-name}-app` secret
    - Add computed `endpoint` field: `{claim-name}-rw.{namespace}.svc.cluster.local`
    - Set static `port` value: `5432`
    - Target secret name/namespace from `writeConnectionSecretToRef`
    - _Requirements: 1.2, 2.1, 2.2, 2.3, 2.4, 4.4_
  - [ ]* 2.4 Write property test for endpoint format
    - **Property 4: Endpoint Format** - Verify endpoint follows `{name}-rw.{namespace}.svc.cluster.local` pattern
    - **Validates: Requirements 2.2**

- [x] 3. Checkpoint - Validate composition changes
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Update example claims for zero-touch pattern
  - [x] 4.1 Update agent-executor-db claim
    - Remove `databaseName`, `databaseOwner`, `credentialsSecretName`, `connectionSecretName`
    - Add `writeConnectionSecretToRef` with target secret name and namespace
    - _Requirements: 1.1, 1.2_
  - [x] 4.2 Remove ExternalSecret resources
    - Delete `db-credentials-es.yaml` and any SSM-related ExternalSecrets
    - _Requirements: 6.1, 6.2, 6.3_

- [x] 5. Update documentation
  - [x] 5.1 Update POSTGRES.md with zero-touch usage
    - Document new claim format with `writeConnectionSecretToRef`
    - Document auto-derivation rules for database/owner names
    - Document connection secret format
    - Add migration guide from SSM-based pattern
    - _Requirements: 1.1, 1.2, 1.3, 2.1_

- [x] 6. Final Checkpoint - Validate end-to-end
  - Ensure all tests pass, ask the user if questions arise.

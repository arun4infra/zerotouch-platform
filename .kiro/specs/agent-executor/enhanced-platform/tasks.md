# Implementation Plan: EventDrivenService Platform API

This implementation plan converts the EventDrivenService design into actionable coding tasks. Each task builds incrementally, with testing integrated throughout to validate correctness early.

**Implementation Note (2025-12-08):** Tasks 3.1-3.10 were completed using a **simplified pre-defined secret slots approach** instead of the originally planned custom Crossplane function. This eliminates complexity and memory overhead while maintaining all core architectural principles.

---

## Task List

- [x] 0. Verify platform prerequisites
  - Check NATS is deployed and healthy in nats namespace
  - Verify JetStream is enabled on NATS
  - Check KEDA is installed and operational
  - Verify Crossplane is installed with kubernetes provider
  - Verify provider-kubernetes is configured
  - **Deliverable:** Platform foundation ready for EventDrivenService API

- [x] 1. Enable 04-apis layer in ArgoCD
  - Rename `platform/04-apis.yaml.disabled` to `platform/04-apis.yaml`
  - Configure ArgoCD Application with sync-wave "1"
  - Set automated sync with `prune: true` and `selfHeal: true`
  - Create `platform/04-apis/README.md` with layer overview
  - _Requirements: 14_

- [x] 1.1 Update bootstrap verification script for 04-apis layer
  - Update `scripts/bootstrap/12-verify-child-apps.sh`
  - Add `apis` to EXPECTED_APPS array
  - Verify script correctly detects the new Application
  - _Requirements: 14_

- [x] 2. Create XRD definition for EventDrivenService
  - Create file `platform/04-apis/definitions/xeventdrivenservices.yaml`
  - Define XRD with API group `platform.bizmatters.io` version `v1alpha1`
  - Set composite kind `XEventDrivenService` and claim kind `EventDrivenService`
  - Define complete OpenAPI v3 schema with all required fields
  - Include field descriptions and validation rules
  - _Requirements: 2, 3, 4, 5, 6, 7, 8_

- [x] 3. Implement Crossplane Composition
  - Create file `platform/04-apis/compositions/event-driven-service-composition.yaml`
  - Configure Composition to use Resources mode (standard patches only, no custom function)
  - Set compositeTypeRef to XEventDrivenService
  - Add providerConfigRef to all Object resources (kubernetes-provider)
  - **Implementation:** All subtasks 3.1-3.10 completed using pre-defined secret slots
  - **Approach:** Pre-defined secret slots (`secret1Name`, `secret2Name`, etc.) instead of dynamic arrays
  - **Secret Mounting:** envFrom (bulk mounting) for all secrets
  - **No Custom Function:** Eliminates complexity and memory overhead
  - _Requirements: 2_

- [x] 3.1 Implement ServiceAccount resource template
  - Create ServiceAccount resource in Composition
  - Patch name from claim metadata
  - Apply standard labels
  - _Requirements: 13, 15_

- [x] 3.2 Implement Deployment resource template
  - Create Deployment base manifest with replicas: 1
  - Configure pod template with security context (runAsNonRoot, runAsUser: 1000)
  - Set container security context (allowPrivilegeEscalation: false, drop ALL capabilities)
  - Configure seccompProfile: RuntimeDefault
  - Add image patch from spec.image
  - Add imagePullPolicy logic (Always if tag is latest)
  - Configure ServiceAccount reference
  - Apply standard labels
  - _Requirements: 3, 9, 15, 19_

- [x] 3.3 Add resource sizing patches to Deployment
  - Create size-to-resources transform patches
  - Map small: 250m-1000m CPU, 512Mi-2Gi memory
  - Map medium: 500m-2000m CPU, 1Gi-4Gi memory
  - Map large: 1000m-4000m CPU, 2Gi-8Gi memory
  - Set default to medium when size not specified
  - _Requirements: 4_

- [x] 3.4 Add NATS environment variable patches
  - Patch NATS_URL from spec.nats.url (default: nats://nats.nats.svc:4222)
  - Patch NATS_STREAM_NAME from spec.nats.stream
  - Patch NATS_CONSUMER_GROUP from spec.nats.consumer
  - _Requirements: 5_

- [x] 3.5 Add hybrid secret mounting logic
  - Implement envFrom patches for pre-defined secret slots (spec.secret1Name through spec.secret5Name)
  - Use conditional patches with `policy: {fromFieldPath: Optional}` to skip empty slots
  - All secrets mounted via envFrom (bulk mounting - all keys become environment variables)
  - _Requirements: 6_

- [x] 3.6 Add image pull secrets patches
  - Patch imagePullSecrets array from spec.imagePullSecrets
  - Handle empty array (use default service account credentials)
  - _Requirements: 7_

- [x] 3.7 Add optional init container logic
  - Create conditional init container patches
  - Use same image as main container (patched from spec.image)
  - Patch command from spec.initContainer.command
  - Patch args from spec.initContainer.args
  - Init container inherits same envFrom secret mounts as main container
  - Only created if spec.initContainer is specified (conditional patches)
  - _Requirements: 8_

- [x] 3.8 Add health and readiness probes
  - Configure liveness probe: HTTP GET /health:8080
  - Set liveness timing: initialDelaySeconds: 10, periodSeconds: 10, timeoutSeconds: 5, failureThreshold: 3
  - Configure readiness probe: HTTP GET /ready:8080
  - Set readiness timing: initialDelaySeconds: 5, periodSeconds: 5, timeoutSeconds: 3, failureThreshold: 2
  - _Requirements: 11_

- [x] 3.9 Implement Service resource template
  - Create Service with type ClusterIP
  - Expose port 8080 targeting container port 8080
  - Patch name from claim metadata
  - Configure selector labels matching Deployment
  - Apply standard labels
  - _Requirements: 10, 15_

- [x] 3.10 Implement KEDA ScaledObject resource template
  - Create ScaledObject base manifest
  - Set scaleTargetRef to Deployment name
  - Configure minReplicaCount: 1, maxReplicaCount: 10
  - Set trigger type: nats-jetstream
  - Configure natsServerMonitoringEndpoint: nats-headless.nats.svc.cluster.local:8222
  - Set account: $SYS
  - Patch stream from spec.nats.stream
  - Patch consumer from spec.nats.consumer
  - Set lagThreshold: 5
  - Patch name to {claim-name}-scaler
  - Apply standard labels
  - _Requirements: 12, 15_

- [x] 4. Create schema publication script
  - Create file `scripts/publish-schema.sh`
  - Extract OpenAPI v3 schema from XRD CRD
  - Write to `platform/04-apis/schemas/eventdrivenservice.schema.json`
  - Ensure JSON Schema Draft 2020-12 compatibility
  - Make script executable
  - _Requirements: 21_

- [ ] 5. Create claim validation script
  - Create file `scripts/validate-claim.sh`
  - Accept claim file path as argument
  - Validate claim against published JSON schema using ajv-cli
  - Output clear error messages for validation failures
  - Exit with appropriate status codes
  - Make script executable
  - _Requirements: 21_

- [x] 6. Create example claims
  - Create directory `platform/04-apis/examples/`
  - Create minimal-claim.yaml (image + NATS only, no secrets)
  - Create full-claim.yaml (image + NATS + database + cache + LLM keys + init container)
  - Create agent-executor-claim.yaml (reference implementation)
  - _Requirements: 16, 17_

- [x] 7. Write comprehensive API documentation
  - Update `platform/04-apis/README.md` with complete API documentation
  - Document XRD schema with field descriptions
  - Include all example claims (minimal, full, agent-executor)
  - Document hybrid secretRefs approach with Crossplane and ESO examples
  - Document migration path from direct manifests to EventDrivenService API
  - Include prerequisites, step-by-step migration instructions, and rollback procedure
  - Add IDE integration instructions (VSCode YAML extension)
  - _Requirements: 16, 18_

- [x] 7.1 Document error handling patterns
  - Add comprehensive troubleshooting section to README.md
  - Document ImagePullBackOff: wrong imagePullSecrets or missing secret
  - Document CreateContainerConfigError: secret not found, Crossplane claim not created yet
  - Document Init:CrashLoopBackOff: init container failure, missing env vars, database unreachable
  - Document KEDA TriggerError: wrong NATS endpoint (nats vs nats-headless), stream doesn't exist, consumer mismatch
  - Document Pending: resource quota exceeded, node capacity issues
  - Include diagnostic commands for each error type
  - Include resolution steps for each error type
  - _Requirements: 20_

- [x] 7.2 Update bootstrap sequence documentation
  - Update `scripts/bootstrap/BOOTSTRAP-SEQUENCE.md`
  - Document the 04-apis layer in platform layers section
  - Explain EventDrivenService API purpose and sync-wave ordering
  - Add to platform architecture overview
  - _Requirements: 14, 16_

- [x] 8. Create schema validation test suite
  - Create file `platform/04-apis/tests/schema-validation.test.sh`
  - Create test fixtures directory `platform/04-apis/tests/fixtures/`
  - Write test for valid minimal claim
  - Write test for valid full claim
  - Write test for invalid size value
  - Write test for missing required field (nats.stream)
  - Make test script executable
  - _Requirements: 21_

- [x] 9. Checkpoint 1: Validate XRD and schema publication
  - Run schema publication script to extract schema from XRD
  - Verify JSON schema file created at correct location
  - Run validation script against all example claims
  - Verify all valid examples pass validation
  - Verify invalid examples fail with clear error messages
  - **Deliverable:** Working schema validation with passing test suite

- [x] 10. Create basic composition verification script
  - Create file `platform/04-apis/tests/verify-composition.sh`
  - Script checks if Composition exists in cluster
  - Script validates Composition references correct XRD
  - Script lists all resource templates in Composition
  - Make script executable
  - _Requirements: 17_

- [x] 11. Checkpoint 2: Verify Composition structure
  - Apply XRD and Composition to cluster
  - Run composition verification script
  - Verify all 4 resource templates present (ServiceAccount, Deployment, Service, ScaledObject)
  - Verify Composition uses correct function (patch-and-transform)
  - **Deliverable:** Composition deployed and structurally validated

- [x] 11.1 Create EventDrivenService API verification script
  - Create file `scripts/bootstrap/15-verify-eventdrivenservice-api.sh`
  - Verify platform-apis Application exists and is synced
  - Verify EventDrivenService XRD (CRD) is installed
  - Verify event-driven-service Composition exists
  - Verify schema file published at platform/04-apis/schemas/
  - Make script executable
  - _Requirements: 14, 17, 21_

- [x] 12. Create minimal claim deployment test
  - Create test script `platform/04-apis/tests/test-minimal-deployment.sh`
  - Script applies minimal-claim.yaml to test namespace
  - Script waits for resources to be created (timeout 2 minutes)
  - Script verifies Deployment, Service, ServiceAccount, ScaledObject exist
  - Script extracts and validates resource configurations
  - Script cleans up test resources
  - Make script executable
  - _Requirements: 17_

- [x] 13. Checkpoint 3: Test minimal claim deployment
  - Run minimal claim deployment test
  - Verify all 4 resources created successfully
  - Verify Deployment has correct image
  - Verify Service exposes port 8080
  - Verify ScaledObject references correct Deployment
  - Verify resource labels applied correctly
  - **Deliverable:** Minimal EventDrivenService claim successfully provisions resources

- [x] 14. Create full claim deployment test
  - Create test script `platform/04-apis/tests/test-full-deployment.sh`
  - Script applies full-claim.yaml with all features (secrets, init container, size)
  - Script verifies resource sizing matches size specification
  - Script verifies secret mounts (both env and envFrom patterns)
  - Script verifies init container configuration
  - Script verifies imagePullSecrets configuration
  - Script cleans up test resources
  - Make script executable
  - _Requirements: 17_

- [x] 15. Checkpoint 4: Test full claim with all features
  - Run full claim deployment test
  - Verify resource requests/limits match size: medium
  - Verify all secretRefs mounted correctly (individual keys + envFrom)
  - Verify init container present with correct command/args
  - Verify imagePullSecrets configured
  - Verify NATS environment variables set correctly
  - **Deliverable:** Full-featured EventDrivenService claim works with all options

- [x] 16. Create KEDA configuration verification script
  - Create test script `platform/04-apis/tests/verify-keda-config.sh`
  - Script checks ScaledObject trigger configuration
  - Script verifies nats-headless endpoint used (not nats)
  - Script verifies stream and consumer names match claim
  - Script verifies lagThreshold, minReplicaCount, maxReplicaCount
  - Make script executable
  - _Requirements: 12, 17_

- [ ] 17. Checkpoint 5: Verify KEDA configuration
  - Run KEDA configuration verification script
  - Verify natsServerMonitoringEndpoint uses nats-headless.nats.svc.cluster.local:8222
  - Verify account set to $SYS
  - Verify lagThreshold: 5
  - Verify replica counts: min=1, max=10
  - **Deliverable:** KEDA ScaledObject correctly configured with proven settings

- [ ] 18. Create agent-executor migration test
  - Create test script `platform/04-apis/tests/test-agent-executor-migration.sh`
  - Script applies agent-executor-claim.yaml
  - Script compares generated resources to current direct manifests
  - Script validates image, resources, env vars, probes match
  - Script documents any differences with rationale
  - Make script executable
  - _Requirements: 17_

- [ ] 19. Checkpoint 6: Validate agent-executor migration
  - Run agent-executor migration test
  - Verify Deployment matches current configuration
  - Verify all secrets mounted correctly (db, cache, llm-keys)
  - Verify init container runs migrations
  - Verify KEDA uses nats-headless endpoint
  - Compare field-by-field with current manifests
  - **Note:** Actual migration of agent-executor (replacing direct manifests in bizmatters repo) is deferred until 2nd NATS service deployment (per ARCHITECTURE_DECISION.md)
  - **Deliverable:** Migration path validated and proven, ready when needed

- [ ] 19.1 Update agent-executor verification script (deferred)
  - Update `scripts/bootstrap/14-verify-agent-executor.sh`
  - Add EventDrivenService claim verification section
  - Verify claim exists and is Ready
  - Verify composed resources (4 expected: Deployment, Service, ScaledObject, ServiceAccount)
  - Make verification conditional (supports both direct manifests and EventDrivenService API)
  - **Note:** Only implement when agent-executor actually migrates to EventDrivenService API
  - _Requirements: 17, 18_

- [ ] 20. Create functional test script
  - Create test script `platform/04-apis/tests/test-functional.sh`
  - Script publishes test message to NATS stream
  - Script monitors pod logs for message processing
  - Script checks health and readiness endpoints
  - Script verifies message successfully processed
  - Make script executable
  - _Requirements: 17_

- [ ] 21. Checkpoint 7: Functional testing
  - Run functional test script
  - Verify pod processes NATS message successfully
  - Verify /health endpoint returns 200
  - Verify /ready endpoint returns 200
  - Check pod logs for successful message processing
  - **Deliverable:** Deployed service functionally processes messages

- [x] 22. Create autoscaling test script
  - Create test script `platform/04-apis/tests/test-autoscaling.sh`
  - Script publishes 50 test messages to NATS
  - Script monitors pod count over time
  - Script verifies scaling up occurs
  - Script waits for queue drain
  - Script verifies scaling down to minReplicaCount
  - Make script executable
  - _Requirements: 17_

- [x] 23. Checkpoint 8: KEDA autoscaling verification
  - Run autoscaling test script
  - Verify pods scale up from 1 to multiple replicas
  - Verify scaling responds to queue depth
  - Verify all messages processed successfully
  - Verify scale down after queue drains
  - **Deliverable:** KEDA autoscaling works correctly based on NATS queue depth

- [ ] 24. Create CI workflow for claim validation
  - Create file `.github/workflows/validate-claims.yml`
  - Configure workflow to run on pull requests
  - Install dependencies (ajv-cli, yq)
  - Run schema validation tests
  - Validate all example claims against schema
  - Fail build if validation errors occur
  - _Requirements: 21_

- [ ] 24.1 Add automated schema extraction to CI
  - Add schema extraction step to CI workflow
  - Trigger on changes to XRD files in platform/04-apis/definitions/
  - Run publish-schema.sh script
  - Verify schema file generated successfully
  - Commit updated schema to platform/04-apis/schemas/ (if changed)
  - Fail build if schema extraction fails
  - _Requirements: 21_

- [ ] 25. Final Checkpoint: Complete platform API validation
  - Run all test scripts in sequence
  - Verify schema validation passes
  - Verify composition structure correct
  - Verify minimal and full claims deploy successfully
  - Verify KEDA configuration correct
  - Verify agent-executor migration successful
  - Verify functional testing passes
  - Verify autoscaling works correctly
  - **Deliverable:** Fully validated EventDrivenService platform API ready for production use

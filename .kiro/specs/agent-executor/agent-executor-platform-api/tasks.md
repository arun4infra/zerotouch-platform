# Implementation Plan: AgentExecutor Platform API

## Overview

This implementation plan creates the AgentExecutor platform API in the zerotouch-platform repository. The plan is organized into **3 major checkpoints**, each representing a testable and verifiable milestone.

---

## CHECKPOINT 1: Deploy NATS with JetStream

**Goal:** Deploy NATS messaging infrastructure with JetStream enabled

**Verification Criteria:**
- [ ] NATS pods running in `nats` namespace
- [ ] JetStream enabled and accessible
- [ ] Can create test stream using nats CLI
- [ ] ArgoCD Application synced successfully

### Tasks

- [ ] 1.1 Create NATS ArgoCD Application
  - Create file: `bootstrap/components/01-nats.yaml`
  - Use NATS Helm chart from https://nats-io.github.io/k8s/helm/charts/
  - Set chart version to 1.1.5
  - Enable JetStream with memStorage (2Gi) and fileStorage (10Gi)
  - Configure resources: 250m-1000m CPU, 512Mi-2Gi memory
  - Set sync-wave annotation to "0"
  - Deploy to `nats` namespace with CreateNamespace=true
  - Enable automated sync with prune and selfHeal
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

- [ ] 1.2 Commit and verify NATS deployment
  - Commit `bootstrap/components/01-nats.yaml` to Git
  - Push to main branch
  - Wait for ArgoCD to sync (check ArgoCD UI or CLI)
  - Verify NATS Application appears in ArgoCD
  - Verify sync status is "Synced" and health is "Healthy"
  - _Requirements: 1.1_

- [ ] 1.3 Verify NATS pods are running
  - Run: `kubectl get pods -n nats`
  - Verify NATS StatefulSet pod is Running
  - Check pod logs for "Server is ready" message
  - Verify no error messages in logs
  - _Requirements: 1.3, 1.4_

- [ ] 1.4 Verify JetStream is enabled
  - Run: `kubectl exec -n nats nats-0 -- nats server info`
  - Verify JetStream is enabled in output
  - Verify memory and file storage are configured
  - Check storage limits match configuration (2Gi mem, 10Gi file)
  - _Requirements: 1.3_

- [ ] 1.5 Test NATS stream creation
  - Run: `kubectl exec -n nats nats-0 -- nats stream add TEST_STREAM --subjects "test.*" --retention limits --max-msgs=-1 --max-age=1h --storage file --replicas 1`
  - Verify stream created successfully
  - Run: `kubectl exec -n nats nats-0 -- nats stream list`
  - Verify TEST_STREAM appears in list
  - Delete test stream: `kubectl exec -n nats nats-0 -- nats stream rm TEST_STREAM -f`
  - _Requirements: 2.1, 2.2_

**CHECKPOINT 1 COMPLETE:** NATS infrastructure is deployed and functional

---

## CHECKPOINT 2: Create and Deploy AgentExecutor XRD and Composition

**Goal:** Define the AgentExecutor platform API and deploy it to the cluster

**Verification Criteria:**
- [ ] XRD installed in cluster (kubectl get xrd shows xagentexecutors.platform.bizmatters.io)
- [ ] Composition installed in cluster
- [ ] 04-apis layer enabled and synced in ArgoCD
- [ ] No sync errors in ArgoCD

### Tasks

- [ ] 2.1 Create AgentExecutor XRD definition
  - Create file: `platform/04-apis/definitions/xagentexecutors.yaml`
  - Define group: platform.bizmatters.io
  - Define API version: v1alpha1
  - Define composite kind: XAgentExecutor
  - Define claim kind: AgentExecutor
  - Add spec fields: image (required), size (enum: small/medium/large, default: medium)
  - Add spec fields: natsUrl (default: nats://nats.nats.svc:4222)
  - Add spec fields: natsStreamName (required), natsConsumerGroup (required)
  - Add spec fields: postgresConnectionSecret (default: postgres-connection)
  - Add spec fields: dragonflyConnectionSecret (default: dragonfly-connection)
  - Add spec fields: llmKeysSecret (default: llm-keys)
  - Add spec fields: imagePullSecrets (array of strings)
  - Add descriptions for all fields documenting their purpose and expected values
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 4.1, 4.2, 5.1, 5.2, 5.3, 5.4, 6.1_

- [ ] 2.2 Create AgentExecutor Composition - ServiceAccount
  - Create file: `platform/04-apis/compositions/agent-executor-composition.yaml`
  - Define Composition metadata with label: crossplane.io/xrd: xagentexecutors.platform.bizmatters.io
  - Set compositeTypeRef to XAgentExecutor
  - Add ServiceAccount resource using kubernetes.crossplane.io/v1alpha2 Object
  - Patch namespace from spec.claimRef.namespace
  - Patch name from metadata.name
  - _Requirements: 7.1, 7.5_

- [ ] 2.3 Create AgentExecutor Composition - Deployment
  - Add Deployment resource to composition
  - Configure init container: name "run-migrations", command ["/bin/sh", "-c", "scripts/ci/run-migrations.sh"]
  - Configure main container: name "agent-executor", port 8080
  - Add liveness probe: httpGet /health on port 8080, initialDelaySeconds 30, periodSeconds 10
  - Add readiness probe: httpGet /ready on port 8080, initialDelaySeconds 10, periodSeconds 5
  - Patch image from spec.image to both init and main containers
  - Patch namespace from spec.claimRef.namespace
  - Patch serviceAccountName from metadata.name
  - Add standard labels: app.kubernetes.io/name, app.kubernetes.io/component
  - _Requirements: 7.2, 8.1, 8.2, 8.3, 13.1, 13.2, 15.1_

- [ ] 2.4 Create AgentExecutor Composition - Environment Variables
  - Add environment variable patches for PostgreSQL: POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD
  - Source from secret specified in spec.postgresConnectionSecret
  - Add environment variable patches for Dragonfly: DRAGONFLY_HOST, DRAGONFLY_PORT, DRAGONFLY_PASSWORD
  - Source from secret specified in spec.dragonflyConnectionSecret
  - Add environment variable patches for LLM keys: OPENAI_API_KEY, ANTHROPIC_API_KEY
  - Source from secret specified in spec.llmKeysSecret
  - Add NATS_URL environment variable from spec.natsUrl
  - Apply same environment variables to init container
  - _Requirements: 8.4, 8.5, 9.1, 9.2, 9.3, 9.4, 9.5_

- [ ] 2.5 Create AgentExecutor Composition - Resource Limits
  - Add resource patches based on spec.size field
  - Map small → requests: 250m CPU, 512Mi memory; limits: 1000m CPU, 2Gi memory
  - Map medium → requests: 500m CPU, 1Gi memory; limits: 2000m CPU, 4Gi memory
  - Map large → requests: 1000m CPU, 2Gi memory; limits: 4000m CPU, 8Gi memory
  - Use transform type "map" for size-based mapping
  - _Requirements: 4.3, 4.4, 10.1, 10.2, 10.3, 10.4_

- [ ] 2.6 Create AgentExecutor Composition - ImagePullSecrets
  - Add imagePullSecrets patch from spec.imagePullSecrets
  - Transform to array format for Kubernetes Deployment spec
  - Apply to Deployment spec.template.spec.imagePullSecrets
  - _Requirements: 6.1, 6.2, 6.4, 6.5_

- [ ] 2.7 Create AgentExecutor Composition - Service
  - Add Service resource to composition
  - Configure type: ClusterIP, port: 8080, targetPort: 8080, protocol: TCP
  - Set selector to match Deployment labels (app: {claim-name})
  - Patch namespace from spec.claimRef.namespace
  - Patch name from metadata.name
  - _Requirements: 7.3_

- [ ] 2.8 Create AgentExecutor Composition - KEDA ScaledObject
  - Add KEDA ScaledObject resource to composition
  - Set scaleTargetRef to Deployment name
  - Configure minReplicaCount: 1, maxReplicaCount: 10
  - Add trigger type: nats-jetstream
  - Patch natsServerMonitoringEndpoint from spec.natsUrl
  - Patch stream from spec.natsStreamName
  - Patch consumer from spec.natsConsumerGroup
  - Set lagThreshold: "5" for scale-up
  - Patch namespace from spec.claimRef.namespace
  - _Requirements: 7.4, 11.1, 11.2, 11.3, 11.4, 11.5, 12.1, 12.2, 12.3, 12.4, 12.5_

- [ ] 2.9 Enable 04-apis layer in ArgoCD
  - Rename file: `platform/04-apis.yaml.disabled` → `platform/04-apis.yaml`
  - Verify file contains correct repoURL pointing to zerotouch-platform
  - Verify sync-wave is "1"
  - Verify path is platform/04-apis
  - Verify automated sync is enabled
  - _Requirements: 14.1, 14.2, 14.3, 14.4_

- [ ] 2.10 Commit and verify XRD/Composition deployment
  - Commit all files in platform/04-apis/ to Git
  - Commit renamed platform/04-apis.yaml to Git
  - Push to main branch
  - Wait for ArgoCD to sync (check ArgoCD UI)
  - Verify "apis" Application appears in ArgoCD
  - Verify sync status is "Synced"
  - _Requirements: 14.5_

- [ ] 2.11 Verify XRD is installed
  - Run: `kubectl get xrd`
  - Verify xagentexecutors.platform.bizmatters.io appears in list
  - Run: `kubectl get xrd xagentexecutors.platform.bizmatters.io -o yaml`
  - Verify all spec fields are present (image, size, natsUrl, etc.)
  - Verify claim kind is AgentExecutor
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [ ] 2.12 Verify Composition is installed
  - Run: `kubectl get composition`
  - Verify agent-executor-composition appears in list
  - Run: `kubectl get composition agent-executor-composition -o yaml`
  - Verify all resources are defined (ServiceAccount, Deployment, Service, ScaledObject)
  - Verify patches are configured correctly
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

**CHECKPOINT 2 COMPLETE:** AgentExecutor API is defined and deployed to cluster

---

## CHECKPOINT 3: Create Documentation and Test with Example Claim

**Goal:** Document the platform API and verify it works with a test claim

**Verification Criteria:**
- [ ] Platform API documentation exists and is comprehensive
- [ ] Namespace naming convention documented
- [ ] NATS stream configuration documented
- [ ] Test claim successfully provisions all resources
- [ ] Test claim cleanup works correctly

### Tasks

- [ ] 3.1 Create namespace naming convention documentation
  - Create file: `docs/standards/namespace-naming-convention.md`
  - Document pattern: {layer}-{category}
  - Provide examples: intelligence-deepagents, services-api, databases-primary
  - Document required labels: layer, category
  - Explain rationale: organizational clarity, resource grouping, RBAC boundaries
  - Provide decision tree for choosing layer and category
  - _Requirements: 16.1, 16.2, 16.3, 16.4, 16.5_

- [ ] 3.2 Create NATS stream configuration documentation
  - Create file: `docs/standards/nats-stream-configuration.md`
  - Document stream naming conventions (UPPERCASE_WITH_UNDERSCORES)
  - Document subject patterns (service.action.*, hierarchical)
  - Document consumer group naming (service-name-workers)
  - Provide retention policy examples (time-based, limits-based, interest-based)
  - Include example Job manifest for stream creation
  - Include example Job manifest for consumer creation
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 18.1, 18.2, 18.3, 18.4, 18.5_

- [ ] 3.3 Create AgentExecutor API documentation
  - Create file: `platform/04-apis/README.md`
  - Add overview section explaining what AgentExecutor API provides
  - Document complete XRD schema with all fields and descriptions
  - Add "Quick Start" section with minimal example claim
  - Add "Configuration Reference" section with all spec fields explained
  - Document size mappings (small/medium/large resource allocations)
  - Document required secrets structure for PostgreSQL, Dragonfly, LLM keys
  - Add "NATS Configuration" section explaining stream and consumer setup
  - Add "Private Registry" section explaining imagePullSecrets usage
  - Add "Troubleshooting" section with common issues and solutions
  - Include example claims for different scenarios (small service, large service, private registry)
  - _Requirements: 17.1, 17.2, 17.3, 17.4, 17.5_

- [ ] 3.4 Create test namespace for example claim
  - Create file: `platform/04-apis/examples/test-namespace.yaml`
  - Define namespace: agent-executor-test
  - Add labels: layer=testing, category=platform-validation
  - Add annotation explaining this is for testing the platform API
  - Commit and push to Git
  - Wait for ArgoCD sync
  - Verify namespace created: `kubectl get namespace agent-executor-test`
  - _Requirements: 16.1, 16.2, 16.3_

- [ ] 3.5 Create test secrets for example claim
  - Create file: `platform/04-apis/examples/test-secrets.yaml`
  - Create Secret: test-postgres-connection with keys: POSTGRES_HOST=postgres.databases.svc, POSTGRES_PORT=5432, POSTGRES_DB=testdb, POSTGRES_USER=testuser, POSTGRES_PASSWORD=testpass
  - Create Secret: test-dragonfly-connection with keys: DRAGONFLY_HOST=dragonfly.databases.svc, DRAGONFLY_PORT=6379, DRAGONFLY_PASSWORD=testpass
  - Create Secret: test-llm-keys with keys: OPENAI_API_KEY=sk-test, ANTHROPIC_API_KEY=sk-ant-test
  - Set namespace: agent-executor-test
  - Commit and push to Git
  - Wait for ArgoCD sync
  - Verify secrets created: `kubectl get secrets -n agent-executor-test`
  - _Requirements: 5.4, 5.5_

- [ ] 3.6 Create test NATS stream
  - Run: `kubectl exec -n nats nats-0 -- nats stream add TEST_AGENT_STREAM --subjects "test.agent.*" --retention limits --max-msgs=-1 --max-age=24h --storage file --replicas 1`
  - Verify stream created: `kubectl exec -n nats nats-0 -- nats stream info TEST_AGENT_STREAM`
  - Create consumer: `kubectl exec -n nats nats-0 -- nats consumer add TEST_AGENT_STREAM test-agent-workers --pull --deliver all --max-deliver=-1 --ack explicit --replay instant`
  - Verify consumer created: `kubectl exec -n nats nats-0 -- nats consumer info TEST_AGENT_STREAM test-agent-workers`
  - _Requirements: 2.1, 2.2, 2.3, 12.1, 12.2_

- [ ] 3.7 Create example AgentExecutor claim
  - Create file: `platform/04-apis/examples/test-claim.yaml`
  - Define AgentExecutor claim with name: test-agent-executor
  - Set namespace: agent-executor-test
  - Use public nginx image for testing: nginx:1.25-alpine
  - Set size: small
  - Set natsUrl: nats://nats.nats.svc:4222
  - Set natsStreamName: TEST_AGENT_STREAM
  - Set natsConsumerGroup: test-agent-workers
  - Set postgresConnectionSecret: test-postgres-connection
  - Set dragonflyConnectionSecret: test-dragonfly-connection
  - Set llmKeysSecret: test-llm-keys
  - Add comment explaining this is a test claim using nginx (not actual agent executor)
  - _Requirements: 3.5, 4.1, 5.1, 5.2, 5.3, 6.4, 12.3, 12.4, 12.5_

- [ ] 3.8 Deploy and verify test claim
  - Commit `platform/04-apis/examples/test-claim.yaml` to Git
  - Push to main branch
  - Wait for ArgoCD sync
  - Verify composite resource created: `kubectl get xagentexecutor`
  - Verify claim created: `kubectl get agentexecutor -n agent-executor-test`
  - Wait 30 seconds for Crossplane to reconcile
  - _Requirements: 7.1, 14.5_

- [ ] 3.9 Verify Deployment created by claim
  - Run: `kubectl get deployment -n agent-executor-test`
  - Verify test-agent-executor Deployment exists
  - Run: `kubectl get deployment test-agent-executor -n agent-executor-test -o yaml`
  - Verify init container "run-migrations" is configured
  - Verify main container "agent-executor" is configured with nginx image
  - Verify environment variables are set from secrets
  - Verify resource limits match "small" size (250m-1000m CPU, 512Mi-2Gi memory)
  - Verify serviceAccountName is set
  - Verify liveness and readiness probes are configured
  - _Requirements: 7.2, 8.1, 8.2, 8.3, 8.4, 9.1, 9.2, 9.3, 9.4, 9.5, 10.1, 13.1, 13.2_

- [ ] 3.10 Verify Service created by claim
  - Run: `kubectl get service -n agent-executor-test`
  - Verify test-agent-executor Service exists
  - Run: `kubectl get service test-agent-executor -n agent-executor-test -o yaml`
  - Verify type is ClusterIP
  - Verify port 8080 is exposed
  - Verify selector matches Deployment labels
  - _Requirements: 7.3_

- [ ] 3.11 Verify KEDA ScaledObject created by claim
  - Run: `kubectl get scaledobject -n agent-executor-test`
  - Verify test-agent-executor-scaler ScaledObject exists
  - Run: `kubectl get scaledobject test-agent-executor-scaler -n agent-executor-test -o yaml`
  - Verify scaleTargetRef points to test-agent-executor Deployment
  - Verify minReplicaCount is 1, maxReplicaCount is 10
  - Verify trigger type is nats-jetstream
  - Verify stream is TEST_AGENT_STREAM
  - Verify consumer is test-agent-workers
  - Verify lagThreshold is "5"
  - _Requirements: 7.4, 11.1, 11.2, 11.3, 11.4, 11.5, 12.1, 12.2, 12.3, 12.4, 12.5_

- [ ] 3.12 Verify ServiceAccount created by claim
  - Run: `kubectl get serviceaccount -n agent-executor-test`
  - Verify test-agent-executor ServiceAccount exists
  - _Requirements: 7.5_

- [ ] 3.13 Verify pod starts successfully (or fails as expected)
  - Run: `kubectl get pods -n agent-executor-test`
  - Note: Init container will fail because nginx doesn't have run-migrations.sh script
  - This is expected - we're testing resource provisioning, not actual service functionality
  - Verify pod exists and init container attempted to run
  - Check init container logs: `kubectl logs -n agent-executor-test <pod-name> -c run-migrations`
  - Verify error is about missing script (not about secrets or configuration)
  - _Requirements: 8.1, 8.5_

- [ ] 3.14 Test claim cleanup
  - Delete claim: `kubectl delete agentexecutor test-agent-executor -n agent-executor-test`
  - Wait 30 seconds for Crossplane to clean up
  - Verify Deployment deleted: `kubectl get deployment -n agent-executor-test` (should be empty)
  - Verify Service deleted: `kubectl get service -n agent-executor-test` (should be empty)
  - Verify ScaledObject deleted: `kubectl get scaledobject -n agent-executor-test` (should be empty)
  - Verify ServiceAccount deleted: `kubectl get serviceaccount -n agent-executor-test` (should be empty)
  - Verify composite resource deleted: `kubectl get xagentexecutor` (should not show test claim)
  - _Requirements: 7.1_

- [ ] 3.15 Cleanup test resources
  - Delete test NATS stream: `kubectl exec -n nats nats-0 -- nats stream rm TEST_AGENT_STREAM -f`
  - Delete test namespace: `kubectl delete namespace agent-executor-test`
  - Remove example files from Git (or keep them as examples with .example suffix)
  - Commit cleanup changes
  - _Requirements: N/A - cleanup_

**CHECKPOINT 3 COMPLETE:** Platform API is documented and verified working

---

## Final Verification

After completing all checkpoints, verify:

- [ ] NATS is running and JetStream is enabled
- [ ] AgentExecutor XRD is installed and accessible
- [ ] AgentExecutor Composition provisions all required resources
- [ ] Documentation is complete and accurate
- [ ] Test claim successfully provisions and cleans up resources
- [ ] Platform is ready for consumers to use

## Notes

- Each checkpoint must be completed and verified before moving to the next
- If any verification step fails, troubleshoot and fix before proceeding
- Keep test resources (examples/) in the repository as reference for consumers
- Update documentation if any issues or improvements are discovered during testing

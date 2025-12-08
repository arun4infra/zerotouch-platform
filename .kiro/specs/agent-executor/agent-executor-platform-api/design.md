# Design Document: EventDrivenService Platform API

## 1. Overview

This design document describes the architecture for creating a reusable EventDrivenService platform API in the zerotouch-platform repository. The API enables consumers to deploy event-driven services with NATS message consumption and KEDA autoscaling.

### 1.1 Design Goals

1. **Open-Source Reusability**: Platform can be used by any consumer for their event-driven services
2. **Clean Separation**: Platform defines "how to run" not "what to run"
3. **Self-Service**: Consumers deploy services by creating simple claim YAML files
4. **Declarative**: All infrastructure defined as Crossplane compositions
5. **Scalable**: KEDA autoscaling based on NATS queue depth

### 1.2 Architecture Principles

- **Provider-Consumer Model**: Platform provides capabilities, consumers provide workloads
- **API-First**: XRD defines clear contract between platform and consumers
- **Composable**: Consumers can mix and match platform APIs
- **Secure**: Support for private registries and secret management

## 2. System Architecture

### 2.1 High-Level Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Public Platform Repository                    │
│                   (zerotouch-platform - GitHub)                  │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         bootstrap/components/ (Sync Wave 0)               │  │
│  │  ┌─────────────┐  ┌──────────┐  ┌──────────────────┐    │  │
│  │  │ Crossplane  │  │   KEDA   │  │  External        │    │  │
│  │  │             │  │          │  │  Secrets         │    │  │
│  │  └─────────────┘  └──────────┘  │  Operator (ESO)  │    │  │
│  │                                  └──────────────────┘    │  │
│  │  ┌─────────────────────────────────────────────────┐    │  │
│  │  │ NATS (JetStream) - NEW                          │    │  │
│  │  │ - Namespace: nats                               │    │  │
│  │  │ - JetStream enabled                             │    │  │
│  │  └─────────────────────────────────────────────────┘    │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         platform/04-apis/ (Sync Wave 1) - NEW             │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │ XRD: XEventDrivenService                           │  │  │
│  │  │ - Group: platform.bizmatters.io                    │  │  │
│  │  │ - Claim: EventDrivenService                        │  │  │
│  │  │ - Fields: image, nats, secretName, initContainer  │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │ Composition: event-driven-service-composition      │  │  │
│  │  │ Creates:                                           │  │  │
│  │  │ - Deployment (init + main container)              │  │  │
│  │  │ - Service (port 8080)                             │  │  │
│  │  │ - KEDA ScaledObject                                │  │  │
│  │  │ - ServiceAccount                                   │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         docs/standards/ - NEW                             │  │
│  │  - namespace-naming-convention.md                         │  │
│  │  - nats-stream-configuration.md                           │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
                              │
                              │ Consumer Uses Platform API
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Private Consumer Repository                    │
│                    (bizmatters - Private GitHub)                 │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         platform/claims/intelligence-deepagents/          │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │ Claim: event-driven-service-claim.yaml             │  │  │
│  │  │ apiVersion: platform.bizmatters.io/v1alpha1        │  │  │
│  │  │ kind: EventDrivenService                           │  │  │
│  │  │ spec:                                              │  │  │
│  │  │   image: ghcr.io/private/my-service:v1.0.0        │  │  │
│  │  │   size: medium                                     │  │  │
│  │  │   nats:                                            │  │  │
│  │  │     stream: MY_STREAM                              │  │  │
│  │  │     consumer: my-workers                           │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
                              │
                              │ ArgoCD Syncs
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (Talos)                    │
│                                                                   │
│  Crossplane sees Claim → Provisions Resources                    │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ Deployment: my-service                                 │    │
│  │ Service: my-service                                    │    │
│  │ KEDA ScaledObject: my-service-scaler                   │    │
│  │ ServiceAccount: my-service                             │    │
│  └────────────────────────────────────────────────────────┘    │
└───────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow

#### 2.2.1 Platform Setup Flow (One-Time)
1. Platform engineer commits NATS deployment to bootstrap/components/
2. Platform engineer commits XRD and Composition to platform/04-apis/
3. Platform engineer enables 04-apis layer (rename .disabled file)
4. ArgoCD syncs and deploys NATS, XRD, Composition
5. Platform API is now available for consumers

#### 2.2.2 Consumer Deployment Flow
1. Consumer creates AgentExecutor claim in their private repo
2. Consumer commits claim to Git
3. ArgoCD (configured with private repo access) syncs claim
4. Crossplane sees claim and reconciles
5. Crossplane provisions Deployment, Service, KEDA ScaledObject, ServiceAccount
6. Kubernetes pulls private image using ImagePullSecrets
7. Service starts and begins processing NATS messages

## 3. Component Design

### 3.1 NATS Deployment

#### 3.1.1 ArgoCD Application
```yaml
# bootstrap/components/01-nats.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nats
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    chart: nats
    repoURL: https://nats-io.github.io/k8s/helm/charts/
    targetRevision: 1.1.5
    helm:
      values: |
        nats:
          jetstream:
            enabled: true
            memStorage:
              enabled: true
              size: 2Gi
            fileStorage:
              enabled: true
              size: 10Gi
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 2Gi
  destination:
    server: https://kubernetes.default.svc
    namespace: nats
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 3.2 EventDrivenService XRD

```yaml
# platform/04-apis/definitions/xeventdrivenservices.yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xeventdrivenservices.platform.bizmatters.io
spec:
  group: platform.bizmatters.io
  names:
    kind: XEventDrivenService
    plural: xeventdrivenservices
  claimNames:
    kind: EventDrivenService
    plural: eventdrivenservices
  versions:
    - name: v1alpha1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                image:
                  type: string
                  description: "Container image"
                size:
                  type: string
                  enum: [small, medium, large]
                  default: medium
                  description: "Resource size: small (250m-1000m CPU, 512Mi-2Gi RAM), medium (500m-2000m CPU, 1Gi-4Gi RAM), large (1000m-4000m CPU, 2Gi-8Gi RAM)"
                nats:
                  type: object
                  required:
                    - stream
                    - consumer
                  properties:
                    url:
                      type: string
                      default: "nats://nats.nats.svc:4222"
                      description: "NATS server URL"
                    stream:
                      type: string
                      description: "NATS JetStream stream name"
                    consumer:
                      type: string
                      description: "NATS consumer group name"
                scaling:
                  type: object
                  properties:
                    minReplicas:
                      type: integer
                      default: 1
                    maxReplicas:
                      type: integer
                      default: 10
                    lagThreshold:
                      type: string
                      default: "5"
                      description: "Queue lag threshold for scaling"
                secretName:
                  type: string
                  description: "Name of secret containing all environment variables (mounted via envFrom)"
                imagePullSecrets:
                  type: array
                  items:
                    type: object
                    properties:
                      name:
                        type: string
                  description: "List of secrets for pulling private images"
                initContainer:
                  type: object
                  description: "Optional init container for migrations or setup"
                  properties:
                    image:
                      type: string
                      description: "Init container image (defaults to main image if not specified)"
                    command:
                      type: array
                      items:
                        type: string
                      description: "Command to run in init container"
              required:
                - image
                - nats
```

### 3.3 AgentExecutor Composition

The composition creates four main resources:

#### 3.3.1 ServiceAccount
```yaml
- name: serviceaccount
  base:
    apiVersion: kubernetes.crossplane.io/v1alpha2
    kind: Object
    spec:
      forProvider:
        manifest:
          apiVersion: v1
          kind: ServiceAccount
          metadata:
            name: agent-executor
      providerConfigRef:
        name: kubernetes-provider
  patches:
    - fromFieldPath: "spec.claimRef.namespace"
      toFieldPath: "spec.forProvider.manifest.metadata.namespace"
    - fromFieldPath: "metadata.name"
      toFieldPath: "spec.forProvider.manifest.metadata.name"
```

#### 3.3.2 Deployment (with Init Container)
```yaml
- name: deployment
  base:
    apiVersion: kubernetes.crossplane.io/v1alpha2
    kind: Object
    spec:
      forProvider:
        manifest:
          apiVersion: apps/v1
          kind: Deployment
          metadata:
            name: agent-executor
          spec:
            replicas: 1
            selector:
              matchLabels:
                app: agent-executor
            template:
              metadata:
                labels:
                  app: agent-executor
              spec:
                serviceAccountName: agent-executor
                initContainers:
                  - name: run-migrations
                    image: placeholder
                    command: ["/bin/sh", "-c", "scripts/ci/run-migrations.sh"]
                    env: []  # Populated by patches
                containers:
                  - name: agent-executor
                    image: placeholder
                    ports:
                      - containerPort: 8080
                        name: http
                    env: []  # Populated by patches
                    livenessProbe:
                      httpGet:
                        path: /health
                        port: 8080
                      initialDelaySeconds: 30
                      periodSeconds: 10
                    readinessProbe:
                      httpGet:
                        path: /ready
                        port: 8080
                      initialDelaySeconds: 10
                      periodSeconds: 5
                    resources:
                      requests:
                        cpu: "500m"
                        memory: "1Gi"
                      limits:
                        cpu: "2000m"
                        memory: "4Gi"
      providerConfigRef:
        name: kubernetes-provider
  patches:
    # Namespace
    - fromFieldPath: "spec.claimRef.namespace"
      toFieldPath: "spec.forProvider.manifest.metadata.namespace"
    
    # Image
    - fromFieldPath: "spec.image"
      toFieldPath: "spec.forProvider.manifest.spec.template.spec.initContainers[0].image"
    - fromFieldPath: "spec.image"
      toFieldPath: "spec.forProvider.manifest.spec.template.spec.containers[0].image"
    
    # ImagePullSecrets
    - fromFieldPath: "spec.imagePullSecrets"
      toFieldPath: "spec.forProvider.manifest.spec.template.spec.imagePullSecrets"
      transforms:
        - type: convert
          convert:
            toType: array
    
    # Size-based resources
    - fromFieldPath: "spec.size"
      toFieldPath: "spec.forProvider.manifest.spec.template.spec.containers[0].resources.requests.cpu"
      transforms:
        - type: map
          map:
            small: "250m"
            medium: "500m"
            large: "1000m"
    
    # Environment variables (PostgreSQL)
    - type: FromCompositeFieldPath
      fromFieldPath: "spec.postgresConnectionSecret"
      toFieldPath: "spec.forProvider.manifest.spec.template.spec.containers[0].env[0]"
      transforms:
        - type: string
          string:
            fmt: |
              name: POSTGRES_HOST
              valueFrom:
                secretKeyRef:
                  name: %s
                  key: POSTGRES_HOST
    
    # ... (similar patches for all environment variables)
```

#### 3.3.3 Service
```yaml
- name: service
  base:
    apiVersion: kubernetes.crossplane.io/v1alpha2
    kind: Object
    spec:
      forProvider:
        manifest:
          apiVersion: v1
          kind: Service
          metadata:
            name: agent-executor
          spec:
            type: ClusterIP
            ports:
              - port: 8080
                targetPort: 8080
                protocol: TCP
                name: http
            selector:
              app: agent-executor
      providerConfigRef:
        name: kubernetes-provider
  patches:
    - fromFieldPath: "spec.claimRef.namespace"
      toFieldPath: "spec.forProvider.manifest.metadata.namespace"
```

#### 3.3.4 KEDA ScaledObject
```yaml
- name: scaledobject
  base:
    apiVersion: kubernetes.crossplane.io/v1alpha2
    kind: Object
    spec:
      forProvider:
        manifest:
          apiVersion: keda.sh/v1alpha1
          kind: ScaledObject
          metadata:
            name: agent-executor-scaler
          spec:
            scaleTargetRef:
              name: agent-executor
            minReplicaCount: 1
            maxReplicaCount: 10
            triggers:
              - type: nats-jetstream
                metadata:
                  natsServerMonitoringEndpoint: "nats://nats.nats.svc:4222"
                  stream: "PLACEHOLDER"
                  consumer: "PLACEHOLDER"
                  lagThreshold: "5"
      providerConfigRef:
        name: kubernetes-provider
  patches:
    - fromFieldPath: "spec.claimRef.namespace"
      toFieldPath: "spec.forProvider.manifest.metadata.namespace"
    - fromFieldPath: "spec.natsStreamName"
      toFieldPath: "spec.forProvider.manifest.spec.triggers[0].metadata.stream"
    - fromFieldPath: "spec.natsConsumerGroup"
      toFieldPath: "spec.forProvider.manifest.spec.triggers[0].metadata.consumer"
    - fromFieldPath: "spec.natsUrl"
      toFieldPath: "spec.forProvider.manifest.spec.triggers[0].metadata.natsServerMonitoringEndpoint"
```

### 3.4 Size-Based Resource Mapping

| Size   | CPU Request | CPU Limit | Memory Request | Memory Limit |
|--------|-------------|-----------|----------------|--------------|
| small  | 250m        | 1000m     | 512Mi          | 2Gi          |
| medium | 500m        | 2000m     | 1Gi            | 4Gi          |
| large  | 1000m       | 4000m     | 2Gi            | 8Gi          |

## 4. Documentation Structure

### 4.1 Platform API Documentation

**Location:** `platform/04-apis/README.md`

**Contents:**
- Overview of AgentExecutor API
- Complete XRD schema reference
- Example claims for different scenarios
- Required secrets structure
- NATS stream setup guide
- Troubleshooting guide

### 4.2 Namespace Naming Convention

**Location:** `docs/standards/namespace-naming-convention.md`

**Pattern:** `{layer}-{category}`

**Examples:**
- `intelligence-deepagents` - AI agent services
- `services-api` - API services
- `databases-primary` - Primary databases

**Required Labels:**
- `layer`: Top-level organizational layer
- `category`: Sub-category within layer

### 4.3 NATS Stream Configuration

**Location:** `docs/standards/nats-stream-configuration.md`

**Contents:**
- Stream naming conventions
- Subject pattern best practices
- Consumer group configuration
- Retention policy examples
- Example Job manifests for stream creation

## 5. Testing Strategy

### 5.1 Platform Validation

**Checkpoint 1: NATS Deployment**
- Verify NATS pods running in nats namespace
- Verify JetStream enabled
- Test stream creation with nats CLI

**Checkpoint 2: XRD and Composition Deployment**
- Verify XRD installed (kubectl get xrd)
- Verify Composition installed
- Verify 04-apis layer synced in ArgoCD

**Checkpoint 3: Example Claim Test**
- Create test claim with public nginx image
- Verify Deployment, Service, KEDA ScaledObject created
- Verify resources in correct namespace
- Delete claim and verify cleanup

## 6. Consumer Usage Example

```yaml
# Consumer creates this in their private repo
apiVersion: platform.bizmatters.io/v1alpha1
kind: EventDrivenService
metadata:
  name: my-service
  namespace: my-namespace
spec:
  image: ghcr.io/myorg/my-service:v1.0.0
  size: medium
  nats:
    url: nats://nats.nats.svc:4222
    stream: MY_SERVICE_STREAM
    consumer: my-service-workers
  scaling:
    minReplicas: 1
    maxReplicas: 10
    lagThreshold: "5"
  secretName: my-service-config  # Created by ExternalSecret
  imagePullSecrets:
    - name: ghcr-pull-secret
  initContainer:
    command: ["/bin/sh", "-c", "scripts/ci/run-migrations.sh"]
```

## 7. References

- **Crossplane Documentation**: https://docs.crossplane.io/
- **KEDA NATS Scaler**: https://keda.sh/docs/scalers/nats-jetstream/
- **NATS JetStream**: https://docs.nats.io/nats-concepts/jetstream

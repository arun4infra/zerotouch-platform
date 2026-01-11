# ZeroTouch Platform: ArgoCD Sync-Wave Installation Order

## Overview

The ZeroTouch Platform uses ArgoCD's sync-wave feature to orchestrate a carefully sequenced deployment of platform components. This document explains the current sync-wave order, the rationale behind each wave, and the dependencies that drive this sequencing.

## Pre-ArgoCD Bootstrap (Talos Inline Manifests)

Before ArgoCD is installed, the following components are deployed as Talos inline manifests during cluster bootstrap via `02-embed-network-manifests.sh`:

1. **Gateway API CRDs** (loaded first)
   - Embedded in Talos config as inline manifest
   - Must load BEFORE Cilium so Cilium detects Gateway API support
   - Version: v1.4.1 (synced with ArgoCD app)

2. **Cilium CNI** (loaded second)
   - Embedded in Talos config as inline manifest
   - Starts with Gateway API support enabled (CRDs already present)
   - ArgoCD later adopts and manages configuration updates

## Sync-Wave Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           ZEROTOUCH PLATFORM SYNC-WAVE FLOW                        │
└─────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────┐
│ WAVE -3: STORAGE FOUNDATION                                                        │
├─────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────────────────┐    │
│  │                    Local Path Provisioner                                  │    │
│  │                    • Dynamic PV Provisioning                               │    │
│  │                    • Local Storage Management                              │    │
│  │                    • Foundation for Persistent Workloads                  │    │
│  └─────────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ WAVE -1: NETWORK FOUNDATION                                                        │
├─────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────────────────┐    │
│  │                         Cilium CNI                                          │    │
│  │                         • Network Policy Engine                            │    │
│  │                         • Service Mesh Capabilities                        │    │
│  │                         • eBPF-based Networking                            │    │
│  │                         • Gateway API Support                              │    │
│  └─────────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ WAVE 0: SECRET MANAGEMENT FOUNDATION                                               │
├─────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────────────────┐    │
│  │                    External Secrets Operator                               │    │
│  │                   • Helm Chart: external-secrets                           │    │
│  │                   • Enables AWS SSM Parameter Store access                 │    │
│  │                   • Foundation for all platform secrets                    │    │
│  └─────────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ WAVE 1: CORE INFRASTRUCTURE PROVISIONING                                           │
├─────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────────────┐  │
│  │  Crossplane Operator│  │ AWS Parameter Store │  │   Provider Kubernetes       │  │
│  │  • Infrastructure   │  │ • ClusterSecretStore│  │   • Crossplane Provider     │  │
│  │    Provisioning     │  │ • Secret Sync Config│  │   • K8s Resource Management │  │
│  │  • XRD Foundation   │  │ • Enables ESO Access│  │   • Composition Support     │  │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────────────┘  │
│                                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────────┐    │
│  │                    ArgoCD Repository Registry Secret                        │    │
│  │                    • GitHub Container Registry Access                      │    │
│  │                    • Private Repository Authentication                     │    │
│  │                    • Enables Private Image Pulls                           │    │
│  └─────────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ WAVE 2: DATA LAYER INFRASTRUCTURE                                                  │
├─────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────┐    ┌─────────────────────────────────────────┐ │
│  │      CloudNativePG Operator     │    │      Observability Stack               │ │
│  │      • PostgreSQL Management    │    │      • Prometheus + Grafana            │ │
│  │      • Database Operator        │    │      • Currently DISABLED              │ │
│  │      • Backup & Recovery        │    │      • Monitoring Infrastructure       │ │
│  └─────────────────────────────────┘    └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ WAVE 3: FOUNDATION CONFIGURATION                                                   │
├─────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────────────────┐    │
│  │                     Foundation Configuration                                │    │
│  │                     • Platform RBAC Policies                               │    │
│  │                     • Network Configurations                               │    │
│  │                     • Shared Platform Resources                            │    │
│  │                     • Essential Platform Settings                          │    │
│  └─────────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ WAVE 4: PLATFORM SERVICES & SCALING                                                │
├─────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────────────┐  │
│  │   Kagent CRDs   │  │  Kagent Agent   │  │        KEDA Autoscaler              │  │
│  │   • AI Agent    │  │  • AI Platform  │  │        • Event-Driven Scaling       │  │
│  │     Definitions │  │  • LLM Services │  │        • Metrics-Based Autoscaling  │  │
│  │   • Custom APIs │  │  • Worker Nodes │  │        • ScaledObjects & ScaledJobs │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────────────────┘  │
│                                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────────┐    │
│  │              Gateway & DNS Config (MAIN ENVIRONMENT ONLY)                   │    │
│  │              • gateway-config: GatewayClass, Gateway, RBAC                 │    │
│  │              • dns-config: Hetzner ExternalSecrets for DNS                 │    │
│  │              • Requires Cilium with Gateway API support                    │    │
│  │              • Not deployed in preview environments (no Cilium)            │    │
│  └─────────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ WAVE 5: MESSAGING INFRASTRUCTURE                                                   │
├─────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────────────────┐    │
│  │                        NATS JetStream                                       │    │
│  │                        • Event Streaming Platform                          │    │
│  │                        • Persistent Message Storage                        │    │
│  │                        • AI Agent Communication Bus                        │    │
│  │                        • Inter-Service Messaging                           │    │
│  └─────────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ WAVE 6: PLATFORM APIs & APPLICATIONS                                               │
├─────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────────────┐  │
│  │  Platform APIs  │  │ Database Comps  │  │     Intelligence Services           │  │
│  │  • XRDs & Comps │  │ • PostgreSQL    │  │     • AI Application Workloads     │  │
│  │  • WebService   │  │   Compositions  │  │     • Qdrant Vector Database       │  │
│  │  • EventDriven  │  │ • Database      │  │     • Model Configurations         │  │
│  │    Service APIs │  │   Templates     │  │     • Agent Deployments            │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ WAVE 20: TENANT INFRASTRUCTURE                                                     │
├─────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────────────────┐    │
│  │                      Tenant Infrastructure                                  │    │
│  │                      • Tenant Namespace Creation                           │    │
│  │                      • Pre-Application Infrastructure                      │    │
│  │                      • Namespace-level RBAC                               │    │
│  │                      • Prepares for Tenant Applications                   │    │
│  └─────────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────┐
│ DEPLOYMENT CHARACTERISTICS                                                          │
├─────────────────────────────────────────────────────────────────────────────────────┤
│ • Sequential Waves: Each wave waits for previous wave to be healthy                 │
│ • Parallel Within Wave: Components in same wave deploy simultaneously               │
│ • Dependency-Driven: Order ensures all dependencies are satisfied                   │
│ • Retry Logic: Each component has configured retry and backoff strategies           │
│ • Health Checks: ArgoCD monitors sync and health status before proceeding           │
└─────────────────────────────────────────────────────────────────────────────────────┘
```
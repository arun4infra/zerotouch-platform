# Tenant Repository Setup

## What is a Tenant Repository?

A private Git repository that stores two types of information:

1. **Environment Configurations** - Server details needed to deploy Talos clusters
2. **Tenant Definitions** - Applications that should be deployed on the platform

## Why Separate from Platform Repository?

**Security:** Server IPs, passwords, and credentials never stored in the public platform repository.

**Separation:** Platform code (public) stays generic while infrastructure details (private) remain secure.

**Multi-tenancy:** Multiple tenant applications can be added without modifying platform code.

## Repository Structure

The tenant repository needs three main directories:

### environments/

Contains server configurations for each environment (dev, staging, production).

Each environment has a file describing:
- Control plane server IP and credentials
- Worker node IPs and credentials
- Cluster networking configuration
- Talos and Kubernetes versions

Bootstrap scripts automatically fetch these configurations and use them to install Talos on your servers.

### repositories/

Contains ExternalSecret definitions for accessing private tenant repositories.

These are Kubernetes manifests that tell the platform how to fetch credentials from AWS SSM Parameter Store. The actual credentials (GitHub tokens, passwords) are stored in AWS SSM, not in Git.

### tenants/

Contains definitions for each tenant application.

Each tenant has a simple configuration file that tells ArgoCD:
- Which Git repository contains the application
- Which branch to deploy from
- Where in the repository the Kubernetes manifests are located
- Which namespace to deploy into

## How It Works

### Environment Configurations

When you run bootstrap scripts, they:
1. Connect to your tenant repository using GitHub credentials
2. Fetch the environment configuration file
3. Read server IPs and other details
4. Use this information to install Talos and Kubernetes
5. Generate rescue passwords and commit them back to the repository

### Tenant Applications

After the platform is deployed, ArgoCD:
1. Watches your tenant repository for changes
2. Discovers all tenant definitions in the tenants/ directory
3. Creates an ArgoCD Application for each tenant
4. Syncs the tenant's Kubernetes manifests from their repository
5. Automatically deploys and manages the tenant applications

## Security Model

**Tenant Repository:** Private repository containing references and configurations, but not actual secrets.

**AWS SSM Parameter Store:** Stores actual credentials (API keys, GitHub tokens, passwords) encrypted at rest.

**ExternalSecrets Operator:** Syncs credentials from AWS SSM into Kubernetes secrets automatically.

**Git Commits:** Only configuration files and ExternalSecret manifests are committed to Git, never plaintext secrets.

## Getting Started

To use this pattern:

1. Create a new private Git repository
2. Set up the three directories (environments, repositories, tenants)
3. Add environment configurations with your server details
4. Configure platform repository to access your tenant repository
5. Run bootstrap scripts to deploy your cluster

The platform will automatically fetch configurations, deploy infrastructure, and manage tenant applications through GitOps.

## References

- [Deployment Modes](DEPLOYMENT-MODES.md) - Production vs Preview modes
- [Bootstrap Scripts](../scripts/bootstrap/README.md) - How to run bootstrap

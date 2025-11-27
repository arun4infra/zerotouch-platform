# Intelligence Layer - Documentation Automation

This Crossplane Configuration provides the Intelligence Layer for Agentic-Native Infrastructure, enabling automated documentation maintenance via AI agents.

## Components

| Component | Purpose | Technology |
|:----------|:--------|:-----------|
| **Qdrant** | Vector database for semantic search | StatefulSet |
| **docs-mcp** | MCP tool server for documentation operations | Deployment + KEDA |
| **Librarian Agent** | Kagent agent maintaining documentation | Kagent Agent CRD |

## Architecture

The Intelligence Layer implements a two-zone documentation strategy:

- **`docs/`** - Human-maintained, free-form content (not indexed)
- **`artifacts/`** - Agent-maintained, structured content (indexed in Qdrant)

The Librarian Agent:
1. Monitors PRs for changes to `platform/` compositions
2. Automatically creates/updates Twin Docs in `artifacts/specs/`
3. Distills human notes from `docs/` into structured runbooks in `artifacts/runbooks/`
4. Validates all content before committing (No-Fluff policy: tables/lists only)

## Deployment

### Prerequisites

- Crossplane >=v1.14.1
- Kagent installed in cluster
- External Secrets Operator (for GitHub token)

### Install

```bash
# Build package
make build

# Install to cluster
kubectl crossplane install configuration ghcr.io/bizmatters/intelligence-layer:latest
```

### Configuration

1. Create GitHub bot token secret:
```bash
kubectl create secret generic github-bot-token \
  --from-literal=token=<YOUR_TOKEN> \
  -n intelligence
```

2. Apply example configuration:
```bash
kubectl apply -f examples/intelligence-example.yaml
```

## Development

```bash
# Add upbound/build submodule
git submodule add https://github.com/upbound/build.git build
git submodule update --init --recursive

# Build package locally
make build

# Run E2E tests
make e2e-intelligence
```

## Documentation

- [Requirements](../../../.kiro/specs/intelligence-layer/requirements.md)
- [Design](../../../.kiro/specs/intelligence-layer/design.md)
- [Tasks](../../../.kiro/specs/intelligence-layer/tasks.md)

## License

Apache 2.0

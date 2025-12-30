## Create ./scripts/ci/in-cluster-test.sh

```bash
#!/bin/bash
set -euo pipefail

# ==============================================================================
# Service CI Entry Point for ide-orchestrator
# ==============================================================================
# Purpose: Standardized entry point for platform-based CI testing
# Usage: ./scripts/ci/in-cluster-test.sh
# ==============================================================================

# Get platform branch from service config
if [[ -f "ci/config.yaml" ]]; then
    if command -v yq &> /dev/null; then
        PLATFORM_BRANCH=$(yq eval '.platform.branch // "main"' ci/config.yaml)
    else
        PLATFORM_BRANCH="main"
    fi
else
    PLATFORM_BRANCH="main"
fi

# Always ensure fresh platform checkout
if [[ -d "zerotouch-platform" ]]; then
    echo "Removing existing platform checkout for fresh clone..."
    rm -rf zerotouch-platform
fi

echo "Cloning fresh zerotouch-platform repository (branch: $PLATFORM_BRANCH)..."
git clone -b "$PLATFORM_BRANCH" https://github.com/arun4infra/zerotouch-platform.git zerotouch-platform

# Run platform script
./zerotouch-platform/scripts/bootstrap/preview/tenants/in-cluster-test.sh

```

## Update .env file

```bash
# AWS Credentials (dummy values for local preview mode)
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
BOT_GITHUB_USERNAME=
BOT_GITHUB_TOKEN=
TENANTS_REPO_NAME=zerotouch-tenants
ANTHROPIC_API_KEY=12345567
AWS_ROLE_ARN=
```

## Run below command

```bash
export CLEANUP_CLUSTER=false && export $(grep -v '^#' .env | grep -v '^$' | xargs) && ./scripts/ci/in-cluster-test.sh
```

## Example - IN-Cluster Testing single test locally

```bash
kubectl run integration-test-manual --image=ide-orchestrator:ci-test --rm -i --restart=Never -n intelligence-orchestrator --overrides='
{
  "spec": {
    "containers": [
      {
        "name": "integration-test-manual",
        "image": "ide-orchestrator:ci-test",
        "command": ["python", "-m", "pytest", "tests/integration/test_workflow_integration.py::test_complete_workflow_lifecycle", "-v"],
        "env": [
          {"name": "POSTGRES_HOST", "value": "ide-orchestrator-db-rw.intelligence-orchestrator.svc.cluster.local"},
          {"name": "POSTGRES_PORT", "value": "5432"},
          {"name": "POSTGRES_USER", "value": "ide-orchestrator-db"},
          {"name": "POSTGRES_PASSWORD", "value": "0KNzcnnKO1NlJgSrdCX3ORbybFFMrd2TuUGr8kkTsQjrdogAv908QuOgZb7T5Zmy"},
          {"name": "POSTGRES_DB", "value": "ide-orchestrator-db"},
          {"name": "JWT_SECRET", "value": "test-secret-key-for-testing"},
          {"name": "REDIS_URL", "value": "redis://redis:6379"},
          {"name": "API_BASE_URL", "value": "http://ide-orchestrator:8000"}
        ]
      }
    ]
  }
}'
```

## Example - IN-Cluster Testing all tests locally

```bash
kubectl run integration-test-all --image=ide-orchestrator:ci-test --rm -i --restart=Never -n intelligence-orchestrator --overrides='
{
  "spec": {
    "containers": [
      {
        "name": "integration-test-all",
        "image": "ide-orchestrator:ci-test",
        "command": ["python", "-m", "pytest", "tests/integration/", "-v"],
        "env": [
          {"name": "POSTGRES_HOST", "value": "ide-orchestrator-db-rw.intelligence-orchestrator.svc.cluster.local"},
          {"name": "POSTGRES_PORT", "value": "5432"},
          {"name": "POSTGRES_USER", "value": "ide-orchestrator-db"},
          {"name": "POSTGRES_PASSWORD", "value": "0KNzcnnKO1NlJgSrdCX3ORbybFFMrd2TuUGr8kkTsQjrdogAv908QuOgZb7T5Zmy"},
          {"name": "POSTGRES_DB", "value": "ide-orchestrator-db"},
          {"name": "JWT_SECRET", "value": "test-secret-key-for-testing"},
          {"name": "REDIS_URL", "value": "redis://redis:6379"},
          {"name": "API_BASE_URL", "value": "http://ide-orchestrator:8000"}
        ]
      }
    ]
  }
}'
```

```bash
kubectl run integration-test-lifecycle --image=ide-orchestrator:ci-test --rm -i --restart=Never -n intelligence-orchestrator --overrides='{"spec":{"containers":[{"name":"integration-test-lifecycle","image":"ide-orchestrator:ci-test","command":["bash","-c","cd /app && python -m pytest tests/integration/test_refinement_lifecycle.py::test_refinement_approved_lifecycle -v"],"env":[{"name":"POSTGRES_HOST","value":"ide-orchestrator-db-rw.intelligence-orchestrator.svc.cluster.local"},{"name":"POSTGRES_PORT","value":"5432"},{"name":"POSTGRES_USER","value":"ide-orchestrator-db"},{"name":"POSTGRES_PASSWORD","value":"0KNzcnnKO1NlJgSrdCX3ORbybFFMrd2TuUGr8kkTsQjrdogAv908QuOgZb7T5Zmy"},{"name":"POSTGRES_DB","value":"ide-orchestrator-db"},{"name":"JWT_SECRET","value":"test-secret-key-for-integration-tests"}]}]}}'
```

## After fix a test case bug, build and load to local cluster for testing else your changes will not get reflected in cluster
```bash
docker build -t ide-orchestrator:ci-test ide-orchestrator/ && kind load docker-image ide-orchestrator:ci-test --name zerotouch-preview
```

## Occassionally you might need to delete the pod and restart after loading the image
```bash
kubectl rollout restart deployment ide-orchestrator -n intelligence-orchestrator
```
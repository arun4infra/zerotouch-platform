# Bootstrap Helper Scripts

## Tenant Configuration Management

### fetch-tenant-config.sh

Fetches environment configuration from the private `zerotouch-tenants` repository.

**Usage:**
```bash
source ./helpers/fetch-tenant-config.sh <ENV> [--use-cache]
# Sets: TENANT_CONFIG_FILE, TENANT_CACHE_DIR
```

**Features:**
- Reads credentials from `.env.ssm`
- Uses sparse checkout (only `environments/` folder)
- Caches to `.tenants-cache/`
- Force pulls latest by default
- `--use-cache` flag skips fetch if cache exists

**Example:**
```bash
source ./helpers/fetch-tenant-config.sh dev
echo "Config file: $TENANT_CONFIG_FILE"
```

### parse-tenant-config.sh

Fetches and parses tenant configuration, exporting variables for bootstrap scripts.

**Usage:**
```bash
source ./helpers/parse-tenant-config.sh <ENV>
# Sets: SERVER_IP, ROOT_PASSWORD, WORKER_NODES, WORKER_PASSWORD
```

**Features:**
- Calls `fetch-tenant-config.sh` internally
- Parses YAML using Python
- Exports all necessary variables for bootstrap
- Formats worker nodes as comma-separated list

**Example:**
```bash
source ./helpers/parse-tenant-config.sh dev
echo "Control Plane: $SERVER_IP"
echo "Workers: $WORKER_NODES"
```

### update-tenant-config.sh

Commits and pushes changes back to the tenant repository.

**Usage:**
```bash
./helpers/update-tenant-config.sh <FILE_PATH> [COMMIT_MESSAGE]
```

**Features:**
- Validates file is in cache directory
- Auto-commits and pushes to `main` branch
- Sets git user as "ZeroTouch Bootstrap"

**Example:**
```bash
# After modifying a config file
./helpers/update-tenant-config.sh "$TENANT_CONFIG_FILE" "Update rescue passwords"
```

## Configuration

Tenant repository credentials are read from `.env.ssm`:

```
/zerotouch/prod/argocd/repos/zerotouch-tenants/url=https://github.com/org/zerotouch-tenants.git
/zerotouch/prod/argocd/repos/zerotouch-tenants/username=username
/zerotouch/prod/argocd/repos/zerotouch-tenants/password=token
```

## Cache Location

Tenant configs are cached at: `zerotouch-platform/.tenants-cache/`

This directory is gitignored and should not be committed.

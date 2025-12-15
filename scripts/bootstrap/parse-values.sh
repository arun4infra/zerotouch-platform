#!/bin/bash
# Helper script to parse talos-values.yaml

ENV="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fetch tenant configuration
source "$SCRIPT_DIR/helpers/fetch-tenant-config.sh" "$ENV" --use-cache
VALUES_FILE="$TENANT_CONFIG_FILE"

if [ ! -f "$VALUES_FILE" ]; then
    echo "ERROR: $VALUES_FILE not found" >&2
    exit 1
fi

# Use Python to parse YAML reliably
python3 - <<EOF
import yaml
import sys

with open('$VALUES_FILE', 'r') as f:
    data = yaml.safe_load(f)

cp = data['controlplane']
workers = data.get('workers', [])

print(f"{cp['ip']}")
print(f"{cp['rescue_password']}")

if workers:
    w = workers[0]
    print(f"{w['name']}")
    print(f"{w['ip']}")
    print(f"{w['rescue_password']}")
EOF

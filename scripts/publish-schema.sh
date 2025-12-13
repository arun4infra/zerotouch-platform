#!/usr/bin/env bash

# publish-schema.sh
# Extracts OpenAPI v3 schema from EventDrivenService XRD and publishes as JSON Schema

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Paths
XRD_FILE="${PROJECT_ROOT}/platform/04-apis/definitions/xeventdrivenservices.yaml"
SCHEMA_DIR="${PROJECT_ROOT}/platform/04-apis/schemas"
SCHEMA_FILE="${SCHEMA_DIR}/eventdrivenservice.schema.json"

echo "=================================================="
echo "EventDrivenService Schema Publication"
echo "=================================================="
echo ""

# Check if XRD file exists
if [[ ! -f "${XRD_FILE}" ]]; then
    echo -e "${RED}ERROR: XRD file not found at ${XRD_FILE}${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found XRD file: ${XRD_FILE}"

# Check for required tools
if ! command -v yq &> /dev/null; then
    echo -e "${RED}ERROR: yq is not installed${NC}"
    echo "Install with: brew install yq (macOS) or see https://github.com/mikefarah/yq"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found yq: $(yq --version)"

# Create schemas directory if it doesn't exist
mkdir -p "${SCHEMA_DIR}"
echo -e "${GREEN}✓${NC} Schema directory ready: ${SCHEMA_DIR}"

# Extract the OpenAPI v3 schema from the XRD
echo ""
echo "Extracting schema from XRD..."

# Extract the spec.properties from the openAPIV3Schema
OPENAPI_SCHEMA=$(yq eval '.spec.versions[0].schema.openAPIV3Schema.properties.spec' "${XRD_FILE}" -o=json)

if [[ -z "${OPENAPI_SCHEMA}" ]] || [[ "${OPENAPI_SCHEMA}" == "null" ]]; then
    echo -e "${RED}ERROR: Failed to extract schema from XRD${NC}"
    exit 1
fi

# Build JSON Schema Draft 2020-12 compliant schema
cat > "${SCHEMA_FILE}" <<EOF
{
  "\$schema": "https://json-schema.org/draft/2020-12/schema",
  "\$id": "https://platform.bizmatters.io/schemas/eventdrivenservice.schema.json",
  "title": "EventDrivenService",
  "description": "Schema for EventDrivenService API - deploys NATS JetStream consumer services with KEDA autoscaling",
  "type": "object",
  "required": ["apiVersion", "kind", "metadata", "spec"],
  "properties": {
    "apiVersion": {
      "type": "string",
      "const": "platform.bizmatters.io/v1alpha1",
      "description": "API version for EventDrivenService"
    },
    "kind": {
      "type": "string",
      "const": "EventDrivenService",
      "description": "Resource kind"
    },
    "metadata": {
      "type": "object",
      "required": ["name"],
      "properties": {
        "name": {
          "type": "string",
          "pattern": "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$",
          "minLength": 1,
          "maxLength": 253,
          "description": "Name of the EventDrivenService resource"
        },
        "namespace": {
          "type": "string",
          "pattern": "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$",
          "minLength": 1,
          "maxLength": 63,
          "description": "Namespace for the EventDrivenService resource"
        },
        "labels": {
          "type": "object",
          "additionalProperties": {
            "type": "string"
          },
          "description": "Labels to apply to the resource"
        },
        "annotations": {
          "type": "object",
          "additionalProperties": {
            "type": "string"
          },
          "description": "Annotations to apply to the resource"
        }
      }
    },
    "spec": ${OPENAPI_SCHEMA}
  }
}
EOF

if [[ $? -ne 0 ]]; then
    echo -e "${RED}ERROR: Failed to write schema file${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Schema extracted successfully"

# Validate the generated JSON
if ! jq empty "${SCHEMA_FILE}" 2>/dev/null; then
    echo -e "${RED}ERROR: Generated schema is not valid JSON${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Schema is valid JSON"

# Pretty-print the schema
jq . "${SCHEMA_FILE}" > "${SCHEMA_FILE}.tmp" && mv "${SCHEMA_FILE}.tmp" "${SCHEMA_FILE}"

echo ""
echo "=================================================="
echo -e "${GREEN}✓ Schema published successfully${NC}"
echo "=================================================="
echo ""
echo "Schema location: ${SCHEMA_FILE}"
echo ""
echo "Schema details:"
jq '{
  "$schema": ."$schema",
  "$id": ."$id",
  "title": .title,
  "required_fields": .properties.spec.required,
  "optional_fields": [.properties.spec.properties | keys[] | select(. as $k | .properties.spec.required | index($k) | not)]
}' "${SCHEMA_FILE}" 2>/dev/null || echo "  (use jq to inspect schema)"

echo ""
echo "Usage:"
echo "  Validate a claim: scripts/validate-claim.sh <claim-file>"
echo ""

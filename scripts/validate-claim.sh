#!/usr/bin/env bash

# validate-claim.sh
# Validates EventDrivenService claim files against the published JSON schema

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Paths
SCHEMA_FILE="${PROJECT_ROOT}/platform/04-apis/schemas/eventdrivenservice.schema.json"

# Usage function
usage() {
    cat <<EOF
Usage: $(basename "$0") <claim-file>

Validates an EventDrivenService claim file against the published JSON schema.

Arguments:
  claim-file    Path to the YAML claim file to validate

Examples:
  $(basename "$0") platform/04-apis/examples/minimal-claim.yaml
  $(basename "$0") platform/04-apis/examples/full-claim.yaml

Exit codes:
  0 - Validation successful
  1 - Validation failed (schema errors)
  2 - Missing dependencies or file not found
  3 - Invalid usage

EOF
    exit 3
}

# Check arguments
if [[ $# -eq 0 ]]; then
    echo -e "${RED}ERROR: No claim file specified${NC}"
    echo ""
    usage
fi

if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
fi

CLAIM_FILE="$1"

echo "=================================================="
echo "EventDrivenService Claim Validation"
echo "=================================================="
echo ""

# Check if claim file exists
if [[ ! -f "${CLAIM_FILE}" ]]; then
    echo -e "${RED}ERROR: Claim file not found: ${CLAIM_FILE}${NC}"
    exit 2
fi

echo -e "${GREEN}✓${NC} Found claim file: ${CLAIM_FILE}"

# Check if schema file exists
if [[ ! -f "${SCHEMA_FILE}" ]]; then
    echo -e "${RED}ERROR: Schema file not found: ${SCHEMA_FILE}${NC}"
    echo ""
    echo "Run the schema publication script first:"
    echo "  ${SCRIPT_DIR}/publish-schema.sh"
    exit 2
fi

echo -e "${GREEN}✓${NC} Found schema file: ${SCHEMA_FILE}"

# Check for required tools
if ! command -v yq &> /dev/null; then
    echo -e "${RED}ERROR: yq is not installed${NC}"
    echo ""
    echo "Install with:"
    echo "  macOS:  brew install yq"
    echo "  Linux:  See https://github.com/mikefarah/yq"
    exit 2
fi

echo -e "${GREEN}✓${NC} Found yq: $(yq --version)"

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}ERROR: Python 3 is not installed${NC}"
    echo ""
    echo "Install with:"
    echo "  macOS:  brew install python3"
    echo "  Linux:  apt-get install python3 (Debian/Ubuntu)"
    exit 2
fi

echo -e "${GREEN}✓${NC} Found Python: $(python3 --version)"

# Check if jsonschema module is available
if ! python3 -c "import jsonschema" 2>/dev/null; then
    echo -e "${YELLOW}ℹ${NC} Installing jsonschema module..."
    if ! python3 -m pip install --quiet jsonschema 2>/dev/null; then
        echo -e "${RED}ERROR: Failed to install jsonschema module${NC}"
        echo ""
        echo "Install manually with:"
        echo "  python3 -m pip install jsonschema"
        exit 2
    fi
fi

echo -e "${GREEN}✓${NC} Found jsonschema module"

# Convert YAML claim to JSON for validation
echo ""
echo "Converting claim to JSON..."
TEMP_JSON=$(mktemp)
trap "rm -f ${TEMP_JSON}" EXIT

if ! yq eval -o=json "${CLAIM_FILE}" > "${TEMP_JSON}" 2>/dev/null; then
    echo -e "${RED}ERROR: Failed to parse YAML claim file${NC}"
    echo ""
    echo "The claim file may contain invalid YAML syntax."
    exit 1
fi

echo -e "${GREEN}✓${NC} Claim converted to JSON"

# Validate against schema
echo ""
echo "Validating claim against schema..."
echo ""

# Run validation using Python jsonschema (better draft 2020-12 support)
# Capture both stdout and stderr, and preserve exit code
set +e
VALIDATION_OUTPUT=$(python3 -c "
import json
import sys
from jsonschema import validate, ValidationError, Draft202012Validator
from jsonschema.exceptions import SchemaError

try:
    with open('${SCHEMA_FILE}', 'r') as f:
        schema = json.load(f)
    
    with open('${TEMP_JSON}', 'r') as f:
        instance = json.load(f)
    
    # Use Draft 2020-12 validator
    validator = Draft202012Validator(schema)
    errors = list(validator.iter_errors(instance))
    
    if errors:
        print('Validation failed with {} error(s):'.format(len(errors)), file=sys.stdout)
        print('', file=sys.stdout)
        for i, error in enumerate(errors, 1):
            path = '.'.join(str(p) for p in error.absolute_path) if error.absolute_path else 'root'
            print('Error {}: at {}'.format(i, path), file=sys.stdout)
            print('  {}'.format(error.message), file=sys.stdout)
            if error.validator:
                print('  Validator: {}'.format(error.validator), file=sys.stdout)
            print('', file=sys.stdout)
        sys.exit(1)
    else:
        print('valid', file=sys.stdout)
        sys.exit(0)
        
except ValidationError as e:
    print('Validation error: {}'.format(e.message), file=sys.stdout)
    sys.exit(1)
except SchemaError as e:
    print('Schema error: {}'.format(e.message), file=sys.stdout)
    sys.exit(1)
except Exception as e:
    print('Error: {}'.format(str(e)), file=sys.stdout)
    sys.exit(1)
" 2>&1)

VALIDATION_EXIT_CODE=$?
set -e

if [[ ${VALIDATION_EXIT_CODE} -eq 0 ]] && echo "${VALIDATION_OUTPUT}" | grep -q "valid"; then
    echo "${VALIDATION_OUTPUT}"
    echo ""
    echo "=================================================="
    echo -e "${GREEN}✓ Validation successful${NC}"
    echo "=================================================="
    echo ""
    echo "Claim file: ${CLAIM_FILE}"
    echo ""
    
    # Display claim summary
    echo "Claim summary:"
    echo -e "${BLUE}Name:${NC}       $(yq eval '.metadata.name' "${CLAIM_FILE}")"
    echo -e "${BLUE}Namespace:${NC}  $(yq eval '.metadata.namespace // "default"' "${CLAIM_FILE}")"
    echo -e "${BLUE}Image:${NC}      $(yq eval '.spec.image' "${CLAIM_FILE}")"
    echo -e "${BLUE}Size:${NC}       $(yq eval '.spec.size // "medium"' "${CLAIM_FILE}")"
    echo -e "${BLUE}Stream:${NC}     $(yq eval '.spec.nats.stream' "${CLAIM_FILE}")"
    echo -e "${BLUE}Consumer:${NC}   $(yq eval '.spec.nats.consumer' "${CLAIM_FILE}")"
    
    # Check for optional features
    SECRET_COUNT=0
    for i in {1..5}; do
        SECRET_NAME=$(yq eval ".spec.secret${i}Name // \"\"" "${CLAIM_FILE}")
        if [[ -n "${SECRET_NAME}" ]] && [[ "${SECRET_NAME}" != "null" ]]; then
            ((SECRET_COUNT++))
        fi
    done
    
    if [[ ${SECRET_COUNT} -gt 0 ]]; then
        echo -e "${BLUE}Secrets:${NC}    ${SECRET_COUNT} secret(s) configured"
    fi
    
    INIT_CONTAINER=$(yq eval '.spec.initContainer.command // ""' "${CLAIM_FILE}")
    if [[ -n "${INIT_CONTAINER}" ]] && [[ "${INIT_CONTAINER}" != "null" ]]; then
        echo -e "${BLUE}Init:${NC}       Init container configured"
    fi
    
    IMAGE_PULL_SECRETS=$(yq eval '.spec.imagePullSecrets // [] | length' "${CLAIM_FILE}")
    if [[ "${IMAGE_PULL_SECRETS}" != "0" ]]; then
        echo -e "${BLUE}Pull Secrets:${NC} ${IMAGE_PULL_SECRETS} configured"
    fi
    
    echo ""
    exit 0
else
    echo "${VALIDATION_OUTPUT}"
    echo ""
    echo "=================================================="
    echo -e "${RED}✗ Validation failed${NC}"
    echo "=================================================="
    echo ""
    echo "Claim file: ${CLAIM_FILE}"
    echo ""
    echo -e "${YELLOW}Common validation errors:${NC}"
    echo ""
    echo "1. Missing required fields:"
    echo "   - spec.image (container image reference)"
    echo "   - spec.nats.stream (JetStream stream name)"
    echo "   - spec.nats.consumer (consumer group name)"
    echo ""
    echo "2. Invalid field values:"
    echo "   - spec.size must be: small, medium, or large"
    echo "   - spec.nats.stream must be uppercase with underscores (e.g., AGENT_EXECUTION)"
    echo "   - spec.nats.consumer must be lowercase with hyphens (e.g., agent-executor-workers)"
    echo "   - spec.image must be a valid container image reference"
    echo ""
    echo "3. Invalid resource names:"
    echo "   - metadata.name must be lowercase alphanumeric with hyphens"
    echo "   - Secret names must follow Kubernetes naming conventions"
    echo ""
    echo "See the schema for complete validation rules:"
    echo "  ${SCHEMA_FILE}"
    echo ""
    echo "Example valid claims:"
    echo "  ${PROJECT_ROOT}/platform/04-apis/examples/minimal-claim.yaml"
    echo "  ${PROJECT_ROOT}/platform/04-apis/examples/full-claim.yaml"
    echo ""
    exit 1
fi

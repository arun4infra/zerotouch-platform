#!/bin/bash
# Bootstrap script to generate Age keypair for SOPS encryption
# Usage: ./generate-age-keys.sh
#
# This script generates a 256-bit Age keypair and outputs the keys
# to environment variables for use by subsequent scripts.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Age Keypair Generation for SOPS Encryption                ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if age-keygen is installed
if ! command -v age-keygen &> /dev/null; then
    echo -e "${RED}✗ Error: age-keygen not found${NC}"
    echo -e "${YELLOW}Install age: https://github.com/FiloSottile/age${NC}"
    echo ""
    echo -e "${YELLOW}Installation options:${NC}"
    echo -e "  macOS:   ${GREEN}brew install age${NC}"
    echo -e "  Linux:   ${GREEN}apt-get install age${NC} or ${GREEN}yum install age${NC}"
    exit 1
fi

echo -e "${GREEN}✓ age-keygen found${NC}"
echo ""

# Generate Age keypair
echo -e "${BLUE}Generating 256-bit Age keypair...${NC}"

# Generate keypair and capture output
KEYGEN_OUTPUT=$(age-keygen 2>&1)

# Extract public key (format: # public key: age1...)
AGE_PUBLIC_KEY=$(echo "$KEYGEN_OUTPUT" | grep "# public key:" | sed 's/# public key: //')

# Extract private key (format: AGE-SECRET-KEY-1...)
AGE_PRIVATE_KEY=$(echo "$KEYGEN_OUTPUT" | grep "^AGE-SECRET-KEY-1" | head -n 1)

# Validate keys were generated
if [ -z "$AGE_PUBLIC_KEY" ]; then
    echo -e "${RED}✗ Error: Failed to generate public key${NC}"
    exit 1
fi

if [ -z "$AGE_PRIVATE_KEY" ]; then
    echo -e "${RED}✗ Error: Failed to generate private key${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Age keypair generated successfully${NC}"
echo ""

# Export keys to environment variables
export AGE_PUBLIC_KEY
export AGE_PRIVATE_KEY

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Generated Keys                                             ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Public Key:${NC}"
echo -e "  $AGE_PUBLIC_KEY"
echo ""
echo -e "${GREEN}Private Key:${NC}"
echo -e "  $AGE_PRIVATE_KEY"
echo ""

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Environment Variables                                      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ AGE_PUBLIC_KEY exported${NC}"
echo -e "${GREEN}✓ AGE_PRIVATE_KEY exported${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Run inject-age-key.sh to create Kubernetes secret"
echo -e "  2. Configure .sops.yaml with the public key"
echo -e "  3. Store private key securely (backup)"
echo ""
echo -e "${YELLOW}Usage in subsequent scripts:${NC}"
echo -e "  ${GREEN}source ./generate-age-keys.sh${NC}"
echo -e "  ${GREEN}echo \$AGE_PUBLIC_KEY${NC}"
echo -e "  ${GREEN}echo \$AGE_PRIVATE_KEY${NC}"
echo ""

exit 0

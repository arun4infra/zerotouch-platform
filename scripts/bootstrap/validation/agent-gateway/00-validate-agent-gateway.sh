#!/bin/bash
# Run all gateway validation scripts in order
# This script executes validation scripts that are ready to run
#
# Usage: ./00-validate-all-gateway.sh
#
# Run this to validate complete gateway functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Gateway Validation Suite                                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Track validation results
TOTAL_VALIDATIONS=0
PASSED_VALIDATIONS=0
FAILED_VALIDATIONS=0

# CHECKPOINT 1: Test Endpoint Ready (uses run-validation.sh)
echo -e "${BLUE}Running: CHECKPOINT 1 - Test Endpoint Ready${NC}"
TOTAL_VALIDATIONS=$((TOTAL_VALIDATIONS + 1))
if "$SCRIPT_DIR/02-run-validation.sh"; then
    echo -e "${GREEN}✓ CHECKPOINT 1 PASSED${NC}"
    PASSED_VALIDATIONS=$((PASSED_VALIDATIONS + 1))
else
    echo -e "${RED}✗ CHECKPOINT 1 FAILED${NC}"
    FAILED_VALIDATIONS=$((FAILED_VALIDATIONS + 1))
fi
echo ""

# CHECKPOINT 2: Gateway Configuration Validated
echo -e "${BLUE}Running: CHECKPOINT 2 - Gateway Configuration${NC}"
TOTAL_VALIDATIONS=$((TOTAL_VALIDATIONS + 1))
if "$SCRIPT_DIR/03-run-gateway-config-validation.sh"; then
    echo -e "${GREEN}✓ CHECKPOINT 2 PASSED${NC}"
    PASSED_VALIDATIONS=$((PASSED_VALIDATIONS + 1))
else
    echo -e "${RED}✗ CHECKPOINT 2 FAILED${NC}"
    FAILED_VALIDATIONS=$((FAILED_VALIDATIONS + 1))
fi
echo ""

# CHECKPOINT 3: Complete Authentication Flow Working
echo -e "${BLUE}Running: CHECKPOINT 3 - Complete Authentication Flow${NC}"
TOTAL_VALIDATIONS=$((TOTAL_VALIDATIONS + 1))
if "$SCRIPT_DIR/04-run-platform-auth-validation.sh"; then
    echo -e "${GREEN}✓ CHECKPOINT 3 PASSED${NC}"
    PASSED_VALIDATIONS=$((PASSED_VALIDATIONS + 1))
else
    echo -e "${RED}✗ CHECKPOINT 3 FAILED${NC}"
    FAILED_VALIDATIONS=$((FAILED_VALIDATIONS + 1))
fi
echo ""

# CHECKPOINT 4: Validation Suite Complete (future implementation)
# echo -e "${BLUE}Running: CHECKPOINT 4 - Validation Suite Complete${NC}"
# TOTAL_VALIDATIONS=$((TOTAL_VALIDATIONS + 1))
# if "$SCRIPT_DIR/05-run-validation-suite.sh"; then
#     echo -e "${GREEN}✓ CHECKPOINT 4 PASSED${NC}"
#     PASSED_VALIDATIONS=$((PASSED_VALIDATIONS + 1))
# else
#     echo -e "${RED}✗ CHECKPOINT 4 FAILED${NC}"
#     FAILED_VALIDATIONS=$((FAILED_VALIDATIONS + 1))
# fi
# echo ""

# Summary
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Validation Summary                                        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo -e "Total Validations: $TOTAL_VALIDATIONS"
echo -e "${GREEN}Passed: $PASSED_VALIDATIONS${NC}"
echo -e "${RED}Failed: $FAILED_VALIDATIONS${NC}"
echo ""

if [ $FAILED_VALIDATIONS -eq 0 ]; then
    echo -e "${GREEN}✓ All gateway validations passed successfully${NC}"
    exit 0
else
    echo -e "${RED}✗ $FAILED_VALIDATIONS validation(s) failed${NC}"
    exit 1
fi
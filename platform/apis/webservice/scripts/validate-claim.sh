#!/bin/bash

# WebService Claim Validation Script
#
# This script validates WebService claims against the XRD schema
# and provides detailed feedback on validation errors.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBSERVICE_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <claim-file>"
    echo ""
    echo "Validates a WebService claim against the XRD schema."
    echo ""
    echo "Examples:"
    echo "  $0 examples/minimal-claim.yaml"
    echo "  $0 examples/full-claim.yaml"
    echo "  $0 examples/ide-orchestrator-claim.yaml"
    echo ""
    echo "Test fixtures:"
    echo "  $0 tests/fixtures/valid-minimal.yaml"
    echo "  $0 tests/fixtures/invalid-missing-image.yaml"
    exit 1
}

validate_prerequisites() {
    echo -e "${BLUE}🔍 Checking prerequisites...${NC}"
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl is not installed or not in PATH${NC}"
        exit 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
        echo "Please ensure kubectl is configured and cluster is accessible"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

validate_xrd_exists() {
    echo -e "${BLUE}🔍 Checking WebService XRD...${NC}"
    
    if ! kubectl get crd xwebservices.platform.bizmatters.io &> /dev/null; then
        echo -e "${RED}❌ WebService XRD not found${NC}"
        echo "Please apply the XRD first:"
        echo "  kubectl apply -f $WEBSERVICE_DIR/definitions/xwebservices.yaml"
        exit 1
    fi
    
    echo -e "${GREEN}✅ WebService XRD exists${NC}"
}

validate_claim_file() {
    local claim_file="$1"
    
    echo -e "${BLUE}🔍 Validating claim file: $claim_file${NC}"
    
    # Check if file exists
    if [[ ! -f "$claim_file" ]]; then
        echo -e "${RED}❌ Claim file not found: $claim_file${NC}"
        exit 1
    fi
    
    # Validate YAML syntax
    if ! kubectl apply --dry-run=client -f "$claim_file" &> /dev/null; then
        echo -e "${RED}❌ Invalid YAML syntax${NC}"
        kubectl apply --dry-run=client -f "$claim_file"
        exit 1
    fi
    
    # Validate against XRD schema
    echo -e "${BLUE}🔍 Validating against WebService XRD schema...${NC}"
    
    if kubectl apply --dry-run=server -f "$claim_file" &> /dev/null; then
        echo -e "${GREEN}✅ Claim validation passed${NC}"
        
        # Extract and display key information
        echo -e "${BLUE}📋 Claim Summary:${NC}"
        
        local name=$(kubectl get -f "$claim_file" -o jsonpath='{.metadata.name}' --dry-run=client)
        local namespace=$(kubectl get -f "$claim_file" -o jsonpath='{.metadata.namespace}' --dry-run=client)
        local image=$(kubectl get -f "$claim_file" -o jsonpath='{.spec.image}' --dry-run=client)
        local port=$(kubectl get -f "$claim_file" -o jsonpath='{.spec.port}' --dry-run=client)
        local size=$(kubectl get -f "$claim_file" -o jsonpath='{.spec.size}' --dry-run=client)
        local replicas=$(kubectl get -f "$claim_file" -o jsonpath='{.spec.replicas}' --dry-run=client)
        local database=$(kubectl get -f "$claim_file" -o jsonpath='{.spec.databaseName}' --dry-run=client)
        local hostname=$(kubectl get -f "$claim_file" -o jsonpath='{.spec.hostname}' --dry-run=client)
        
        echo "  Name: $name"
        echo "  Namespace: $namespace"
        echo "  Image: $image"
        echo "  Port: $port"
        echo "  Size: ${size:-medium}"
        echo "  Replicas: ${replicas:-2}"
        
        if [[ -n "$database" ]]; then
            echo "  Database: $database (will be provisioned)"
        else
            echo "  Database: None"
        fi
        
        if [[ -n "$hostname" ]]; then
            echo "  External Access: https://$hostname"
        else
            echo "  External Access: Internal only"
        fi
        
        echo ""
        echo -e "${GREEN}🎉 WebService claim is valid and ready to deploy!${NC}"
        echo ""
        echo "To deploy this claim:"
        echo "  kubectl apply -f $claim_file"
        echo ""
        echo "To check status after deployment:"
        echo "  kubectl get webservice $name -n ${namespace:-default}"
        
    else
        echo -e "${RED}❌ Claim validation failed${NC}"
        echo ""
        echo "Validation errors:"
        kubectl apply --dry-run=server -f "$claim_file"
        exit 1
    fi
}

run_test_suite() {
    echo -e "${BLUE}🧪 Running WebService XRD test suite...${NC}"
    
    local test_dir="$WEBSERVICE_DIR/tests/fixtures"
    local passed=0
    local failed=0
    
    echo ""
    echo -e "${BLUE}Testing valid claims (should pass):${NC}"
    
    for test_file in "$test_dir"/valid-*.yaml; do
        if [[ -f "$test_file" ]]; then
            local test_name=$(basename "$test_file")
            echo -n "  $test_name: "
            
            if kubectl apply --dry-run=server -f "$test_file" &> /dev/null; then
                echo -e "${GREEN}PASS${NC}"
                ((passed++))
            else
                echo -e "${RED}FAIL${NC}"
                ((failed++))
            fi
        fi
    done
    
    echo ""
    echo -e "${BLUE}Testing invalid claims (should fail):${NC}"
    
    for test_file in "$test_dir"/invalid-*.yaml; do
        if [[ -f "$test_file" ]]; then
            local test_name=$(basename "$test_file")
            echo -n "  $test_name: "
            
            if kubectl apply --dry-run=server -f "$test_file" &> /dev/null; then
                echo -e "${RED}FAIL (should have been rejected)${NC}"
                ((failed++))
            else
                echo -e "${GREEN}PASS (correctly rejected)${NC}"
                ((passed++))
            fi
        fi
    done
    
    echo ""
    echo -e "${BLUE}📊 Test Results:${NC}"
    echo "  Passed: $passed"
    echo "  Failed: $failed"
    
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}🎉 All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}❌ Some tests failed${NC}"
        return 1
    fi
}

main() {
    if [[ $# -eq 0 ]]; then
        usage
    fi
    
    local claim_file="$1"
    
    # Special case: run test suite
    if [[ "$claim_file" == "--test" ]]; then
        validate_prerequisites
        validate_xrd_exists
        run_test_suite
        exit $?
    fi
    
    # Validate single claim file
    validate_prerequisites
    validate_xrd_exists
    validate_claim_file "$claim_file"
}

main "$@"
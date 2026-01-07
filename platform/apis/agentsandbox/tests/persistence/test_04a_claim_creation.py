#!/usr/bin/env python3
"""
Test Claim Creation and Basic Validation
Validates AgentSandboxService claim creation and Sandbox resource provisioning
Usage: pytest test_04a_claim_creation.py -v
"""

import pytest
import time


class TestClaimCreation:

    def test_create_claim_and_validate_resources(self, ready_claim_manager, k8s, colors):
        """Test: Create claim and validate all resources are provisioned"""
        test_claim_name = "test-claim-creation"
        print(f"{colors.BLUE}Testing Claim Creation and Resource Provisioning{colors.NC}")
        
        # Create claim with complete setup using fixture (already waits for Ready state)
        pod_name = ready_claim_manager(test_claim_name, "CLAIM_CREATION_STREAM")
        
        # Validate pod is running using fixture result
        assert pod_name is not None
        print(f"{colors.GREEN}✓ Pod {pod_name} is running and ready{colors.NC}")
        
        # Validate PVC exists using k8s fixture
        k8s.run(["get", "pvc", f"{test_claim_name}-workspace", "-n", "intelligence-deepagents"])
        print(f"{colors.GREEN}✓ PVC {test_claim_name}-workspace exists{colors.NC}")
        
        # Validate Service exists using k8s fixture
        k8s.run(["get", "service", f"{test_claim_name}-http", "-n", "intelligence-deepagents"])
        print(f"{colors.GREEN}✓ Service {test_claim_name}-http exists{colors.NC}")
        
        print(f"{colors.GREEN}✓ All resources validated successfully{colors.NC}")
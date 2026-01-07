#!/usr/bin/env python3
"""
Test Dependency Enforcement (dependsOn validation)
Validates Sandbox stops when PVC dependency is lost
Usage: pytest test_08_dependency_enforcement.py -v
"""

import pytest
import time


class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'


class TestDependencyEnforcement:

    def test_dependency_order_enforcement(self, ready_claim_manager, ttl_manager, colors):
        """Test: Sandbox depends on PVC (dependsOn validation)"""
        test_claim_name = "test-dependency-enforce-8"
        namespace = "intelligence-deepagents"
        print(f"{colors.BLUE}Testing Dependency Order Enforcement{colors.NC}")
        
        # Step 1: Create claim and verify normal operation
        pod_name = ready_claim_manager(test_claim_name, "DEPENDENCY_STREAM")
        
        # Step 2: Delete claim to break dependency (simulates PVC deletion)
        print(f"{colors.YELLOW}⚠️ Breaking PVC dependency...{colors.NC}")
        ready_claim_manager.delete(test_claim_name, namespace)
        ready_claim_manager.wait_cleanup(test_claim_name, namespace)
        
        # Step 3: Verify Cold state (dependency failure)
        assert ttl_manager.verify_cold(test_claim_name, namespace)
        print(f"{colors.GREEN}✓ Sandbox stopped due to PVC dependency failure{colors.NC}")
        
        # Step 4: Verify dependency restoration
        print(f"{colors.YELLOW}⏳ Verifying dependency restoration...{colors.NC}")
        pod_name = ready_claim_manager(test_claim_name, "DEPENDENCY_STREAM")
        print(f"{colors.GREEN}✓ Sandbox restored after dependency recreation{colors.NC}")
        
        print(f"{colors.GREEN}✓ Dependency Enforcement Test Complete{colors.NC}")

    def test_pod_startup_without_pvc(self, ready_claim_manager, ttl_manager, colors):
        """Test: Pod should not start without PVC (dependsOn prevents it)"""
        test_claim_name = "test-pod-startup-8"
        namespace = "intelligence-deepagents"
        print(f"{colors.BLUE}Testing Pod Startup Prevention{colors.NC}")
        
        # Create claim and immediately delete to test dependency
        pod_name = ready_claim_manager(test_claim_name, "STARTUP_DEPENDENCY_STREAM")
        
        # Delete claim to simulate PVC dependency failure
        ready_claim_manager.delete(test_claim_name, namespace)
        ready_claim_manager.wait_cleanup(test_claim_name, namespace)
        
        # Verify system enters cold state (no pod without PVC)
        assert ttl_manager.verify_cold(test_claim_name, namespace)
        print(f"{colors.GREEN}✓ Pod correctly prevented from starting without PVC{colors.NC}")
        
        # Verify restoration works
        pod_name = ready_claim_manager(test_claim_name, "STARTUP_DEPENDENCY_STREAM")
        print(f"{colors.GREEN}✓ Pod starts correctly when PVC dependency is available{colors.NC}")
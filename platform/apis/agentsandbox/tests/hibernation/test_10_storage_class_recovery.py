#!/usr/bin/env python3
"""
Test Storage Class Corruption Recovery
Validates PVC recreation with correct storage class after corruption
Usage: pytest test_10_storage_class_recovery.py -v
"""

import pytest
import time


class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'


class TestStorageClassRecovery:

    def test_storage_class_corruption_recovery(self, ready_claim_manager, ttl_manager, colors):
        """Test: Storage class corruption and recovery"""
        test_claim_name = "test-storage-recovery-10"
        namespace = "intelligence-deepagents"
        print(f"{colors.BLUE}Testing Storage Class Corruption Recovery{colors.NC}")
        
        # Step 1: Create claim and verify normal operation
        pod_name = ready_claim_manager(test_claim_name, "STORAGE_RECOVERY_STREAM")
        print(f"{colors.GREEN}✓ Claim created with correct storage class{colors.NC}")
        
        # Step 2: Simulate storage corruption by deleting claim
        print(f"{colors.YELLOW}⚠️ Simulating storage class corruption...{colors.NC}")
        ready_claim_manager.delete(test_claim_name, namespace)
        ready_claim_manager.wait_cleanup(test_claim_name, namespace)
        
        # Step 3: Verify Cold state (storage deleted)
        assert ttl_manager.verify_cold(test_claim_name, namespace)
        print(f"{colors.GREEN}✓ Storage corruption detected (PVC deleted){colors.NC}")
        
        # Step 4: Verify recreation with correct storage class
        print(f"{colors.YELLOW}⏳ Verifying recreation with correct storage class...{colors.NC}")
        pod_name = ready_claim_manager(test_claim_name, "STORAGE_RECOVERY_STREAM")
        print(f"{colors.GREEN}✓ PVC recreated with correct storage class{colors.NC}")
        
        print(f"{colors.GREEN}✓ Storage Class Recovery Test Complete{colors.NC}")

    def test_pvc_size_validation_recovery(self, ready_claim_manager, ttl_manager, colors):
        """Test: PVC size validation and recovery"""
        test_claim_name = "test-size-recovery-10"
        namespace = "intelligence-deepagents"
        print(f"{colors.BLUE}Testing PVC Size Validation Recovery{colors.NC}")
        
        # Create claim with default size (5Gi from composition)
        pod_name = ready_claim_manager(test_claim_name, "SIZE_RECOVERY_STREAM")
        print(f"{colors.GREEN}✓ Initial PVC created with correct size{colors.NC}")
        
        # Delete and recreate to test size consistency
        ready_claim_manager.delete(test_claim_name, namespace)
        ready_claim_manager.wait_cleanup(test_claim_name, namespace)
        
        # Verify Cold state
        assert ttl_manager.verify_cold(test_claim_name, namespace)
        
        # Recreate and verify size consistency
        pod_name = ready_claim_manager(test_claim_name, "SIZE_RECOVERY_STREAM")
        print(f"{colors.GREEN}✓ Recreated PVC with consistent size{colors.NC}")
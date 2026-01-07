#!/usr/bin/env python3
"""
Test PVC Sizing Validation
Validates PVC is created with correct size from storageGB field
Usage: pytest test_04b_pvc_sizing_validation.py -v
"""

import pytest
import time


class TestPVCSizingValidation:

    def test_pvc_sizing_from_storage_gb(self, ready_claim_manager, k8s, colors):
        """Test: PVC sizing matches storageGB field"""
        print(f"{colors.BLUE}Testing PVC Sizing from storageGB Field{colors.NC}")
        
        # Test different storage sizes
        test_cases = [
            {"size": 5, "expected": "5Gi", "claim": "test-pvc-sizing-5gb"},
            {"size": 20, "expected": "20Gi", "claim": "test-pvc-sizing-20gb"}
        ]
        
        for case in test_cases:
            # Create claim with specific storage size using fixture
            pod_name = ready_claim_manager(
                case["claim"], 
                "PVC_SIZING_STREAM",
                storageGB=case["size"]
            )
            
            # Validate PVC size using k8s fixture
            result = k8s.run([
                "get", "pvc", f"{case['claim']}-workspace", "-n", "intelligence-deepagents",
                "-o", "jsonpath={.spec.resources.requests.storage}"
            ])
            
            actual_size = result.stdout.strip()
            assert actual_size == case["expected"], f"Expected {case['expected']}, got {actual_size}"
            
            print(f"{colors.GREEN}✓ PVC {case['claim']}-workspace: {actual_size} (correct){colors.NC}")

    def test_default_storage_size(self, ready_claim_manager, k8s, colors):
        """Test: Default storage size when storageGB not specified"""
        print(f"{colors.BLUE}Testing Default Storage Size{colors.NC}")
        
        # Create claim without storageGB field using fixture
        pod_name = ready_claim_manager("test-pvc-default", "PVC_DEFAULT_STREAM")
        
        # Check default size (should be 10Gi from composition default)
        result = k8s.run([
            "get", "pvc", "test-pvc-default-workspace", "-n", "intelligence-deepagents",
            "-o", "jsonpath={.spec.resources.requests.storage}"
        ])
        
        default_size = result.stdout.strip()
        expected_default = "10Gi"  # From composition default
        
        assert default_size == expected_default, f"Expected {expected_default}, got {default_size}"
        print(f"{colors.GREEN}✓ Default PVC size correct: {default_size}{colors.NC}")
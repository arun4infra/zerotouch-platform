#!/usr/bin/env python3
"""
Test Resurrection (Pod Recreation with Data Persistence)
Validates stable identity and data persistence across pod recreation
Usage: pytest test_04d_resurrection_test.py -v
"""

import pytest
import time


class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'


class TestResurrectionTest:

    def test_pod_resurrection_with_data_persistence(self, ready_claim_manager, k8s):
        """Test: Pod resurrection maintains stable identity and data persistence"""
        test_claim_name = "test-resurrection-4d"
        print(f"{Colors.BLUE}Testing Pod Resurrection with Data Persistence{Colors.NC}")
        
        # Step 1: Create claim and get initial pod
        start_time = time.time()
        pod_name = ready_claim_manager(test_claim_name, "RESURRECTION_STREAM")
        original_pod_uid = k8s.get_pod_uid(pod_name)
        
        print(f"{Colors.BLUE}Original Pod: {pod_name} (UID: {original_pod_uid[:8]}...){Colors.NC}")
        
        # Step 2: Validate stable network identity
        service_name = f"{test_claim_name}-http"
        assert k8s.service_exists(service_name), f"Service {service_name} not found"
        print(f"{Colors.GREEN}✓ Stable network identity confirmed: Service '{service_name}' exists{Colors.NC}")
        
        # Step 3: Write test data
        test_data = f"resurrection-{original_pod_uid[:8]}"
        test_file = "/workspace/resurrection.txt"
        k8s.exec_in_pod(pod_name, f"echo '{test_data}' > {test_file}")
        print(f"{Colors.GREEN}✓ Test data written: {test_data}{Colors.NC}")
        
        # Step 4: Delete pod to trigger resurrection
        print(f"{Colors.BLUE}Deleting pod to trigger resurrection...{Colors.NC}")
        k8s.delete_pod(pod_name, wait=True)
        
        # Step 5: Wait for resurrection
        print(f"{Colors.BLUE}Waiting for pod resurrection...{Colors.NC}")
        time.sleep(10)
        new_pod_name = k8s.wait_for_pod("intelligence-deepagents", f"app.kubernetes.io/name={test_claim_name}")
        new_pod_uid = k8s.get_pod_uid(new_pod_name)
        
        resurrection_latency = time.time() - start_time
        print(f"{Colors.BLUE}New Pod: {new_pod_name} (UID: {new_pod_uid[:8]}...){Colors.NC}")
        print(f"{Colors.GREEN}✓ Resurrection Latency: {resurrection_latency:.2f}s{Colors.NC}")
        
        # Step 6: Validate data persistence
        actual_data = k8s.exec_in_pod(new_pod_name, f"cat {test_file}")
        assert actual_data.strip() == test_data, f"Data persistence failed. Expected: {test_data}, Got: {actual_data.strip()}"
        print(f"{Colors.GREEN}✓ Data persisted: {test_data}{Colors.NC}")
        
        # Step 7: Validate stable identity maintained
        assert k8s.service_exists(service_name), f"Service {service_name} lost after resurrection"
        print(f"{Colors.GREEN}✓ Stable network identity maintained{Colors.NC}")
        
        print(f"{Colors.GREEN}✓ Resurrection Test Complete{Colors.NC}")

    def test_multiple_resurrections(self, ready_claim_manager, k8s):
        """Test: Multiple pod resurrections maintain consistency"""
        test_claim_name = "test-multi-resurrection-4d"
        print(f"{Colors.BLUE}Testing Multiple Resurrections{Colors.NC}")
        
        # Create claim
        pod_name = ready_claim_manager(test_claim_name, "MULTI_RESURRECTION_STREAM")
        
        resurrection_data = []
        
        # Perform 3 resurrection cycles
        for i in range(3):
            print(f"{Colors.BLUE}Resurrection cycle {i+1}/3{Colors.NC}")
            
            pod_name = k8s.wait_for_pod("intelligence-deepagents", f"app.kubernetes.io/name={test_claim_name}")
            pod_uid = k8s.get_pod_uid(pod_name)
            
            # Write unique data for this cycle
            test_data = f"cycle-{i+1}-{pod_uid[:8]}"
            test_file = f"/workspace/cycle-{i+1}.txt"
            k8s.exec_in_pod(pod_name, f"echo '{test_data}' > {test_file}")
            
            resurrection_data.append({"file": test_file, "data": test_data})
            
            # Delete pod (except on last cycle)
            if i < 2:
                k8s.delete_pod(pod_name, wait=True)
                time.sleep(5)
        
        # Validate all data persisted
        final_pod = k8s.wait_for_pod("intelligence-deepagents", f"app.kubernetes.io/name={test_claim_name}")
        for cycle_data in resurrection_data:
            actual_data = k8s.exec_in_pod(final_pod, f"cat {cycle_data['file']}")
            assert actual_data.strip() == cycle_data["data"], f"Data persistence failed for {cycle_data['file']}"
            print(f"{Colors.GREEN}✓ Cycle data persisted: {cycle_data['data']}{Colors.NC}")
        
        print(f"{Colors.GREEN}✓ Multiple Resurrections Test Complete{Colors.NC}")
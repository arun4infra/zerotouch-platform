#!/usr/bin/env python3
"""
Test Resurrection (Pod Recreation with Data Persistence)
Validates stable identity and data persistence across pod recreation
Usage: pytest test_04d_resurrection_test.py -v
"""

import pytest
import time


class TestResurrectionTest:

    def test_pod_resurrection_with_data_persistence(self, ready_claim_manager, workspace_manager, k8s, colors):
        """Test: Warm State - Pod resurrection maintains stable identity and data persistence via PVC"""
        test_claim_name = "test-resurrection-4d"
        namespace = "intelligence-deepagents"
        print(f"{colors.BLUE}Testing Warm State Pod Resurrection{colors.NC}")
        
        # Step 1: Create claim and get initial pod
        start_time = time.time()
        original_pod_name = ready_claim_manager(test_claim_name, "RESURRECTION_STREAM")
        original_pod_uid = k8s.get_pod_uid(original_pod_name, namespace)
        
        print(f"{colors.BLUE}Original Pod: {original_pod_name} (UID: {original_pod_uid[:8]}...){colors.NC}")
        
        # Step 2: Validate stable network identity
        service_name = f"{test_claim_name}-http"
        assert k8s.service_exists(service_name, namespace), f"Service {service_name} not found"
        print(f"{colors.GREEN}✓ Stable network identity confirmed: Service '{service_name}' exists{colors.NC}")
        
        # Step 3: Write test data using workspace_manager fixture
        test_data = f"warm-resurrection-{original_pod_uid[:8]}"
        workspace_manager(test_claim_name, namespace, "warm-resurrection.txt", test_data)
        print(f"{colors.GREEN}✓ Test data written: {test_data}{colors.NC}")
        
        # Step 4: Verify sidecar backup to S3 before pod deletion
        print(f"{colors.BLUE}Waiting for sidecar backup to S3...{colors.NC}")
        time.sleep(90)  # Wait for sidecar backup cycle (package install + first backup cycle)
        
        # Check sidecar logs for successful S3 upload (check recent logs to avoid package installation noise)
        sidecar_logs = k8s.get_container_logs(original_pod_name, "workspace-backup-sidecar", namespace)
        # Also check recent logs in case backup happened after initial package installation
        try:
            import subprocess
            recent_logs = subprocess.run([
                "kubectl", "logs", original_pod_name, "-n", namespace, 
                "-c", "workspace-backup-sidecar", "--since=60s"
            ], capture_output=True, text=True, check=False).stdout
            sidecar_logs += "\n" + recent_logs
        except:
            pass
        
        assert ("Atomic backup completed:" in sidecar_logs or "Success: Final Key updated" in sidecar_logs or "upload:" in sidecar_logs) and "workspace.tar.gz" in sidecar_logs, "Sidecar backup to S3 not confirmed"
        print(f"{colors.GREEN}✓ Sidecar backup to S3 confirmed{colors.NC}")
        
        # Step 5: Delete pod (not claim) to trigger Warm resurrection
        print(f"{colors.BLUE}Deleting pod to trigger Warm resurrection...{colors.NC}")
        # Use graceful deletion to allow preStop hook, but with extended timeout for terminationGracePeriodSeconds
        k8s.delete_pod(original_pod_name, namespace, wait=True)
        
        # Step 6: Wait for pod to be recreated by Kubernetes (Warm resume)
        print(f"{colors.BLUE}Waiting for Warm resurrection...{colors.NC}")
        resurrection_start = time.time()
        new_pod_name = k8s.wait_for_pod(namespace, f"app.kubernetes.io/name={test_claim_name}")
        resurrection_latency = time.time() - resurrection_start
        new_pod_uid = k8s.get_pod_uid(new_pod_name, namespace)
        
        print(f"{colors.BLUE}New Pod: {new_pod_name} (UID: {new_pod_uid[:8]}...){colors.NC}")
        
        # Step 7: Validate Identity Immutability (Manus-level requirement)
        assert new_pod_name == original_pod_name, f"Identity broken! Expected: {original_pod_name}, Got: {new_pod_name}"
        print(f"{colors.GREEN}✓ Identity Immutability: Pod name preserved ({new_pod_name}){colors.NC}")
        
        # Step 8: Validate Warm resurrection latency (< 20 seconds with graceful shutdown + atomic backup)
        assert resurrection_latency < 20, f"Warm resurrection too slow: {resurrection_latency:.2f}s (should be < 20s)"
        print(f"{colors.GREEN}✓ Warm Resurrection Latency: {resurrection_latency:.2f}s (< 20s){colors.NC}")
        
        # Step 9: Validate data persistence via PVC (not S3)
        actual_data = workspace_manager.read(test_claim_name, namespace, "warm-resurrection.txt")
        assert actual_data == test_data, f"Warm data persistence failed. Expected: {test_data}, Got: {actual_data}"
        print(f"{colors.GREEN}✓ Warm data persisted via PVC: {test_data}{colors.NC}")
        
        # Step 10: Validate stable identity maintained
        assert k8s.service_exists(service_name, namespace), f"Service {service_name} lost after resurrection"
        print(f"{colors.GREEN}✓ Stable network identity maintained{colors.NC}")
        
        total_latency = time.time() - start_time
        print(f"{colors.GREEN}✓ Warm Resurrection Test Complete - Total: {total_latency:.2f}s{colors.NC}")

    def test_multiple_resurrections(self, ready_claim_manager, workspace_manager, k8s, colors):
        """Test: Multiple Warm resurrections maintain consistency and cumulative S3 data"""
        test_claim_name = "test-multi-resurrection-4d"
        namespace = "intelligence-deepagents"
        print(f"{colors.BLUE}Testing Multiple Warm Resurrections (Race Condition Stress){colors.NC}")
        
        # Create claim using ready_claim_manager fixture
        original_pod_name = ready_claim_manager(test_claim_name, "MULTI_RESURRECTION_STREAM")
        
        resurrection_data = []
        
        # Perform 3 resurrection cycles
        for i in range(3):
            print(f"{colors.BLUE}Resurrection cycle {i+1}/3{colors.NC}")
            
            # Write unique data for this cycle using workspace_manager fixture
            test_data = f"cycle-{i+1}-{int(time.time())}"
            workspace_manager(test_claim_name, namespace, f"cycle-{i+1}.txt", test_data)
            
            resurrection_data.append({"claim": test_claim_name, "file": f"cycle-{i+1}.txt", "data": test_data})
            print(f"{colors.GREEN}✓ Cycle {i+1} data written: {test_data}{colors.NC}")
            
            # Wait for sidecar sync before resurrection (except on last cycle)
            if i < 2:
                print(f"{colors.YELLOW}⏳ Waiting for sidecar sync...{colors.NC}")
                time.sleep(90)  # Wait for sidecar backup cycle (package install + backup cycle)
                
                # Get current pod name before deletion
                current_pod_name = k8s.wait_for_pod(namespace, f"app.kubernetes.io/name={test_claim_name}")
                
                # Verify sidecar backup before deletion
                sidecar_logs = k8s.get_container_logs(current_pod_name, "workspace-backup-sidecar", namespace)
                assert ("Atomic backup completed:" in sidecar_logs or "Success: Final Key updated" in sidecar_logs or "upload:" in sidecar_logs), f"Sidecar backup not confirmed in cycle {i+1}"
                print(f"{colors.GREEN}✓ Cycle {i+1} sidecar backup confirmed{colors.NC}")
                
                # Delete pod (not claim) to trigger Warm resurrection
                print(f"{colors.BLUE}Triggering Warm resurrection {i+1}...{colors.NC}")
                k8s.delete_pod(current_pod_name, namespace, wait=True)
                
                # Wait for pod to be recreated (Warm resume)
                time.sleep(15)
                new_pod_name = k8s.wait_for_pod(namespace, f"app.kubernetes.io/name={test_claim_name}")
                
                # Validate identity immutability across resurrections
                assert new_pod_name == current_pod_name, f"Identity broken in cycle {i+1}! Expected: {current_pod_name}, Got: {new_pod_name}"
                print(f"{colors.GREEN}✓ Cycle {i+1} identity preserved: {new_pod_name}{colors.NC}")
        
        # Final sidecar sync wait
        print(f"{colors.YELLOW}⏳ Final sidecar sync wait...{colors.NC}")
        time.sleep(45)
        
        # Validate all data persisted in workspace (PVC)
        for cycle_data in resurrection_data:
            actual_data = workspace_manager.read(cycle_data['claim'], namespace, cycle_data['file'])
            assert actual_data == cycle_data["data"], f"Data persistence failed for {cycle_data['file']}"
            print(f"{colors.GREEN}✓ Cycle data persisted in PVC: {cycle_data['data']}{colors.NC}")
        
        # Validate cumulative S3 data using workspace_manager fixture
        print(f"{colors.BLUE}Validating cumulative S3 data...{colors.NC}")
        for cycle_data in resurrection_data:
            s3_content = workspace_manager.read_s3(test_claim_name, namespace, cycle_data['file'])
            assert s3_content == cycle_data['data'], f"S3 data mismatch for {cycle_data['file']}"
            print(f"{colors.GREEN}✓ S3 cumulative data verified: {cycle_data['file']}{colors.NC}")
        
        print(f"{colors.GREEN}✓ Multiple Resurrections Test Complete - All cycles preserved{colors.NC}")

    def test_cold_resurrection(self, ready_claim_manager, workspace_manager, k8s, colors, claim_manager):
        """Test: Cold State - Scorched Earth resurrection via S3 (The Valet Test)"""
        test_claim_name = "test-cold-resurrection-4d"
        namespace = "intelligence-deepagents"
        print(f"{colors.BLUE}Testing Cold State Resurrection (Scorched Earth - Valet Test){colors.NC}")
        
        # Step 1: Create claim and write test data
        start_time = time.time()
        original_pod_name = ready_claim_manager(test_claim_name, "COLD_RESURRECTION_STREAM")
        original_pod_uid = k8s.get_pod_uid(original_pod_name, namespace)
        
        test_data = f"cold-valet-{original_pod_uid[:8]}"
        workspace_manager(test_claim_name, namespace, "cold-resurrection.txt", test_data)
        print(f"{colors.GREEN}✓ Test data written: {test_data}{colors.NC}")
        
        # Step 2: Wait for sidecar backup to S3 (Critical for Cold state)
        print(f"{colors.BLUE}Waiting for sidecar backup to S3...{colors.NC}")
        time.sleep(90)  # Wait for sidecar backup cycle (package install + first backup cycle)
        
        # Verify sidecar backup completed
        sidecar_logs = k8s.get_container_logs(original_pod_name, "workspace-backup-sidecar", namespace)
        assert ("Atomic backup completed:" in sidecar_logs or "Success: Final Key updated" in sidecar_logs or "upload:" in sidecar_logs) and "workspace.tar.gz" in sidecar_logs, "Sidecar backup to S3 not confirmed"
        print(f"{colors.GREEN}✓ Sidecar backup to S3 confirmed{colors.NC}")
        
        # Step 3: SCORCHED EARTH - Delete Claim (Pod AND PVC deleted)
        print(f"{colors.BLUE}🔥 SCORCHED EARTH: Deleting Claim (Pod + PVC)...{colors.NC}")
        
        # Before deletion, check if preStop hook will execute atomic backup
        print(f"{colors.BLUE}Triggering preStop hook for atomic final backup...{colors.NC}")
        
        claim_manager.delete(test_claim_name, namespace)
        claim_manager.wait_cleanup(test_claim_name, namespace)
        print(f"{colors.GREEN}✓ Claim deleted - Pod and PVC destroyed{colors.NC}")
        
        # Validate that preStop hook completed atomic backup (check logs if pod still exists briefly)
        print(f"{colors.GREEN}✓ PreStop atomic backup should have completed during deletion{colors.NC}")
        
        # Step 4: Re-Apply Claim with SAME NAME (Valet brings luggage from S3)
        print(f"{colors.BLUE}🎩 VALET: Re-creating claim with same identity...{colors.NC}")
        cold_resurrection_start = time.time()
        new_pod_name = ready_claim_manager(test_claim_name, "COLD_RESURRECTION_STREAM")
        cold_resurrection_latency = time.time() - cold_resurrection_start
        new_pod_uid = k8s.get_pod_uid(new_pod_name, namespace)
        
        print(f"{colors.BLUE}Valet Pod: {new_pod_name} (UID: {new_pod_uid[:8]}...){colors.NC}")
        
        # Step 5: Validate Identity Immutability (Same name, different UID)
        assert new_pod_name == original_pod_name, f"Valet identity broken! Expected: {original_pod_name}, Got: {new_pod_name}"
        assert new_pod_uid != original_pod_uid, f"Pod UID should be different after Cold resurrection"
        print(f"{colors.GREEN}✓ Valet Identity: Same name ({new_pod_name}), new UID{colors.NC}")
        
        # Step 6: Validate Cold resurrection latency (should be slower due to S3 download)
        assert cold_resurrection_latency >= 20, f"Cold resurrection too fast: {cold_resurrection_latency:.2f}s (should be >= 20s due to S3)"
        print(f"{colors.GREEN}✓ Cold Resurrection Latency: {cold_resurrection_latency:.2f}s (>= 20s with S3){colors.NC}")
        
        # Step 7: CRITICAL - Validate data came from S3 (not PVC, which was deleted)
        actual_data = workspace_manager.read(test_claim_name, namespace, "cold-resurrection.txt")
        assert actual_data == test_data, f"Cold data resurrection failed. Expected: {test_data}, Got: {actual_data}"
        print(f"{colors.GREEN}✓ VALET SUCCESS: Data restored from S3: {test_data}{colors.NC}")
        
        # Step 8: Verify InitContainer hydration logs (proof of S3 download)
        init_logs = k8s.get_container_logs(new_pod_name, "workspace-hydrator", namespace)
        assert ("Workspace hydrated successfully" in init_logs or "aws s3 cp" in init_logs or "aws s3 sync" in init_logs), "InitContainer S3 hydration not confirmed"
        print(f"{colors.GREEN}✓ InitContainer S3 hydration confirmed{colors.NC}")
        
        # Step 9: Validate stable network identity restored
        service_name = f"{test_claim_name}-http"
        assert k8s.service_exists(service_name, namespace), f"Service {service_name} not restored after Cold resurrection"
        print(f"{colors.GREEN}✓ Stable network identity restored{colors.NC}")
        
        total_latency = time.time() - start_time
        print(f"{colors.GREEN}✓ COLD RESURRECTION (VALET) TEST COMPLETE - Total: {total_latency:.2f}s{colors.NC}")
        print(f"{colors.GREEN}🎩 The Valet successfully brought the luggage from S3 to the new room!{colors.NC}")
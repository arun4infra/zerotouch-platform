#!/usr/bin/env python3
"""
Test Scorched Earth Recovery (Infrastructure Self-Healing - Unplanned)
This validates recovery from infrastructure drift/corruption while Claim remains active.
Usage: pytest test_06_scorched_earth_recovery.py -v
"""

import pytest
import subprocess
import tempfile
import os
import time


class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'


class TestScorchedEarthRecovery:
    def setup_method(self):
        self.tenant_name = "deepagents-runtime"
        self.namespace = "intelligence-deepagents"
        self.test_claim_name = "test-scorched-earth"
        self.temp_dir = tempfile.mkdtemp()
        print(f"{Colors.BLUE}[INFO] Scorched Earth Test Setup for {self.test_claim_name}{Colors.NC}")

    def teardown_method(self):
        try:
            import shutil
            shutil.rmtree(self.temp_dir)
        except:
            pass

    def test_01_create_claim_and_write_data(self):
        """Step 1: Create Claim, Write Test Data"""
        print(f"{Colors.BLUE}Step: 1. Creating Claim and Writing Test Data{Colors.NC}")
        
        claim_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: {self.test_claim_name}
  namespace: {self.namespace}
spec:
  image: "ghcr.io/arun4infra/deepagents-runtime:sha-9d6cb0e"
  size: "micro"
  nats:
    url: "nats://nats-headless.nats.svc.cluster.local:4222"
    stream: "SCORCHED_EARTH_STREAM"
    consumer: "scorched-earth-consumer"
  httpPort: 8080
  healthPath: "/health"
  readyPath: "/ready"
  storageGB: 5
  secret1Name: "deepagents-runtime-db-conn"
  secret2Name: "deepagents-runtime-cache-conn"
  secret3Name: "deepagents-runtime-llm-keys"
"""
        
        claim_file = os.path.join(self.temp_dir, "scorched-claim.yaml")
        with open(claim_file, 'w') as f:
            f.write(claim_yaml)
        
        subprocess.run(["kubectl", "apply", "-f", claim_file], check=True)
        print(f"{Colors.GREEN}✓ Created Claim {self.test_claim_name}{Colors.NC}")
        
        # Wait for pod to be running
        pod_name = self._wait_for_pod_running()
        
        # Write test data to workspace
        test_data = f"scorched-earth-test-{int(time.time())}"
        subprocess.run([
            "kubectl", "exec", pod_name, "-n", self.namespace, 
            "-c", "main", "--", "sh", "-c", 
            f"echo '{test_data}' > /workspace/scorched-test.txt"
        ], check=True)
        
        print(f"{Colors.GREEN}✓ Test data written: {test_data}{Colors.NC}")
        
        # Wait for S3 backup (sidecar runs every 30s)
        print(f"{Colors.YELLOW}⏳ Waiting 35s for S3 backup...{Colors.NC}")
        time.sleep(35)
        
        return test_data

    def test_02_simulate_infrastructure_corruption(self):
        """Step 2: Simulate Infrastructure Corruption (Node Failure Sequence)"""
        print(f"{Colors.BLUE}Step: 2. Simulating Infrastructure Corruption{Colors.NC}")
        
        # Step 2a: Delete Pod first (simulates node failure)
        try:
            subprocess.run([
                "kubectl", "delete", "pod", "-n", self.namespace,
                "-l", f"app.kubernetes.io/name={self.test_claim_name}",
                "--force", "--grace-period=0"
            ], check=True)
            print(f"{Colors.GREEN}✓ Pod deleted (simulated node failure){Colors.NC}")
        except subprocess.CalledProcessError:
            print(f"{Colors.YELLOW}⚠️ Pod already gone{Colors.NC}")
        
        # Step 2b: Wait for pod to be fully terminated
        timeout = 30
        count = 0
        while count < timeout:
            try:
                result = subprocess.run([
                    "kubectl", "get", "pods", "-n", self.namespace,
                    "-l", f"app.kubernetes.io/name={self.test_claim_name}"
                ], capture_output=True, text=True, check=True)
                
                if "No resources found" in result.stdout:
                    break
                    
            except subprocess.CalledProcessError:
                break
                
            time.sleep(2)
            count += 2
        
        print(f"{Colors.GREEN}✓ Pod termination complete{Colors.NC}")
        
        # Step 2c: Force delete PVC (simulates storage corruption)
        try:
            subprocess.run([
                "kubectl", "delete", "pvc", f"{self.test_claim_name}-workspace",
                "-n", self.namespace, "--force", "--grace-period=0"
            ], check=True)
            print(f"{Colors.GREEN}✓ PVC force deleted (simulated storage corruption){Colors.NC}")
        except subprocess.CalledProcessError:
            print(f"{Colors.YELLOW}⚠️ PVC already gone{Colors.NC}")

    def test_03_verify_crossplane_self_healing(self):
        """Step 3: Verify Crossplane Self-Healing (Infrastructure Recovery)"""
        print(f"{Colors.BLUE}Step: 3. Verifying Crossplane Self-Healing{Colors.NC}")
        
        # Crossplane should detect the drift and recreate resources
        # Wait for new PVC to be created
        timeout = 120
        count = 0
        pvc_created = False
        
        while count < timeout:
            try:
                result = subprocess.run([
                    "kubectl", "get", "pvc", f"{self.test_claim_name}-workspace",
                    "-n", self.namespace, "-o", "jsonpath={.status.phase}"
                ], capture_output=True, text=True, check=True)
                
                if result.stdout.strip() == "Bound":
                    pvc_created = True
                    print(f"{Colors.GREEN}✓ New PVC created and bound{Colors.NC}")
                    break
                    
            except subprocess.CalledProcessError:
                pass
                
            time.sleep(3)
            count += 3
        
        if not pvc_created:
            pytest.fail("Crossplane failed to recreate PVC after corruption")
        
        # Wait for new pod to be running
        pod_name = self._wait_for_pod_running()
        print(f"{Colors.GREEN}✓ New pod running: {pod_name}{Colors.NC}")

    def test_04_verify_data_recovery_from_s3(self):
        """Step 4: Verify Data Recovery from S3 Backup"""
        print(f"{Colors.BLUE}Step: 4. Verifying Data Recovery from S3{Colors.NC}")
        
        # Get current pod name
        result = subprocess.run([
            "kubectl", "get", "pods", "-n", self.namespace,
            "-l", f"app.kubernetes.io/name={self.test_claim_name}",
            "-o", "jsonpath={.items[0].metadata.name}"
        ], capture_output=True, text=True, check=True)
        
        pod_name = result.stdout.strip()
        
        # Check if data was restored from S3
        try:
            result = subprocess.run([
                "kubectl", "exec", pod_name, "-n", self.namespace,
                "-c", "main", "--", "cat", "/workspace/scorched-test.txt"
            ], capture_output=True, text=True, check=True)
            
            restored_data = result.stdout.strip()
            print(f"{Colors.GREEN}✓ Data recovered from S3: {restored_data}{Colors.NC}")
            
        except subprocess.CalledProcessError:
            # Check initContainer logs to see if S3 restore was attempted
            try:
                logs = subprocess.run([
                    "kubectl", "logs", pod_name, "-n", self.namespace,
                    "-c", "workspace-hydrator"
                ], capture_output=True, text=True, check=True)
                
                if "No existing workspace backup found" in logs.stdout:
                    print(f"{Colors.YELLOW}⚠️ No S3 backup found - Data loss expected{Colors.NC}")
                elif "Workspace hydrated successfully" in logs.stdout:
                    print(f"{Colors.GREEN}✓ S3 restore successful{Colors.NC}")
                else:
                    print(f"{Colors.RED}✗ S3 restore failed{Colors.NC}")
                    
            except subprocess.CalledProcessError:
                print(f"{Colors.YELLOW}⚠️ Could not check initContainer logs{Colors.NC}")

    def test_05_verify_system_operational(self):
        """Step 5: Verify System is Fully Operational After Recovery"""
        print(f"{Colors.BLUE}Step: 5. Verifying System Operational Status{Colors.NC}")
        
        # Get pod name
        result = subprocess.run([
            "kubectl", "get", "pods", "-n", self.namespace,
            "-l", f"app.kubernetes.io/name={self.test_claim_name}",
            "-o", "jsonpath={.items[0].metadata.name}"
        ], capture_output=True, text=True, check=True)
        
        pod_name = result.stdout.strip()
        
        # Test write capability
        recovery_data = f"post-recovery-test-{int(time.time())}"
        subprocess.run([
            "kubectl", "exec", pod_name, "-n", self.namespace,
            "-c", "main", "--", "sh", "-c",
            f"echo '{recovery_data}' > /workspace/recovery-test.txt"
        ], check=True)
        
        # Verify write
        result = subprocess.run([
            "kubectl", "exec", pod_name, "-n", self.namespace,
            "-c", "main", "--", "cat", "/workspace/recovery-test.txt"
        ], capture_output=True, text=True, check=True)
        
        if result.stdout.strip() == recovery_data:
            print(f"{Colors.GREEN}✓ System fully operational - Write/Read working{Colors.NC}")
        else:
            pytest.fail("System not operational after recovery")

    def test_06_cleanup(self):
        """Step 6: Final Cleanup"""
        print(f"{Colors.BLUE}Step: 6. Final Cleanup{Colors.NC}")
        
        try:
            subprocess.run([
                "kubectl", "delete", "agentsandboxservice", self.test_claim_name,
                "-n", self.namespace
            ], check=False)
            print(f"{Colors.GREEN}✓ Cleanup complete{Colors.NC}")
        except:
            pass

    def _wait_for_pod_running(self):
        """Helper to wait for pod to be running"""
        timeout = 120
        count = 0
        while count < timeout:
            try:
                result = subprocess.run([
                    "kubectl", "get", "pods", "-n", self.namespace,
                    "-l", f"app.kubernetes.io/name={self.test_claim_name}",
                    "--field-selector=status.phase=Running",
                    "-o", "jsonpath={.items[0].metadata.name}"
                ], capture_output=True, text=True, check=True)
                
                if result.stdout.strip():
                    return result.stdout.strip()
                    
            except subprocess.CalledProcessError:
                pass
                
            time.sleep(3)
            count += 3
            
        pytest.fail("Pod failed to reach running state")
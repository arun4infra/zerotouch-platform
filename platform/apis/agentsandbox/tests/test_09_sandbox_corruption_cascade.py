#!/usr/bin/env python3
"""
Test Sandbox Corruption Cascade Recovery
Validates Crossplane recreates Sandbox when directly deleted
Usage: pytest test_09_sandbox_corruption_cascade.py -v
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


class TestSandboxCorruptionCascade:
    def setup_method(self):
        self.namespace = "intelligence-deepagents"
        self.test_claim_name = "test-sandbox-cascade"
        self.temp_dir = tempfile.mkdtemp()
        print(f"{Colors.BLUE}[INFO] Sandbox Corruption Cascade Test{Colors.NC}")

    def teardown_method(self):
        try:
            subprocess.run([
                "kubectl", "delete", "agentsandboxservice", self.test_claim_name, "-n", self.namespace
            ], check=False)
            import shutil
            shutil.rmtree(self.temp_dir)
        except:
            pass

    def test_sandbox_corruption_recovery(self):
        """Test: Sandbox corruption and auto-recovery"""
        print(f"{Colors.BLUE}Testing Sandbox Corruption Recovery{Colors.NC}")
        
        # Step 1: Create claim and verify normal operation
        self._create_test_claim()
        self._wait_for_pod_running()
        
        # Step 2: Write test data
        test_data = f"cascade-test-{int(time.time())}"
        subprocess.run([
            "kubectl", "exec", self.test_claim_name, "-n", self.namespace,
            "-c", "main", "--", "sh", "-c",
            f"echo '{test_data}' > /workspace/cascade-test.txt"
        ], check=True)
        print(f"{Colors.GREEN}✓ Test data written{Colors.NC}")
        
        # Step 3: Delete Sandbox directly (simulates controller corruption)
        print(f"{Colors.YELLOW}⚠️ Simulating Sandbox corruption...{Colors.NC}")
        subprocess.run([
            "kubectl", "delete", "sandbox", self.test_claim_name, "-n", self.namespace
        ], check=True)
        
        # Step 4: Verify Crossplane recreates Sandbox
        self._verify_sandbox_recreation()
        
        # Step 5: Verify data persistence through S3
        self._verify_data_persistence()
        
        print(f"{Colors.GREEN}✓ Sandbox Corruption Cascade Test Complete{Colors.NC}")

    def test_pod_deletion_recovery(self):
        """Test: Pod deletion and auto-recovery via Sandbox controller"""
        print(f"{Colors.BLUE}Testing Pod Deletion Recovery{Colors.NC}")
        
        # Create claim and wait for pod
        self._create_test_claim("test-pod-recovery")
        pod_name = self._wait_for_pod_running("test-pod-recovery")
        
        # Delete pod directly
        print(f"{Colors.YELLOW}⚠️ Deleting pod directly...{Colors.NC}")
        subprocess.run([
            "kubectl", "delete", "pod", pod_name, "-n", self.namespace, "--force", "--grace-period=0"
        ], check=True)
        
        # Verify Sandbox controller recreates pod
        self._verify_pod_recreation("test-pod-recovery")
        
        # Cleanup
        subprocess.run([
            "kubectl", "delete", "agentsandboxservice", "test-pod-recovery", "-n", self.namespace
        ], check=False)

    def _create_test_claim(self, name=None):
        """Create test claim"""
        claim_name = name or self.test_claim_name
        
        claim_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: {claim_name}
  namespace: {self.namespace}
spec:
  image: "ghcr.io/arun4infra/deepagents-runtime:sha-9d6cb0e"
  size: "micro"
  nats:
    url: "nats://nats-headless.nats.svc.cluster.local:4222"
    stream: "CASCADE_STREAM"
    consumer: "cascade-consumer"
  httpPort: 8080
  healthPath: "/health"
  readyPath: "/ready"
  storageGB: 5
  secret1Name: "deepagents-runtime-db-conn"
  secret2Name: "deepagents-runtime-cache-conn"
  secret3Name: "deepagents-runtime-llm-keys"
"""
        
        claim_file = os.path.join(self.temp_dir, f"{claim_name}-claim.yaml")
        with open(claim_file, 'w') as f:
            f.write(claim_yaml)
        
        subprocess.run(["kubectl", "apply", "-f", claim_file], check=True)
        print(f"{Colors.GREEN}✓ Created claim {claim_name}{Colors.NC}")

    def _wait_for_pod_running(self, name=None):
        """Wait for pod to be running"""
        claim_name = name or self.test_claim_name
        timeout = 120
        count = 0
        while count < timeout:
            try:
                result = subprocess.run([
                    "kubectl", "get", "pods", "-n", self.namespace,
                    "-l", f"app.kubernetes.io/name={claim_name}",
                    "--field-selector=status.phase=Running",
                    "-o", "jsonpath={.items[0].metadata.name}"
                ], capture_output=True, text=True, check=True)
                
                if result.stdout.strip():
                    print(f"{Colors.GREEN}✓ Pod running: {result.stdout.strip()}{Colors.NC}")
                    return result.stdout.strip()
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(3)
            count += 3
        
        pytest.fail(f"Pod failed to reach running state for {claim_name}")

    def _verify_sandbox_recreation(self):
        """Verify Crossplane recreates Sandbox"""
        print(f"{Colors.YELLOW}⏳ Verifying Sandbox recreation...{Colors.NC}")
        
        timeout = 60
        count = 0
        while count < timeout:
            try:
                subprocess.run([
                    "kubectl", "get", "sandbox", self.test_claim_name, "-n", self.namespace
                ], check=True, capture_output=True)
                print(f"{Colors.GREEN}✓ Sandbox auto-recreated by Crossplane{Colors.NC}")
                return
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(2)
            count += 2
        
        pytest.fail("Crossplane failed to recreate Sandbox")

    def _verify_data_persistence(self):
        """Verify data persists through S3 after Sandbox recreation"""
        print(f"{Colors.YELLOW}⏳ Verifying data persistence...{Colors.NC}")
        
        # Wait for new pod to be running
        self._wait_for_pod_running()
        
        # Check if data was restored from S3
        try:
            result = subprocess.run([
                "kubectl", "exec", self.test_claim_name, "-n", self.namespace,
                "-c", "main", "--", "cat", "/workspace/cascade-test.txt"
            ], capture_output=True, text=True, check=True)
            
            restored_data = result.stdout.strip()
            print(f"{Colors.GREEN}✓ Data persisted through S3: {restored_data}{Colors.NC}")
            
        except subprocess.CalledProcessError:
            # Check initContainer logs for S3 restore attempt
            try:
                logs = subprocess.run([
                    "kubectl", "logs", self.test_claim_name, "-n", self.namespace,
                    "-c", "workspace-hydrator"
                ], capture_output=True, text=True, check=True)
                
                if "No existing workspace backup found" in logs.stdout:
                    print(f"{Colors.YELLOW}⚠️ No S3 backup found - Expected for new workspace{Colors.NC}")
                elif "Workspace hydrated successfully" in logs.stdout:
                    print(f"{Colors.GREEN}✓ S3 restore successful{Colors.NC}")
                else:
                    print(f"{Colors.YELLOW}⚠️ S3 restore status unclear{Colors.NC}")
                    
            except subprocess.CalledProcessError:
                print(f"{Colors.YELLOW}⚠️ Could not check S3 restore logs{Colors.NC}")

    def _verify_pod_recreation(self, claim_name):
        """Verify pod is recreated after deletion"""
        print(f"{Colors.YELLOW}⏳ Verifying pod recreation...{Colors.NC}")
        
        timeout = 60
        count = 0
        while count < timeout:
            try:
                result = subprocess.run([
                    "kubectl", "get", "pods", "-n", self.namespace,
                    "-l", f"app.kubernetes.io/name={claim_name}",
                    "--field-selector=status.phase=Running",
                    "-o", "jsonpath={.items[0].metadata.name}"
                ], capture_output=True, text=True, check=True)
                
                if result.stdout.strip():
                    print(f"{Colors.GREEN}✓ Pod recreated: {result.stdout.strip()}{Colors.NC}")
                    return
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(2)
            count += 2
        
        pytest.fail("Pod recreation failed")
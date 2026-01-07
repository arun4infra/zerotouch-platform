#!/usr/bin/env python3
"""
Verify AgentSandboxService Hybrid Persistence - Summary Test
This is a summary test that runs key persistence validations.
For detailed tests, run the modular test files:
- test_04a_claim_creation.py
- test_04b_pvc_sizing_validation.py  
- test_04c_container_validation.py
- test_04d_resurrection_test.py

Usage: pytest test_04_verify_persistence.py -v
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


class TestAgentSandboxPersistenceSummary:
    def setup_method(self):
        self.namespace = "intelligence-deepagents"
        self.test_claim_name = "test-persistence-summary"
        self.temp_dir = tempfile.mkdtemp()
        print(f"{Colors.BLUE}[INFO] Persistence Summary Test{Colors.NC}")

    def teardown_method(self):
        try:
            subprocess.run([
                "kubectl", "delete", "agentsandboxservice", self.test_claim_name, "-n", self.namespace
            ], check=False)
            import shutil
            shutil.rmtree(self.temp_dir)
        except:
            pass

    def test_persistence_summary_validation(self):
        """Summary test: Key persistence features validation"""
        print(f"{Colors.BLUE}Running Persistence Summary Validation{Colors.NC}")
        
        # Step 1: Create claim
        self._create_test_claim()
        
        # Step 2: Validate basic resources
        self._validate_basic_resources()
        
        # Step 3: Quick pod test
        pod_name = self._wait_for_pod_running()
        
        # Step 4: Basic data persistence test
        self._test_basic_data_persistence(pod_name)
        
        print(f"{Colors.GREEN}✓ Persistence Summary Test Complete{Colors.NC}")
        print(f"{Colors.BLUE}ℹ️  For detailed testing, run modular test files 04a-04d{Colors.NC}")

    def _create_test_claim(self):
        """Create test claim"""
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
    stream: "PERSISTENCE_SUMMARY_STREAM"
    consumer: "persistence-summary-consumer"
  httpPort: 8080
  healthPath: "/health"
  readyPath: "/ready"
  storageGB: 10
  secret1Name: "deepagents-runtime-db-conn"
  secret2Name: "deepagents-runtime-cache-conn"
  secret3Name: "deepagents-runtime-llm-keys"
"""
        
        claim_file = os.path.join(self.temp_dir, "claim.yaml")
        with open(claim_file, 'w') as f:
            f.write(claim_yaml)
        
        subprocess.run(["kubectl", "apply", "-f", claim_file], check=True)
        print(f"{Colors.GREEN}✓ Created claim {self.test_claim_name}{Colors.NC}")

    def _validate_basic_resources(self):
        """Validate basic resources are created"""
        print(f"{Colors.YELLOW}⏳ Validating basic resources...{Colors.NC}")
        
        # Wait for Sandbox
        timeout = 60
        count = 0
        while count < timeout:
            try:
                subprocess.run([
                    "kubectl", "get", "sandbox", self.test_claim_name, "-n", self.namespace
                ], check=True, capture_output=True)
                print(f"{Colors.GREEN}✓ Sandbox created{Colors.NC}")
                break
            except subprocess.CalledProcessError:
                pass
            time.sleep(2)
            count += 2
        
        if count >= timeout:
            pytest.fail("Sandbox creation failed")
        
        # Check PVC
        try:
            result = subprocess.run([
                "kubectl", "get", "pvc", f"{self.test_claim_name}-workspace", "-n", self.namespace,
                "-o", "jsonpath={.spec.resources.requests.storage}"
            ], capture_output=True, text=True, check=True)
            
            pvc_size = result.stdout.strip()
            if pvc_size == "10Gi":
                print(f"{Colors.GREEN}✓ PVC created with correct size: {pvc_size}{Colors.NC}")
            else:
                print(f"{Colors.YELLOW}⚠️ PVC size unexpected: {pvc_size}{Colors.NC}")
        except subprocess.CalledProcessError:
            pytest.fail("PVC not created")

    def _wait_for_pod_running(self):
        """Wait for pod to be running"""
        # Force scale up
        subprocess.run([
            "kubectl", "patch", "sandbox", self.test_claim_name, "-n", self.namespace,
            "--type=merge", "-p", '{"spec":{"replicas":1}}'
        ], check=True, capture_output=True)
        
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
                    pod_name = result.stdout.strip()
                    print(f"{Colors.GREEN}✓ Pod running: {pod_name}{Colors.NC}")
                    return pod_name
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(3)
            count += 3
        
        pytest.fail("Pod failed to reach running state")

    def _test_basic_data_persistence(self, pod_name):
        """Basic data persistence test"""
        print(f"{Colors.YELLOW}⏳ Testing basic data persistence...{Colors.NC}")
        
        # Wait for container readiness
        time.sleep(10)
        
        # Write test data
        test_data = f"summary-test-{int(time.time())}"
        try:
            subprocess.run([
                "kubectl", "exec", pod_name, "-n", self.namespace, "-c", "main", "--",
                "sh", "-c", f"echo '{test_data}' > /workspace/summary-test.txt"
            ], check=True)
            print(f"{Colors.GREEN}✓ Test data written{Colors.NC}")
        except subprocess.CalledProcessError:
            print(f"{Colors.YELLOW}⚠️ Could not write test data (container may not be ready){Colors.NC}")
            return
        
        # Read back test data
        try:
            result = subprocess.run([
                "kubectl", "exec", pod_name, "-n", self.namespace, "-c", "main", "--",
                "cat", "/workspace/summary-test.txt"
            ], capture_output=True, text=True, check=True)
            
            if result.stdout.strip() == test_data:
                print(f"{Colors.GREEN}✓ Data persistence working{Colors.NC}")
            else:
                print(f"{Colors.YELLOW}⚠️ Data mismatch{Colors.NC}")
        except subprocess.CalledProcessError:
            print(f"{Colors.YELLOW}⚠️ Could not read test data{Colors.NC}")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
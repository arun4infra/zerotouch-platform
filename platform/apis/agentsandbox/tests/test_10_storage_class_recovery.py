#!/usr/bin/env python3
"""
Test Storage Class Corruption Recovery
Validates PVC recreation with correct storage class after corruption
Usage: pytest test_10_storage_class_recovery.py -v
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


class TestStorageClassRecovery:
    def setup_method(self):
        self.namespace = "intelligence-deepagents"
        self.test_claim_name = "test-storage-recovery"
        self.temp_dir = tempfile.mkdtemp()
        print(f"{Colors.BLUE}[INFO] Storage Class Recovery Test{Colors.NC}")

    def teardown_method(self):
        try:
            subprocess.run([
                "kubectl", "delete", "agentsandboxservice", self.test_claim_name, "-n", self.namespace
            ], check=False)
            import shutil
            shutil.rmtree(self.temp_dir)
        except:
            pass

    def test_storage_class_corruption_recovery(self):
        """Test: Storage class corruption and recovery"""
        print(f"{Colors.BLUE}Testing Storage Class Corruption Recovery{Colors.NC}")
        
        # Step 1: Create claim and verify correct storage class
        self._create_test_claim()
        self._wait_for_pod_running()
        self._verify_correct_storage_class()
        
        # Step 2: Simulate storage class corruption
        print(f"{Colors.YELLOW}⚠️ Simulating storage class corruption...{Colors.NC}")
        self._corrupt_storage_class()
        
        # Step 3: Delete PVC to trigger recreation
        subprocess.run([
            "kubectl", "delete", "pvc", f"{self.test_claim_name}-workspace", "-n", self.namespace
        ], check=True)
        
        # Step 4: Verify recreation with correct storage class
        self._verify_recreation_with_correct_storage_class()
        
        print(f"{Colors.GREEN}✓ Storage Class Recovery Test Complete{Colors.NC}")

    def test_pvc_size_validation_recovery(self):
        """Test: PVC size validation and recovery"""
        print(f"{Colors.BLUE}Testing PVC Size Validation Recovery{Colors.NC}")
        
        # Create claim with specific size
        self._create_test_claim("test-size-recovery")
        self._wait_for_pod_running("test-size-recovery")
        
        # Verify initial size is correct (5Gi from spec)
        result = subprocess.run([
            "kubectl", "get", "pvc", "test-size-recovery-workspace", "-n", self.namespace,
            "-o", "jsonpath={.spec.resources.requests.storage}"
        ], capture_output=True, text=True, check=True)
        
        initial_size = result.stdout.strip()
        if initial_size == "5Gi":
            print(f"{Colors.GREEN}✓ Initial PVC size correct: {initial_size}{Colors.NC}")
        else:
            pytest.fail(f"Initial PVC size incorrect: expected 5Gi, got {initial_size}")
        
        # Delete and recreate to test size consistency
        subprocess.run([
            "kubectl", "delete", "pvc", "test-size-recovery-workspace", "-n", self.namespace
        ], check=True)
        
        # Wait for recreation and verify size
        timeout = 60
        count = 0
        while count < timeout:
            try:
                result = subprocess.run([
                    "kubectl", "get", "pvc", "test-size-recovery-workspace", "-n", self.namespace,
                    "-o", "jsonpath={.spec.resources.requests.storage}"
                ], capture_output=True, text=True, check=True)
                
                recreated_size = result.stdout.strip()
                if recreated_size == "5Gi":
                    print(f"{Colors.GREEN}✓ Recreated PVC size correct: {recreated_size}{Colors.NC}")
                    break
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(2)
            count += 2
        
        if count >= timeout:
            pytest.fail("PVC size validation failed after recreation")
        
        # Cleanup
        subprocess.run([
            "kubectl", "delete", "agentsandboxservice", "test-size-recovery", "-n", self.namespace
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
    stream: "STORAGE_RECOVERY_STREAM"
    consumer: "storage-recovery-consumer"
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
                    return
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(3)
            count += 3
        
        pytest.fail(f"Pod failed to reach running state for {claim_name}")

    def _verify_correct_storage_class(self):
        """Verify PVC has correct storage class"""
        result = subprocess.run([
            "kubectl", "get", "pvc", f"{self.test_claim_name}-workspace", "-n", self.namespace,
            "-o", "jsonpath={.spec.storageClassName}"
        ], capture_output=True, text=True, check=True)
        
        storage_class = result.stdout.strip()
        if storage_class == "local-path":
            print(f"{Colors.GREEN}✓ Correct storage class: {storage_class}{Colors.NC}")
        else:
            pytest.fail(f"Incorrect storage class: expected local-path, got {storage_class}")

    def _corrupt_storage_class(self):
        """Simulate storage class corruption"""
        try:
            subprocess.run([
                "kubectl", "patch", "pvc", f"{self.test_claim_name}-workspace", "-n", self.namespace,
                "--type=merge", "-p", '{"spec":{"storageClassName":"invalid-storage-class"}}'
            ], check=False)  # May fail due to immutable field, that's expected
            print(f"{Colors.YELLOW}⚠️ Attempted storage class corruption{Colors.NC}")
        except subprocess.CalledProcessError:
            print(f"{Colors.YELLOW}⚠️ Storage class corruption blocked (immutable field){Colors.NC}")

    def _verify_recreation_with_correct_storage_class(self):
        """Verify PVC is recreated with correct storage class"""
        print(f"{Colors.YELLOW}⏳ Verifying recreation with correct storage class...{Colors.NC}")
        
        timeout = 60
        count = 0
        while count < timeout:
            try:
                result = subprocess.run([
                    "kubectl", "get", "pvc", f"{self.test_claim_name}-workspace", "-n", self.namespace,
                    "-o", "jsonpath={.spec.storageClassName}"
                ], capture_output=True, text=True, check=True)
                
                storage_class = result.stdout.strip()
                if storage_class == "local-path":
                    print(f"{Colors.GREEN}✓ PVC recreated with correct storage class: {storage_class}{Colors.NC}")
                    
                    # Also verify it's bound
                    result = subprocess.run([
                        "kubectl", "get", "pvc", f"{self.test_claim_name}-workspace", "-n", self.namespace,
                        "-o", "jsonpath={.status.phase}"
                    ], capture_output=True, text=True, check=True)
                    
                    if result.stdout.strip() == "Bound":
                        print(f"{Colors.GREEN}✓ PVC bound successfully{Colors.NC}")
                        return
                    
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(2)
            count += 2
        
        pytest.fail("PVC recreation with correct storage class failed")
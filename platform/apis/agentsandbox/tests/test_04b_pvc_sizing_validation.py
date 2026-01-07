#!/usr/bin/env python3
"""
Test PVC Sizing Validation
Validates PVC is created with correct size from storageGB field
Usage: pytest test_04b_pvc_sizing_validation.py -v
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


class TestPVCSizingValidation:
    def setup_method(self):
        self.namespace = "intelligence-deepagents"
        self.test_claim_name = "test-pvc-sizing"
        self.temp_dir = tempfile.mkdtemp()
        print(f"{Colors.BLUE}[INFO] PVC Sizing Validation Test{Colors.NC}")

    def teardown_method(self):
        try:
            subprocess.run([
                "kubectl", "delete", "agentsandboxservice", self.test_claim_name, "-n", self.namespace
            ], check=False)
            import shutil
            shutil.rmtree(self.temp_dir)
        except:
            pass

    def test_pvc_sizing_from_storage_gb(self):
        """Test: PVC sizing matches storageGB field"""
        print(f"{Colors.BLUE}Testing PVC Sizing from storageGB Field{Colors.NC}")
        
        # Test different storage sizes
        test_cases = [
            {"size": 5, "expected": "5Gi"},
            {"size": 20, "expected": "20Gi"},
            {"size": 100, "expected": "100Gi"}
        ]
        
        for i, case in enumerate(test_cases):
            claim_name = f"{self.test_claim_name}-{case['size']}gb"
            print(f"{Colors.BLUE}Testing {case['size']}GB -> {case['expected']}{Colors.NC}")
            
            # Create claim with specific size
            self._create_claim_with_size(claim_name, case['size'])
            
            # Validate PVC size
            self._validate_pvc_size(claim_name, case['expected'])
            
            # Cleanup
            subprocess.run([
                "kubectl", "delete", "agentsandboxservice", claim_name, "-n", self.namespace
            ], check=False)
            
            print(f"{Colors.GREEN}✓ Size test {case['size']}GB passed{Colors.NC}")
        
        print(f"{Colors.GREEN}✓ PVC Sizing Validation Complete{Colors.NC}")

    def test_default_storage_size(self):
        """Test: Default storage size when storageGB not specified"""
        print(f"{Colors.BLUE}Testing Default Storage Size{Colors.NC}")
        
        # Create claim without storageGB field
        claim_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: {self.test_claim_name}-default
  namespace: {self.namespace}
spec:
  image: "ghcr.io/arun4infra/deepagents-runtime:sha-9d6cb0e"
  size: "micro"
  nats:
    url: "nats://nats-headless.nats.svc.cluster.local:4222"
    stream: "PVC_DEFAULT_STREAM"
    consumer: "pvc-default-consumer"
  httpPort: 8080
  healthPath: "/health"
  readyPath: "/ready"
  secret1Name: "deepagents-runtime-db-conn"
"""
        
        claim_file = os.path.join(self.temp_dir, "default-claim.yaml")
        with open(claim_file, 'w') as f:
            f.write(claim_yaml)
        
        subprocess.run(["kubectl", "apply", "-f", claim_file], check=True)
        
        # Wait for PVC creation
        self._wait_for_pvc(f"{self.test_claim_name}-default")
        
        # Check default size (should be 10Gi from composition default)
        result = subprocess.run([
            "kubectl", "get", "pvc", f"{self.test_claim_name}-default-workspace", "-n", self.namespace,
            "-o", "jsonpath={.spec.resources.requests.storage}"
        ], capture_output=True, text=True, check=True)
        
        default_size = result.stdout.strip()
        expected_default = "10Gi"  # From composition default
        
        if default_size == expected_default:
            print(f"{Colors.GREEN}✓ Default PVC size correct: {default_size}{Colors.NC}")
        else:
            pytest.fail(f"Default PVC size incorrect: expected {expected_default}, got {default_size}")
        
        # Cleanup
        subprocess.run([
            "kubectl", "delete", "agentsandboxservice", f"{self.test_claim_name}-default", "-n", self.namespace
        ], check=False)

    def _create_claim_with_size(self, claim_name, storage_gb):
        """Create claim with specific storage size"""
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
    stream: "PVC_SIZING_STREAM"
    consumer: "pvc-sizing-consumer"
  httpPort: 8080
  healthPath: "/health"
  readyPath: "/ready"
  storageGB: {storage_gb}
  secret1Name: "deepagents-runtime-db-conn"
"""
        
        claim_file = os.path.join(self.temp_dir, f"{claim_name}.yaml")
        with open(claim_file, 'w') as f:
            f.write(claim_yaml)
        
        subprocess.run(["kubectl", "apply", "-f", claim_file], check=True)

    def _wait_for_pvc(self, claim_name):
        """Wait for PVC to be created and bound"""
        timeout = 60
        count = 0
        while count < timeout:
            try:
                result = subprocess.run([
                    "kubectl", "get", "pvc", f"{claim_name}-workspace", "-n", self.namespace,
                    "-o", "jsonpath={.status.phase}"
                ], capture_output=True, text=True, check=True)
                
                if result.stdout.strip() == "Bound":
                    return
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(2)
            count += 2
        
        pytest.fail(f"PVC for {claim_name} failed to bind")

    def _validate_pvc_size(self, claim_name, expected_size):
        """Validate PVC has expected size"""
        # Wait for PVC creation
        self._wait_for_pvc(claim_name)
        
        # Check size
        result = subprocess.run([
            "kubectl", "get", "pvc", f"{claim_name}-workspace", "-n", self.namespace,
            "-o", "jsonpath={.spec.resources.requests.storage}"
        ], capture_output=True, text=True, check=True)
        
        actual_size = result.stdout.strip()
        
        if actual_size == expected_size:
            print(f"{Colors.GREEN}✓ PVC size correct: {actual_size}{Colors.NC}")
        else:
            pytest.fail(f"PVC size mismatch for {claim_name}: expected {expected_size}, got {actual_size}")
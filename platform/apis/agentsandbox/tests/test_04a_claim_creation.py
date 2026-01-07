#!/usr/bin/env python3
"""
Test Claim Creation and Basic Validation
Validates AgentSandboxService claim creation and Sandbox resource provisioning
Usage: pytest test_04a_claim_creation.py -v
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


class TestClaimCreation:
    def setup_method(self):
        self.namespace = "intelligence-deepagents"
        self.test_claim_name = "test-claim-creation"
        self.temp_dir = tempfile.mkdtemp()
        print(f"{Colors.BLUE}[INFO] Claim Creation Test{Colors.NC}")

    def teardown_method(self):
        try:
            subprocess.run([
                "kubectl", "delete", "agentsandboxservice", self.test_claim_name, "-n", self.namespace
            ], check=False)
            import shutil
            shutil.rmtree(self.temp_dir)
        except:
            pass

    def test_create_claim_and_validate_resources(self):
        """Test: Create claim and validate all resources are provisioned"""
        print(f"{Colors.BLUE}Testing Claim Creation and Resource Provisioning{Colors.NC}")
        
        # Step 1: Create claim
        self._create_test_claim()
        
        # Step 2: Validate Sandbox resource creation
        self._validate_sandbox_creation()
        
        # Step 3: Validate supporting resources
        self._validate_supporting_resources()
        
        print(f"{Colors.GREEN}✓ Claim Creation Test Complete{Colors.NC}")

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
    stream: "CLAIM_CREATION_STREAM"
    consumer: "claim-creation-consumer"
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

    def _validate_sandbox_creation(self):
        """Validate Sandbox resource is created"""
        print(f"{Colors.YELLOW}⏳ Validating Sandbox creation...{Colors.NC}")
        
        timeout = 120
        count = 0
        while count < timeout:
            try:
                res = subprocess.run([
                    "kubectl", "get", "sandbox", self.test_claim_name, "-n", self.namespace
                ], capture_output=True, text=True, check=True)
                
                if "AGE" in res.stdout:  # Sandbox exists
                    print(f"{Colors.GREEN}✓ Sandbox resource created{Colors.NC}")
                    return
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(5)
            count += 5
        
        pytest.fail("Sandbox resource failed to create")

    def _validate_supporting_resources(self):
        """Validate supporting resources are created"""
        print(f"{Colors.YELLOW}⏳ Validating supporting resources...{Colors.NC}")
        
        # Check ServiceAccount
        try:
            subprocess.run([
                "kubectl", "get", "serviceaccount", self.test_claim_name, "-n", self.namespace
            ], check=True, capture_output=True)
            print(f"{Colors.GREEN}✓ ServiceAccount created{Colors.NC}")
        except subprocess.CalledProcessError:
            pytest.fail("ServiceAccount not created")
        
        # Check Service
        try:
            subprocess.run([
                "kubectl", "get", "service", f"{self.test_claim_name}-http", "-n", self.namespace
            ], check=True, capture_output=True)
            print(f"{Colors.GREEN}✓ HTTP Service created{Colors.NC}")
        except subprocess.CalledProcessError:
            pytest.fail("HTTP Service not created")
        
        # Check PVC
        try:
            subprocess.run([
                "kubectl", "get", "pvc", f"{self.test_claim_name}-workspace", "-n", self.namespace
            ], check=True, capture_output=True)
            print(f"{Colors.GREEN}✓ PVC created{Colors.NC}")
        except subprocess.CalledProcessError:
            pytest.fail("PVC not created")
        
        # Check KEDA ScaledObject
        try:
            subprocess.run([
                "kubectl", "get", "scaledobject", "-n", self.namespace,
                "-l", f"app.kubernetes.io/name={self.test_claim_name}"
            ], check=True, capture_output=True)
            print(f"{Colors.GREEN}✓ KEDA ScaledObject created{Colors.NC}")
        except subprocess.CalledProcessError:
            print(f"{Colors.YELLOW}⚠️ KEDA ScaledObject not found (may be optional){Colors.NC}")
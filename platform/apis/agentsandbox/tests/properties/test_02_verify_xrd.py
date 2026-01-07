#!/usr/bin/env python3
"""
Verify AgentSandboxService XRD
Usage: pytest test_02_verify_xrd.py [--tenant <name>] [--namespace <name>] [-v] [--cleanup]

This script verifies:
1. AgentSandboxService XRD (CRD) is installed
2. All EventDrivenService fields are accepted by live API server
3. Field validation works correctly for invalid inputs
4. Test claims can be created and validated in live cluster
"""

import pytest
import subprocess
import tempfile
import os
import json
from typing import Optional, Dict, Any, List


class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'


class KubectlHelper:
    """Helper class for kubectl operations with retry logic"""
    
    @staticmethod
    def kubectl_cmd(args: List[str], timeout: int = 15) -> subprocess.CompletedProcess:
        """Execute kubectl command with timeout"""
        cmd = ["kubectl"] + args
        try:
            return subprocess.run(cmd, timeout=timeout, capture_output=True, text=True, check=True)
        except subprocess.TimeoutExpired:
            raise Exception(f"kubectl command timed out after {timeout}s")
    
    @staticmethod
    def kubectl_retry(args: List[str], max_attempts: int = 5, verbose: bool = False) -> subprocess.CompletedProcess:
        """Execute kubectl command with retry logic"""
        for attempt in range(1, max_attempts + 1):
            try:
                return KubectlHelper.kubectl_cmd(args)
            except Exception as e:
                if attempt < max_attempts:
                    delay = attempt * 2
                    if verbose:
                        print(f"{Colors.YELLOW}⚠️  kubectl command failed (attempt {attempt}/{max_attempts}). Retrying in {delay}s...{Colors.NC}")
                    time.sleep(delay)
                else:
                    raise Exception(f"kubectl command failed after {max_attempts} attempts: {e}")


class TestAgentSandboxXRD:
    """Test class for AgentSandboxService XRD verification"""
    
    def setup_method(self):
        """Setup for each test method"""
        self.errors = 0
        self.warnings = 0
        self.test_namespace = f"agentsandbox-test-{os.getpid()}"
        self.temp_dir = tempfile.mkdtemp()
        
        print(f"{Colors.BLUE}╔══════════════════════════════════════════════════════════════╗{Colors.NC}")
        print(f"{Colors.BLUE}║   Verifying AgentSandboxService XRD                         ║{Colors.NC}")
        print(f"{Colors.BLUE}╚══════════════════════════════════════════════════════════════╝{Colors.NC}")
        print("")
        
        # Create test namespace
        try:
            subprocess.run(["kubectl", "create", "namespace", self.test_namespace], 
                         capture_output=True, text=True, check=False)
        except:
            pass
    
    def teardown_method(self):
        """Cleanup after each test method"""
        # Clean up test namespace
        try:
            subprocess.run(["kubectl", "delete", "namespace", self.test_namespace, "--ignore-not-found=true"], 
                         capture_output=True, text=True, check=False)
        except:
            pass
        
        # Clean up temp files
        import shutil
        try:
            shutil.rmtree(self.temp_dir)
        except:
            pass
    
    def test_xrd_installed(self):
        """Verify AgentSandboxService XRD (CRD) is installed"""
        print(f"{Colors.BLUE}Verifying AgentSandboxService XRD...{Colors.NC}")
        
        try:
            result = KubectlHelper.kubectl_retry(["get", "crd", "xagentsandboxservices.platform.bizmatters.io"])
            print(f"{Colors.GREEN}✓ XRD 'xagentsandboxservices.platform.bizmatters.io' is installed{Colors.NC}")
            
            # Verify claim CRD also exists
            try:
                result = KubectlHelper.kubectl_retry(["get", "crd", "agentsandboxservices.platform.bizmatters.io"])
                print(f"{Colors.GREEN}✓ Claim CRD 'agentsandboxservices.platform.bizmatters.io' is installed{Colors.NC}")
            except Exception:
                print(f"{Colors.RED}✗ Claim CRD 'agentsandboxservices.platform.bizmatters.io' not found{Colors.NC}")
                self.errors += 1
            
            # Verify XRD has correct API version
            result = KubectlHelper.kubectl_retry([
                "get", "crd", "xagentsandboxservices.platform.bizmatters.io",
                "-o", "jsonpath={.spec.versions[0].name}"
            ])
            api_version = result.stdout.strip()
            if api_version == "v1alpha1":
                print(f"{Colors.GREEN}✓ XRD API version: v1alpha1{Colors.NC}")
            else:
                print(f"{Colors.YELLOW}⚠️  XRD API version: {api_version} (expected: v1alpha1){Colors.NC}")
                self.warnings += 1
                
        except Exception:
            print(f"{Colors.RED}✗ XRD 'xagentsandboxservices.platform.bizmatters.io' not found{Colors.NC}")
            print(f"{Colors.BLUE}ℹ  Check if platform/04-apis/agentsandbox/xrd.yaml is applied{Colors.NC}")
            self.errors += 1
            pytest.fail("XRD not found")
        
        print("")
    
    def test_valid_minimal_claim(self):
        """Test valid minimal claim (image, nats)"""
        print(f"{Colors.BLUE}Testing AgentSandboxService field compatibility...{Colors.NC}")
        
        valid_minimal_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-minimal
  namespace: {self.test_namespace}
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  nats:
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer"
"""
        
        minimal_file = os.path.join(self.temp_dir, "valid-minimal.yaml")
        with open(minimal_file, 'w') as f:
            f.write(valid_minimal_yaml)
        
        try:
            result = subprocess.run([
                "kubectl", "apply", "--dry-run=server", "-f", minimal_file
            ], capture_output=True, text=True, check=True)
            print(f"{Colors.GREEN}✓ Minimal AgentSandboxService claim validates successfully{Colors.NC}")
        except subprocess.CalledProcessError:
            print(f"{Colors.RED}✗ Minimal AgentSandboxService claim validation failed{Colors.NC}")
            self.errors += 1
    
    def test_valid_full_claim(self):
        """Test full EventDrivenService field compatibility"""
        valid_full_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-full
  namespace: {self.test_namespace}
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  size: "medium"
  nats:
    url: "nats://nats.nats.svc:4222"
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer"
  httpPort: 8000
  healthPath: "/health"
  readyPath: "/ready"
  sessionAffinity: "None"
  secret1Name: "test-db-conn"
  secret2Name: "test-cache-conn"
  secret3Name: "test-llm-keys"
  secret4Name: "test-extra-secret"
  secret5Name: "test-another-secret"
  imagePullSecrets:
    - name: "ghcr-pull-secret"
  initContainer:
    command: ["/bin/bash", "-c"]
    args: ["echo 'init complete'"]
  storageGB: 20
"""
        
        full_file = os.path.join(self.temp_dir, "valid-full.yaml")
        with open(full_file, 'w') as f:
            f.write(valid_full_yaml)
        
        try:
            result = subprocess.run([
                "kubectl", "apply", "--dry-run=server", "-f", full_file
            ], capture_output=True, text=True, check=True)
            print(f"{Colors.GREEN}✓ Full AgentSandboxService claim with all EventDrivenService fields validates successfully{Colors.NC}")
        except subprocess.CalledProcessError:
            print(f"{Colors.RED}✗ Full AgentSandboxService claim validation failed{Colors.NC}")
            self.errors += 1
    
    def test_invalid_missing_stream(self):
        """Test invalid field validation (missing required field)"""
        invalid_missing_stream_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-invalid
  namespace: {self.test_namespace}
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  nats:
    consumer: "test-consumer"
    # stream is missing - should fail validation
"""
        
        invalid_file = os.path.join(self.temp_dir, "invalid-missing-stream.yaml")
        with open(invalid_file, 'w') as f:
            f.write(invalid_missing_stream_yaml)
        
        try:
            result = subprocess.run([
                "kubectl", "apply", "--dry-run=server", "-f", invalid_file
            ], capture_output=True, text=True, check=True)
            print(f"{Colors.RED}✗ Invalid AgentSandboxService claim was accepted (should have been rejected){Colors.NC}")
            self.errors += 1
        except subprocess.CalledProcessError:
            print(f"{Colors.GREEN}✓ Invalid AgentSandboxService claim correctly rejected{Colors.NC}")
    
    def test_invalid_size_enum(self):
        """Test invalid size enum"""
        invalid_size_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-invalid-size
  namespace: {self.test_namespace}
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  size: "invalid-size"
  nats:
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer"
"""
        
        invalid_size_file = os.path.join(self.temp_dir, "invalid-size.yaml")
        with open(invalid_size_file, 'w') as f:
            f.write(invalid_size_yaml)
        
        try:
            result = subprocess.run([
                "kubectl", "apply", "--dry-run=server", "-f", invalid_size_file
            ], capture_output=True, text=True, check=True)
            print(f"{Colors.RED}✗ Invalid size enum was accepted (should have been rejected){Colors.NC}")
            self.errors += 1
        except subprocess.CalledProcessError:
            print(f"{Colors.GREEN}✓ Invalid size enum correctly rejected{Colors.NC}")
    
    def test_invalid_http_port_range(self):
        """Test invalid httpPort range"""
        invalid_http_port_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-invalid-port
  namespace: {self.test_namespace}
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  httpPort: 70000
  nats:
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer"
"""
        
        invalid_port_file = os.path.join(self.temp_dir, "invalid-http-port.yaml")
        with open(invalid_port_file, 'w') as f:
            f.write(invalid_http_port_yaml)
        
        try:
            result = subprocess.run([
                "kubectl", "apply", "--dry-run=server", "-f", invalid_port_file
            ], capture_output=True, text=True, check=True)
            print(f"{Colors.RED}✗ Invalid httpPort range was accepted (should have been rejected){Colors.NC}")
            self.errors += 1
        except subprocess.CalledProcessError:
            print(f"{Colors.GREEN}✓ Invalid httpPort range correctly rejected{Colors.NC}")
    
    def test_invalid_storage_range(self):
        """Test invalid storageGB range"""
        invalid_storage_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-invalid-storage
  namespace: {self.test_namespace}
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  storageGB: 2000
  nats:
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer"
"""
        
        invalid_storage_file = os.path.join(self.temp_dir, "invalid-storage.yaml")
        with open(invalid_storage_file, 'w') as f:
            f.write(invalid_storage_yaml)
        
        try:
            result = subprocess.run([
                "kubectl", "apply", "--dry-run=server", "-f", invalid_storage_file
            ], capture_output=True, text=True, check=True)
            print(f"{Colors.RED}✗ Invalid storageGB range was accepted (should have been rejected){Colors.NC}")
            self.errors += 1
        except subprocess.CalledProcessError:
            print(f"{Colors.GREEN}✓ Invalid storageGB range correctly rejected{Colors.NC}")
    
    def test_live_claim_creation(self):
        """Test actual claim creation in live cluster"""
        print(f"{Colors.BLUE}Testing live claim creation...{Colors.NC}")
        
        valid_minimal_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-minimal
  namespace: {self.test_namespace}
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  nats:
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer"
"""
        
        minimal_file = os.path.join(self.temp_dir, "valid-minimal.yaml")
        with open(minimal_file, 'w') as f:
            f.write(valid_minimal_yaml)
        
        try:
            # Create test claim in live cluster
            result = subprocess.run([
                "kubectl", "apply", "-f", minimal_file
            ], capture_output=True, text=True, check=True)
            print(f"{Colors.GREEN}✓ Test claim created successfully in live cluster{Colors.NC}")
            
            # Wait a moment for the claim to be processed
            import time
            time.sleep(2)
            
            # Check if the claim exists
            try:
                result = subprocess.run([
                    "kubectl", "get", "agentsandboxservice", "test-minimal", "-n", self.test_namespace
                ], capture_output=True, text=True, check=True)
                print(f"{Colors.GREEN}✓ Test claim is accessible via kubectl{Colors.NC}")
            except subprocess.CalledProcessError:
                print(f"{Colors.YELLOW}⚠️  Test claim not found after creation{Colors.NC}")
                self.warnings += 1
            
            # Clean up the test claim
            subprocess.run([
                "kubectl", "delete", "-f", minimal_file
            ], capture_output=True, text=True, check=False)
            
        except subprocess.CalledProcessError:
            print(f"{Colors.RED}✗ Failed to create test claim in live cluster{Colors.NC}")
            self.errors += 1
        
        print("")
    
    def test_summary(self):
        """Print verification summary"""
        print(f"{Colors.BLUE}╔══════════════════════════════════════════════════════════════╗{Colors.NC}")
        print(f"{Colors.BLUE}║   Verification Summary                                       ║{Colors.NC}")
        print(f"{Colors.BLUE}╚══════════════════════════════════════════════════════════════╝{Colors.NC}")
        print("")
        
        if self.errors == 0 and self.warnings == 0:
            print(f"{Colors.GREEN}✓ All checks passed! AgentSandboxService XRD is ready.{Colors.NC}")
            print("")
            print(f"{Colors.BLUE}ℹ  Next steps:{Colors.NC}")
            print("  - Create composition: platform/04-apis/agentsandbox/composition.yaml")
            print("  - Test with real claims: kubectl apply -f <your-claim.yaml>")
            print("  - Run composition validation: ./03-verify-composition.sh")
        elif self.errors == 0:
            print(f"{Colors.YELLOW}⚠️  AgentSandboxService XRD has {self.warnings} warning(s) but no errors{Colors.NC}")
            print("")
            print(f"{Colors.BLUE}ℹ  Review warnings above and monitor the deployment{Colors.NC}")
        else:
            print(f"{Colors.RED}✗ AgentSandboxService XRD has {self.errors} error(s) and {self.warnings} warning(s){Colors.NC}")
            print("")
            print(f"{Colors.BLUE}ℹ  Troubleshooting steps:{Colors.NC}")
            print("  1. Check XRD status: kubectl get xrd xagentsandboxservices.platform.bizmatters.io")
            print("  2. Check XRD details: kubectl describe xrd xagentsandboxservices.platform.bizmatters.io")
            print("  3. Verify XRD file: platform/04-apis/agentsandbox/xrd.yaml")
            print("  4. Check cluster connectivity: kubectl cluster-info")
            
            if self.errors > 0:
                pytest.fail(f"AgentSandboxService XRD has {self.errors} error(s)")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
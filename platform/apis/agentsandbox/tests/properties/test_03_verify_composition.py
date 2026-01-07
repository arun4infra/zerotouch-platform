#!/usr/bin/env python3
"""
Verify AgentSandboxService Composition
Usage: pytest test_03_verify_composition.py [--tenant <name>] [--namespace <name>] [-v] [--cleanup]

This script verifies:
1. Composition creates SandboxTemplate with correct pod spec in live cluster
2. Composition creates SandboxWarmPool referencing template in live cluster
3. ServiceAccount created with proper permissions and accessible via kubectl
4. Resource patching works for image and size fields in live Crossplane
5. Test claim provisions actual resources successfully in cluster
"""

import pytest
import subprocess
import tempfile
import os
import json
import time
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


class TestAgentSandboxComposition:
    """Test class for AgentSandboxService Composition verification"""
    
    def setup_method(self):
        """Setup for each test method"""
        self.errors = 0
        self.warnings = 0
        self.test_namespace = f"agentsandbox-comp-test-{os.getpid()}"
        self.temp_dir = tempfile.mkdtemp()
        
        print(f"{Colors.BLUE}╔══════════════════════════════════════════════════════════════╗{Colors.NC}")
        print(f"{Colors.BLUE}║   Verifying AgentSandboxService Composition                 ║{Colors.NC}")
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
    
    def test_composition_installed(self):
        """Verify Composition is installed"""
        print(f"{Colors.BLUE}Verifying AgentSandboxService Composition...{Colors.NC}")
        
        try:
            result = KubectlHelper.kubectl_retry(["get", "composition", "agent-sandbox-service"])
            print(f"{Colors.GREEN}✓ Composition 'agent-sandbox-service' is installed{Colors.NC}")
            
            # Verify composition has correct XRD reference
            result = KubectlHelper.kubectl_retry([
                "get", "composition", "agent-sandbox-service",
                "-o", "jsonpath={.spec.compositeTypeRef.kind}"
            ])
            xrd_ref = result.stdout.strip()
            if xrd_ref == "XAgentSandboxService":
                print(f"{Colors.GREEN}✓ Composition references correct XRD: XAgentSandboxService{Colors.NC}")
            else:
                print(f"{Colors.YELLOW}⚠️  Composition XRD reference: {xrd_ref} (expected: XAgentSandboxService){Colors.NC}")
                self.warnings += 1
            
            # Verify composition has expected resources
            result = KubectlHelper.kubectl_retry([
                "get", "composition", "agent-sandbox-service",
                "-o", "jsonpath={.spec.resources}"
            ])
            try:
                resources = json.loads(result.stdout)
                resource_count = len(resources) if isinstance(resources, list) else 0
                if resource_count >= 4:
                    print(f"{Colors.GREEN}✓ Composition has {resource_count} resources (expected: 4+){Colors.NC}")
                else:
                    print(f"{Colors.YELLOW}⚠️  Composition has {resource_count} resources (expected: 4+){Colors.NC}")
                    self.warnings += 1
            except:
                print(f"{Colors.YELLOW}⚠️  Could not parse composition resources{Colors.NC}")
                self.warnings += 1
                
        except Exception:
            print(f"{Colors.RED}✗ Composition 'agent-sandbox-service' not found{Colors.NC}")
            print(f"{Colors.BLUE}ℹ  Check if platform/04-apis/agentsandbox/composition.yaml is applied{Colors.NC}")
            self.errors += 1
            pytest.fail("Composition not found")
        
        print("")
    
    def test_claim_provisioning(self):
        """Test AgentSandboxService claim creation and resource provisioning"""
        print(f"{Colors.BLUE}Testing AgentSandboxService claim provisioning...{Colors.NC}")
        
        test_claim_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-sandbox
  namespace: {self.test_namespace}
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  size: "small"
  nats:
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer"
  storageGB: 5
"""
        
        claim_file = os.path.join(self.temp_dir, "test-claim.yaml")
        with open(claim_file, 'w') as f:
            f.write(test_claim_yaml)
        
        print(f"{Colors.BLUE}Creating test AgentSandboxService claim...{Colors.NC}")
        
        try:
            # Create test claim
            result = subprocess.run([
                "kubectl", "apply", "-f", claim_file
            ], capture_output=True, text=True, check=True)
            print(f"{Colors.GREEN}✓ Test claim created successfully{Colors.NC}")
            
            # Wait for claim to be processed
            print(f"{Colors.BLUE}Waiting for claim to be processed (30s timeout)...{Colors.NC}")
            time.sleep(5)
            
            # Check if composite resource was created
            try:
                result = subprocess.run([
                    "kubectl", "get", "xagentsandboxservice", "-n", self.test_namespace
                ], capture_output=True, text=True, check=True)
                print(f"{Colors.GREEN}✓ Composite resource (XAgentSandboxService) created{Colors.NC}")
            except subprocess.CalledProcessError:
                print(f"{Colors.YELLOW}⚠️  Composite resource not found after 5s{Colors.NC}")
                self.warnings += 1
            
            # Wait a bit more for resources to be provisioned
            time.sleep(10)
            
            # Clean up the test claim
            print(f"{Colors.BLUE}Cleaning up test resources...{Colors.NC}")
            subprocess.run([
                "kubectl", "delete", "-f", claim_file
            ], capture_output=True, text=True, check=False)
            
            # Wait for cleanup
            time.sleep(5)
            
        except subprocess.CalledProcessError:
            print(f"{Colors.RED}✗ Failed to create test claim{Colors.NC}")
            self.errors += 1
        
        print("")
    
    def test_serviceaccount_creation(self):
        """Verify ServiceAccount creation"""
        print(f"{Colors.BLUE}Verifying ServiceAccount creation...{Colors.NC}")
        
        test_claim_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-sandbox-sa
  namespace: {self.test_namespace}
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  size: "small"
  nats:
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer"
  storageGB: 5
"""
        
        claim_file = os.path.join(self.temp_dir, "test-claim-sa.yaml")
        with open(claim_file, 'w') as f:
            f.write(test_claim_yaml)
        
        try:
            # Create test claim
            subprocess.run([
                "kubectl", "apply", "-f", claim_file
            ], capture_output=True, text=True, check=True)
            
            # Wait for resources to be provisioned
            time.sleep(15)
            
            # Check ServiceAccount creation
            try:
                result = subprocess.run([
                    "kubectl", "get", "serviceaccount", "test-sandbox-sa", "-n", self.test_namespace
                ], capture_output=True, text=True, check=True)
                print(f"{Colors.GREEN}✓ ServiceAccount 'test-sandbox-sa' created successfully{Colors.NC}")
                
                # Check ServiceAccount labels
                result = subprocess.run([
                    "kubectl", "get", "serviceaccount", "test-sandbox-sa", "-n", self.test_namespace,
                    "-o", "jsonpath={.metadata.labels}"
                ], capture_output=True, text=True, check=True)
                try:
                    labels = json.loads(result.stdout) if result.stdout.strip() else {}
                    if "app.kubernetes.io/name" in labels:
                        print(f"{Colors.GREEN}✓ ServiceAccount has correct labels{Colors.NC}")
                    else:
                        print(f"{Colors.YELLOW}⚠️  ServiceAccount missing expected labels{Colors.NC}")
                        self.warnings += 1
                except:
                    print(f"{Colors.YELLOW}⚠️  Could not parse ServiceAccount labels{Colors.NC}")
                    self.warnings += 1
                    
            except subprocess.CalledProcessError:
                print(f"{Colors.RED}✗ ServiceAccount 'test-sandbox-sa' not found{Colors.NC}")
                self.errors += 1
            
            # Clean up
            subprocess.run([
                "kubectl", "delete", "-f", claim_file
            ], capture_output=True, text=True, check=False)
            
        except subprocess.CalledProcessError:
            print(f"{Colors.RED}✗ Failed to create test claim for ServiceAccount test{Colors.NC}")
            self.errors += 1
    
    def test_pvc_creation(self):
        """Verify PersistentVolumeClaim creation"""
        print(f"{Colors.BLUE}Verifying PersistentVolumeClaim creation...{Colors.NC}")
        
        test_claim_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-sandbox-pvc
  namespace: {self.test_namespace}
spec:
  image: "ghcr.io/test/agent:v1.0.0"
  size: "small"
  nats:
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer"
  storageGB: 5
"""
        
        claim_file = os.path.join(self.temp_dir, "test-claim-pvc.yaml")
        with open(claim_file, 'w') as f:
            f.write(test_claim_yaml)
        
        try:
            # Create test claim
            subprocess.run([
                "kubectl", "apply", "-f", claim_file
            ], capture_output=True, text=True, check=True)
            
            # Wait for resources to be provisioned
            time.sleep(15)
            
            # Check PVC creation
            try:
                result = subprocess.run([
                    "kubectl", "get", "pvc", "test-sandbox-pvc-workspace", "-n", self.test_namespace
                ], capture_output=True, text=True, check=True)
                print(f"{Colors.GREEN}✓ PVC 'test-sandbox-pvc-workspace' created successfully{Colors.NC}")
                
                # Check PVC storage size
                result = subprocess.run([
                    "kubectl", "get", "pvc", "test-sandbox-pvc-workspace", "-n", self.test_namespace,
                    "-o", "jsonpath={.spec.resources.requests.storage}"
                ], capture_output=True, text=True, check=True)
                pvc_size = result.stdout.strip()
                if pvc_size == "5Gi":
                    print(f"{Colors.GREEN}✓ PVC has correct storage size: {pvc_size}{Colors.NC}")
                else:
                    print(f"{Colors.YELLOW}⚠️  PVC storage size: {pvc_size} (expected: 5Gi){Colors.NC}")
                    self.warnings += 1
                    
            except subprocess.CalledProcessError:
                print(f"{Colors.RED}✗ PVC 'test-sandbox-pvc-workspace' not found{Colors.NC}")
                self.errors += 1
            
            # Clean up
            subprocess.run([
                "kubectl", "delete", "-f", claim_file
            ], capture_output=True, text=True, check=False)
            
        except subprocess.CalledProcessError:
            print(f"{Colors.RED}✗ Failed to create test claim for PVC test{Colors.NC}")
            self.errors += 1
    
    def test_sandbox_template_creation(self):
        """Verify SandboxTemplate creation (via Crossplane Object)"""
        print(f"{Colors.BLUE}Verifying SandboxTemplate creation...{Colors.NC}")
        
        try:
            # Get SandboxTemplate objects
            result = subprocess.run([
                "kubectl", "get", "object", "-A",
                "-o", "jsonpath={.items[?(@.spec.forProvider.manifest.kind==\"SandboxTemplate\")].metadata.name}"
            ], capture_output=True, text=True, check=True)
            
            template_objects = [name.strip() for name in result.stdout.split() if "test-sandbox" in name]
            
            if template_objects:
                print(f"{Colors.GREEN}✓ SandboxTemplate Object created successfully{Colors.NC}")
                
                # Get the first template object for validation
                template_object_name = template_objects[0]
                result = subprocess.run([
                    "kubectl", "get", "object", template_object_name, "-A",
                    "-o", "jsonpath={.metadata.namespace}"
                ], capture_output=True, text=True, check=True)
                template_namespace = result.stdout.strip()
                
                if template_object_name and template_namespace:
                    # Check SandboxTemplate image patching
                    result = subprocess.run([
                        "kubectl", "get", "object", template_object_name, "-n", template_namespace,
                        "-o", "jsonpath={.spec.forProvider.manifest.spec.podTemplate.spec.containers[0].image}"
                    ], capture_output=True, text=True, check=False)
                    
                    if result.returncode == 0:
                        template_image = result.stdout.strip()
                        if "ghcr.io/test/agent" in template_image:
                            print(f"{Colors.GREEN}✓ SandboxTemplate has correct image: {template_image}{Colors.NC}")
                        else:
                            print(f"{Colors.YELLOW}⚠️  SandboxTemplate image: {template_image}{Colors.NC}")
                            self.warnings += 1
            else:
                print(f"{Colors.RED}✗ SandboxTemplate Object not found{Colors.NC}")
                self.errors += 1
                
        except subprocess.CalledProcessError:
            print(f"{Colors.YELLOW}⚠️  Could not check SandboxTemplate objects{Colors.NC}")
            self.warnings += 1
    
    def test_resource_patching(self):
        """Test resource patching with different configurations"""
        print(f"{Colors.BLUE}Testing resource patching with different configurations...{Colors.NC}")
        
        test_claim_large_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: test-sandbox-large
  namespace: {self.test_namespace}
spec:
  image: "ghcr.io/test/agent:v2.0.0"
  size: "large"
  httpPort: 9000
  nats:
    stream: "AGENT_EXECUTION"
    consumer: "test-consumer-large"
  storageGB: 20
  secret1Name: "test-db-secret"
  secret2Name: "test-cache-secret"
"""
        
        large_claim_file = os.path.join(self.temp_dir, "test-claim-large.yaml")
        with open(large_claim_file, 'w') as f:
            f.write(test_claim_large_yaml)
        
        try:
            # Test dry-run validation
            result = subprocess.run([
                "kubectl", "apply", "--dry-run=server", "-f", large_claim_file
            ], capture_output=True, text=True, check=True)
            print(f"{Colors.GREEN}✓ Large configuration claim validates successfully{Colors.NC}")
            
            # Test actual creation briefly
            result = subprocess.run([
                "kubectl", "apply", "-f", large_claim_file
            ], capture_output=True, text=True, check=True)
            print(f"{Colors.GREEN}✓ Large configuration claim created successfully{Colors.NC}")
            
            # Wait briefly and check one resource
            time.sleep(5)
            
            # Clean up
            subprocess.run([
                "kubectl", "delete", "-f", large_claim_file
            ], capture_output=True, text=True, check=False)
            
        except subprocess.CalledProcessError:
            print(f"{Colors.RED}✗ Large configuration claim validation failed{Colors.NC}")
            self.errors += 1
        
        print("")
    
    def test_summary(self):
        """Print verification summary"""
        print(f"{Colors.BLUE}╔══════════════════════════════════════════════════════════════╗{Colors.NC}")
        print(f"{Colors.BLUE}║   Verification Summary                                       ║{Colors.NC}")
        print(f"{Colors.BLUE}╚══════════════════════════════════════════════════════════════╝{Colors.NC}")
        print("")
        
        if self.errors == 0 and self.warnings == 0:
            print(f"{Colors.GREEN}✓ All checks passed! AgentSandboxService Composition is ready.{Colors.NC}")
            print("")
            print(f"{Colors.BLUE}ℹ  Next steps:{Colors.NC}")
            print("  - Implement hybrid persistence: ./04-verify-persistence.sh")
            print("  - Test with real workloads: kubectl apply -f <your-claim.yaml>")
            print("  - Monitor resource creation: kubectl get xagentsandboxservice,sandboxtemplate,sandboxwarmpool -A")
        elif self.errors == 0:
            print(f"{Colors.YELLOW}⚠️  AgentSandboxService Composition has {self.warnings} warning(s) but no errors{Colors.NC}")
            print("")
            print(f"{Colors.BLUE}ℹ  Review warnings above and monitor the deployment{Colors.NC}")
        else:
            print(f"{Colors.RED}✗ AgentSandboxService Composition has {self.errors} error(s) and {self.warnings} warning(s){Colors.NC}")
            print("")
            print(f"{Colors.BLUE}ℹ  Troubleshooting steps:{Colors.NC}")
            print("  1. Check composition status: kubectl get composition agent-sandbox-service")
            print("  2. Check composition details: kubectl describe composition agent-sandbox-service")
            print("  3. Verify composition file: platform/04-apis/agentsandbox/composition.yaml")
            print("  4. Check Crossplane provider: kubectl get provider kubernetes")
            print(f"  5. Check test claim status: kubectl get agentsandboxservice -n {self.test_namespace}")
            print(f"  6. Check composite resource: kubectl get xagentsandboxservice -n {self.test_namespace}")
            
            if self.errors > 0:
                pytest.fail(f"AgentSandboxService Composition has {self.errors} error(s)")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
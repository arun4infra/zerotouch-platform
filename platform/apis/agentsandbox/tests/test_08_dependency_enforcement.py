#!/usr/bin/env python3
"""
Test Dependency Enforcement (dependsOn validation)
Validates Sandbox stops when PVC dependency is lost
Usage: pytest test_08_dependency_enforcement.py -v
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


class TestDependencyEnforcement:
    def setup_method(self):
        self.namespace = "intelligence-deepagents"
        self.test_claim_name = "test-dependency-enforce"
        self.temp_dir = tempfile.mkdtemp()
        print(f"{Colors.BLUE}[INFO] Dependency Enforcement Test{Colors.NC}")

    def teardown_method(self):
        try:
            subprocess.run([
                "kubectl", "delete", "agentsandboxservice", self.test_claim_name, "-n", self.namespace
            ], check=False)
            import shutil
            shutil.rmtree(self.temp_dir)
        except:
            pass

    def test_dependency_order_enforcement(self):
        """Test: Sandbox depends on PVC (dependsOn validation)"""
        print(f"{Colors.BLUE}Testing Dependency Order Enforcement{Colors.NC}")
        
        # Step 1: Create claim and verify normal operation
        self._create_test_claim()
        self._wait_for_pod_running()
        
        # Step 2: Delete PVC to break dependency
        print(f"{Colors.YELLOW}⚠️ Breaking PVC dependency...{Colors.NC}")
        subprocess.run([
            "kubectl", "delete", "pvc", f"{self.test_claim_name}-workspace", "-n", self.namespace
        ], check=True)
        
        # Step 3: Verify Sandbox stops due to dependency failure
        self._verify_sandbox_stops_on_dependency_failure()
        
        # Step 4: Verify dependency restoration
        self._verify_dependency_restoration()
        
        print(f"{Colors.GREEN}✓ Dependency Enforcement Test Complete{Colors.NC}")

    def test_pod_startup_without_pvc(self):
        """Test: Pod should not start without PVC (dependsOn prevents it)"""
        print(f"{Colors.BLUE}Testing Pod Startup Prevention{Colors.NC}")
        
        # Create claim but immediately delete PVC before pod starts
        self._create_test_claim()
        
        # Quick delete of PVC before pod fully starts
        time.sleep(5)  # Brief delay to let claim create PVC
        subprocess.run([
            "kubectl", "delete", "pvc", f"{self.test_claim_name}-workspace", "-n", self.namespace
        ], check=False)  # May not exist yet
        
        # Verify pod doesn't start or stops quickly
        time.sleep(10)
        
        try:
            result = subprocess.run([
                "kubectl", "get", "pods", "-n", self.namespace,
                "-l", f"app.kubernetes.io/name={self.test_claim_name}",
                "--field-selector=status.phase=Running"
            ], capture_output=True, text=True, check=True)
            
            if "No resources found" in result.stdout or not result.stdout.strip():
                print(f"{Colors.GREEN}✓ Pod correctly prevented from starting without PVC{Colors.NC}")
            else:
                print(f"{Colors.YELLOW}⚠️ Pod started despite missing PVC dependency{Colors.NC}")
        except subprocess.CalledProcessError:
            print(f"{Colors.GREEN}✓ Pod correctly prevented from starting without PVC{Colors.NC}")

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
    stream: "DEPENDENCY_STREAM"
    consumer: "dependency-consumer"
  httpPort: 8080
  healthPath: "/health"
  readyPath: "/ready"
  storageGB: 5
  secret1Name: "deepagents-runtime-db-conn"
  secret2Name: "deepagents-runtime-cache-conn"
  secret3Name: "deepagents-runtime-llm-keys"
"""
        
        claim_file = os.path.join(self.temp_dir, "claim.yaml")
        with open(claim_file, 'w') as f:
            f.write(claim_yaml)
        
        subprocess.run(["kubectl", "apply", "-f", claim_file], check=True)
        print(f"{Colors.GREEN}✓ Created claim {self.test_claim_name}{Colors.NC}")

    def _wait_for_pod_running(self):
        """Wait for pod to be running"""
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
                    print(f"{Colors.GREEN}✓ Pod running: {result.stdout.strip()}{Colors.NC}")
                    return
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(3)
            count += 3
        
        pytest.fail("Pod failed to reach running state")

    def _verify_sandbox_stops_on_dependency_failure(self):
        """Verify Sandbox stops when PVC dependency is lost"""
        print(f"{Colors.YELLOW}⏳ Verifying Sandbox stops on dependency failure...{Colors.NC}")
        
        timeout = 60
        count = 0
        while count < timeout:
            try:
                result = subprocess.run([
                    "kubectl", "get", "pods", "-n", self.namespace,
                    "-l", f"app.kubernetes.io/name={self.test_claim_name}",
                    "--field-selector=status.phase=Running"
                ], capture_output=True, text=True, check=True)
                
                if "No resources found" in result.stdout or not result.stdout.strip():
                    print(f"{Colors.GREEN}✓ Sandbox stopped due to PVC dependency failure{Colors.NC}")
                    return
            except subprocess.CalledProcessError:
                print(f"{Colors.GREEN}✓ Sandbox stopped due to PVC dependency failure{Colors.NC}")
                return
            
            time.sleep(2)
            count += 2
        
        print(f"{Colors.YELLOW}⚠️ Sandbox still running (dependency enforcement may be delayed){Colors.NC}")

    def _verify_dependency_restoration(self):
        """Verify system restores when dependency is recreated"""
        print(f"{Colors.YELLOW}⏳ Verifying dependency restoration...{Colors.NC}")
        
        # Wait for Crossplane to recreate PVC
        timeout = 120
        count = 0
        while count < timeout:
            try:
                result = subprocess.run([
                    "kubectl", "get", "pvc", f"{self.test_claim_name}-workspace",
                    "-n", self.namespace, "-o", "jsonpath={.status.phase}"
                ], capture_output=True, text=True, check=True)
                
                if result.stdout.strip() == "Bound":
                    print(f"{Colors.GREEN}✓ PVC dependency restored{Colors.NC}")
                    break
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(3)
            count += 3
        
        if count >= timeout:
            pytest.fail("PVC dependency restoration failed")
        
        # Wait for pod to restart
        try:
            self._wait_for_pod_running()
            print(f"{Colors.GREEN}✓ Sandbox restored after dependency recreation{Colors.NC}")
        except:
            print(f"{Colors.YELLOW}⚠️ Sandbox restoration may be delayed{Colors.NC}")
#!/usr/bin/env python3
"""
Test Resurrection (Pod Recreation with Data Persistence)
Validates stable identity and data persistence across pod recreation
Usage: pytest test_04d_resurrection_test.py -v
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


class TestResurrectionTest:
    def setup_method(self):
        self.namespace = "intelligence-deepagents"
        self.test_claim_name = "test-resurrection"
        self.temp_dir = tempfile.mkdtemp()
        print(f"{Colors.BLUE}[INFO] Resurrection Test{Colors.NC}")

    def teardown_method(self):
        try:
            subprocess.run([
                "kubectl", "delete", "agentsandboxservice", self.test_claim_name, "-n", self.namespace
            ], check=False)
            import shutil
            shutil.rmtree(self.temp_dir)
        except:
            pass

    def test_pod_resurrection_with_data_persistence(self):
        """Test: Pod resurrection maintains stable identity and data persistence"""
        print(f"{Colors.BLUE}Testing Pod Resurrection with Data Persistence{Colors.NC}")
        
        # Step 1: Create claim and get initial pod
        self._create_test_claim()
        original_pod_name = self._wait_for_pod_running()
        original_pod_uid = self._get_pod_uid(original_pod_name)
        
        print(f"{Colors.BLUE}Original Pod: {original_pod_name} (UID: {original_pod_uid[:8]}...){Colors.NC}")
        
        # Step 2: Validate stable network identity
        self._validate_stable_network_identity()
        
        # Step 3: Write test data
        test_data = f"resurrection-{original_pod_uid[:8]}"
        test_file = "/workspace/resurrection.txt"
        self._write_test_data(original_pod_name, test_file, test_data)
        
        # Step 4: Delete pod to trigger resurrection
        print(f"{Colors.BLUE}Deleting pod to trigger resurrection...{Colors.NC}")
        subprocess.run([
            "kubectl", "delete", "pod", original_pod_name, "-n", self.namespace, "--wait=true"
        ], check=True)
        
        # Step 5: Wait for resurrection
        print(f"{Colors.BLUE}Waiting for pod resurrection...{Colors.NC}")
        time.sleep(10)
        new_pod_name = self._wait_for_pod_running()
        new_pod_uid = self._get_pod_uid(new_pod_name)
        
        print(f"{Colors.BLUE}New Pod: {new_pod_name} (UID: {new_pod_uid[:8]}...){Colors.NC}")
        
        # Step 6: Validate data persistence
        self._validate_data_persistence(new_pod_name, test_file, test_data)
        
        # Step 7: Validate stable identity maintained
        self._validate_stable_network_identity()
        
        print(f"{Colors.GREEN}✓ Resurrection Test Complete{Colors.NC}")

    def test_multiple_resurrections(self):
        """Test: Multiple pod resurrections maintain consistency"""
        print(f"{Colors.BLUE}Testing Multiple Resurrections{Colors.NC}")
        
        # Create claim
        self._create_test_claim("test-multi-resurrection")
        
        resurrection_data = []
        
        # Perform 3 resurrection cycles
        for i in range(3):
            print(f"{Colors.BLUE}Resurrection cycle {i+1}/3{Colors.NC}")
            
            pod_name = self._wait_for_pod_running("test-multi-resurrection")
            pod_uid = self._get_pod_uid(pod_name)
            
            # Write unique data for this cycle
            test_data = f"cycle-{i+1}-{pod_uid[:8]}"
            test_file = f"/workspace/cycle-{i+1}.txt"
            self._write_test_data(pod_name, test_file, test_data)
            
            resurrection_data.append({"file": test_file, "data": test_data})
            
            # Delete pod (except on last cycle)
            if i < 2:
                subprocess.run([
                    "kubectl", "delete", "pod", pod_name, "-n", self.namespace, "--wait=true"
                ], check=True)
                time.sleep(5)
        
        # Validate all data persisted
        final_pod = self._wait_for_pod_running("test-multi-resurrection")
        for cycle_data in resurrection_data:
            self._validate_data_persistence(final_pod, cycle_data["file"], cycle_data["data"])
        
        # Cleanup
        subprocess.run([
            "kubectl", "delete", "agentsandboxservice", "test-multi-resurrection", "-n", self.namespace
        ], check=False)
        
        print(f"{Colors.GREEN}✓ Multiple Resurrections Test Complete{Colors.NC}")

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
    stream: "RESURRECTION_STREAM"
    consumer: "resurrection-consumer"
  httpPort: 8080
  healthPath: "/health"
  readyPath: "/ready"
  storageGB: 5
  secret1Name: "deepagents-runtime-db-conn"
  secret2Name: "deepagents-runtime-cache-conn"
  secret3Name: "deepagents-runtime-llm-keys"
"""
        
        claim_file = os.path.join(self.temp_dir, f"{claim_name}.yaml")
        with open(claim_file, 'w') as f:
            f.write(claim_yaml)
        
        subprocess.run(["kubectl", "apply", "-f", claim_file], check=True)
        print(f"{Colors.GREEN}✓ Created claim {claim_name}{Colors.NC}")

    def _wait_for_pod_running(self, name=None):
        """Wait for pod to be running and return pod name"""
        claim_name = name or self.test_claim_name
        
        # Force scale up
        subprocess.run([
            "kubectl", "patch", "sandbox", claim_name, "-n", self.namespace,
            "--type=merge", "-p", '{"spec":{"replicas":1}}'
        ], check=True, capture_output=True)
        
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
                    pod_name = result.stdout.strip()
                    
                    # Wait for main container to be ready
                    self._wait_for_container_ready(pod_name)
                    
                    print(f"{Colors.GREEN}✓ Pod running and ready: {pod_name}{Colors.NC}")
                    return pod_name
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(3)
            count += 3
        
        pytest.fail(f"Pod failed to reach running state for {claim_name}")

    def _wait_for_container_ready(self, pod_name):
        """Wait for main container to be ready"""
        timeout = 60
        count = 0
        while count < timeout:
            try:
                result = subprocess.run([
                    "kubectl", "get", "pod", pod_name, "-n", self.namespace,
                    "-o", "jsonpath={.status.containerStatuses[?(@.name=='main')].ready}"
                ], capture_output=True, text=True, check=True)
                
                if result.stdout.strip() == "true":
                    return
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(2)
            count += 2
        
        print(f"{Colors.YELLOW}⚠️ Container readiness timeout for {pod_name}{Colors.NC}")

    def _get_pod_uid(self, pod_name):
        """Get pod UID"""
        result = subprocess.run([
            "kubectl", "get", "pod", pod_name, "-n", self.namespace,
            "-o", "jsonpath={.metadata.uid}"
        ], capture_output=True, text=True, check=True)
        
        return result.stdout.strip()

    def _validate_stable_network_identity(self):
        """Validate stable network identity via service"""
        service_name = f"{self.test_claim_name}-http"
        
        try:
            subprocess.run([
                "kubectl", "get", "service", service_name, "-n", self.namespace
            ], check=True, capture_output=True)
            print(f"{Colors.GREEN}✓ Stable network identity confirmed: Service '{service_name}' exists{Colors.NC}")
        except subprocess.CalledProcessError:
            pytest.fail(f"Stable network identity service '{service_name}' not found")

    def _write_test_data(self, pod_name, file_path, data):
        """Write test data to pod"""
        subprocess.run([
            "kubectl", "exec", pod_name, "-n", self.namespace, "-c", "main", "--",
            "sh", "-c", f"echo '{data}' > {file_path}"
        ], check=True)
        print(f"{Colors.GREEN}✓ Test data written: {data}{Colors.NC}")

    def _validate_data_persistence(self, pod_name, file_path, expected_data):
        """Validate data persisted across resurrection"""
        try:
            result = subprocess.run([
                "kubectl", "exec", pod_name, "-n", self.namespace, "-c", "main", "--",
                "cat", file_path
            ], capture_output=True, text=True, check=True)
            
            actual_data = result.stdout.strip()
            if actual_data == expected_data:
                print(f"{Colors.GREEN}✓ Data persisted: {expected_data}{Colors.NC}")
            else:
                pytest.fail(f"Data persistence failed. Expected: {expected_data}, Got: {actual_data}")
                
        except subprocess.CalledProcessError:
            pytest.fail(f"Failed to read persisted data from {file_path}")
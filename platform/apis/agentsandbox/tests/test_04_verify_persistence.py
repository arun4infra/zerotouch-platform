#!/usr/bin/env python3
"""
Verify AgentSandboxService Hybrid Persistence
Usage: pytest test_04_verify_persistence.py [--tenant <name>] [--namespace <name>] [-v] [--cleanup]
"""

import pytest
import subprocess
import tempfile
import os
import json
import time


class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'


@pytest.fixture
def test_config():
    return {
        "tenant_name": "deepagents-runtime",
        "namespace": "intelligence-deepagents",
        "test_claim_name": "test-persistence-sandbox"  # Fixed name for deterministic testing
    }


class TestAgentSandboxPersistence:
    def setup_method(self):
        self.errors = 0
        self.warnings = 0
        self.tenant_name = "deepagents-runtime"
        self.namespace = "intelligence-deepagents"
        self.test_claim_name = "test-persistence-sandbox"  # Fixed name for deterministic testing
        self.temp_dir = tempfile.mkdtemp()
        print(f"{Colors.BLUE}[INFO] Setup complete for {self.test_claim_name}{Colors.NC}")

    def teardown_method(self):
        # Don't delete during testing - let tests manage their own lifecycle
        try:
            import shutil
            shutil.rmtree(self.temp_dir)
        except:
            pass

    def test_create_test_claim(self):
        """Step 1: Create Test Claim with Persistence Configuration"""
        print(f"{Colors.BLUE}Step: 1. Creating Test Claim{Colors.NC}")
        
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
    stream: "TEST_PERSISTENCE_STREAM"
    consumer: "test-persistence-consumer"
  httpPort: 8080
  healthPath: "/health"
  readyPath: "/ready"
  storageGB: 10
  secret1Name: "deepagents-runtime-db-conn"
  secret2Name: "deepagents-runtime-cache-conn"
  secret3Name: "deepagents-runtime-llm-keys"
"""
        
        claim_file = os.path.join(self.temp_dir, "test-claim.yaml")
        with open(claim_file, 'w') as f:
            f.write(claim_yaml)
        
        subprocess.run(["kubectl", "apply", "-f", claim_file], check=True)
        print(f"{Colors.GREEN}✓ Created Claim {self.test_claim_name}{Colors.NC}")
        
        # Wait for Sandbox resource to be ready (KEDA may scale to 0)
        time.sleep(10)
        timeout = 120
        count = 0
        while count < timeout:
            try:
                res = subprocess.run(["kubectl", "get", "sandbox", self.test_claim_name, "-n", self.namespace], 
                                   capture_output=True, text=True, check=True)
                if "AGE" in res.stdout:  # Sandbox exists
                    print(f"{Colors.GREEN}✓ Sandbox Resource Created{Colors.NC}")
                    
                    # Check if scaled to 0 (expected for warm pool)
                    pod_res = subprocess.run(["kubectl", "get", "pods", "-n", self.namespace, 
                                            "-l", f"app.kubernetes.io/name={self.test_claim_name}"], 
                                           capture_output=True, text=True)
                    if "No resources found" in pod_res.stdout:
                        print(f"{Colors.YELLOW}⚠️ Sandbox scaled to 0 (Warm Pool behavior){Colors.NC}")
                    else:
                        print(f"{Colors.GREEN}✓ Pod Running{Colors.NC}")
                    return
            except subprocess.CalledProcessError:
                pass
            time.sleep(5)
            count += 5
        pytest.fail("Sandbox resource failed to create")

    def test_pvc_sizing_validation(self):
        """Step 2: Validate PVC Sizing from storageGB Field"""
        print(f"{Colors.BLUE}Step: 2. Validating PVC Sizing{Colors.NC}")
        
        try:
            # Get PVC details
            res = subprocess.run([
                "kubectl", "get", "pvc", f"{self.test_claim_name}-workspace", "-n", self.namespace,
                "-o", "jsonpath={.spec.resources.requests.storage}"
            ], capture_output=True, text=True, check=True)
            
            pvc_size = res.stdout.strip()
            expected_size = "10Gi"  # From storageGB: 10 in claim
            
            if pvc_size == expected_size:
                print(f"{Colors.GREEN}✓ PVC Size Correct: {pvc_size}{Colors.NC}")
            else:
                print(f"{Colors.RED}✗ PVC Size Mismatch: Expected {expected_size}, Got {pvc_size}{Colors.NC}")
                self.errors += 1
                pytest.fail(f"PVC sizing failed: expected {expected_size}, got {pvc_size}")
                
        except subprocess.CalledProcessError as e:
            pytest.fail(f"PVC validation failed: {e}")

    def _ensure_pod_running(self):
        """Helper to ensure pod is running for validation tests"""
        # Check if sandbox exists first
        try:
            subprocess.run([
                "kubectl", "get", "sandbox", self.test_claim_name, "-n", self.namespace
            ], check=True, capture_output=True)
        except subprocess.CalledProcessError:
            # Sandbox doesn't exist, need to create claim first
            pytest.fail(f"Sandbox {self.test_claim_name} not found. Run test_create_test_claim first.")
        
        # Force scale up by setting replicas to 1
        try:
            subprocess.run([
                "kubectl", "patch", "sandbox", self.test_claim_name, "-n", self.namespace,
                "--type=merge", "-p", '{"spec":{"replicas":1}}'
            ], check=True, capture_output=True)
            
            # Wait for pod to be running
            timeout = 120
            count = 0
            while count < timeout:
                res = subprocess.run([
                    "kubectl", "get", "pods", "-n", self.namespace,
                    "-l", f"app.kubernetes.io/name={self.test_claim_name}",
                    "--field-selector=status.phase=Running",
                    "-o", "jsonpath={.items[0].metadata.name}"
                ], capture_output=True, text=True)
                
                if res.stdout.strip():
                    return res.stdout.strip()
                    
                time.sleep(2)
                count += 2
            
            pytest.fail("Pod failed to start after forcing scale up")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Failed to force scale up: {e}")

    def test_initcontainer_validation(self):
        """Step 3: Validate InitContainer for S3 Workspace Hydration"""
        print(f"{Colors.BLUE}Step: 3. Validating InitContainer S3 Hydration{Colors.NC}")
        
        pod_name = self._ensure_pod_running()
        
        try:
            # Get Pod spec to check initContainers
            res = subprocess.run([
                "kubectl", "get", "pod", pod_name, "-n", self.namespace,
                "-o", "json"
            ], capture_output=True, text=True, check=True)
            
            pod_data = json.loads(res.stdout)
            init_containers = pod_data["spec"].get("initContainers", [])
            
            # Look for S3 hydration initContainer
            s3_init_found = False
            for container in init_containers:
                if "workspace-hydrator" in container["name"] or "s3" in container["name"].lower() or "hydrate" in container["name"].lower():
                    s3_init_found = True
                    print(f"{Colors.GREEN}✓ S3 InitContainer Found: {container['name']}{Colors.NC}")
                    
                    # Validate it has AWS credentials
                    env_from = container.get("envFrom", [])
                    has_aws_secret = any("aws" in str(env).lower() for env in env_from)
                    if has_aws_secret:
                        print(f"{Colors.GREEN}✓ AWS Credentials Configured{Colors.NC}")
                    else:
                        print(f"{Colors.YELLOW}⚠️ AWS Credentials Not Found in InitContainer{Colors.NC}")
                        self.warnings += 1
                    break
            
            if not s3_init_found:
                print(f"{Colors.RED}✗ S3 InitContainer Not Found{Colors.NC}")
                print(f"{Colors.BLUE}Available initContainers: {[c.get('name', 'unnamed') for c in init_containers]}{Colors.NC}")
                self.errors += 1
                pytest.fail("S3 hydration initContainer missing")
                
        except subprocess.CalledProcessError as e:
            pytest.fail(f"InitContainer validation failed: {e}")

    def test_sidecar_backup_validation(self):
        """Step 4: Validate Sidecar Container for Continuous S3 Backup"""
        print(f"{Colors.BLUE}Step: 4. Validating Sidecar S3 Backup{Colors.NC}")
        
        pod_name = self._ensure_pod_running()
        
        try:
            # Get Pod spec to check containers
            res = subprocess.run([
                "kubectl", "get", "pod", pod_name, "-n", self.namespace,
                "-o", "json"
            ], capture_output=True, text=True, check=True)
            
            pod_data = json.loads(res.stdout)
            containers = pod_data["spec"]["containers"]
            
            # Look for backup sidecar (should be more than just main container)
            if len(containers) < 2:
                print(f"{Colors.RED}✗ Sidecar Container Missing (only {len(containers)} containers){Colors.NC}")
                self.errors += 1
                pytest.fail("Backup sidecar container missing")
            
            # Find sidecar container (not main)
            sidecar_found = False
            for container in containers:
                if container["name"] != "main":
                    sidecar_found = True
                    print(f"{Colors.GREEN}✓ Sidecar Container Found: {container['name']}{Colors.NC}")
                    
                    # Validate it has AWS credentials
                    env_from = container.get("envFrom", [])
                    has_aws_secret = any("aws" in str(env).lower() for env in env_from)
                    if has_aws_secret:
                        print(f"{Colors.GREEN}✓ AWS Credentials Configured{Colors.NC}")
                    else:
                        print(f"{Colors.YELLOW}⚠️ AWS Credentials Not Found in Sidecar{Colors.NC}")
                        self.warnings += 1
                    break
            
            if not sidecar_found:
                print(f"{Colors.RED}✗ Backup Sidecar Not Found{Colors.NC}")
                self.errors += 1
                pytest.fail("Backup sidecar container missing")
                
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Sidecar validation failed: {e}")

    def test_prestop_hook_validation(self):
        """Step 5: Validate PreStop Hook for Final S3 Sync"""
        print(f"{Colors.BLUE}Step: 5. Validating PreStop Hook{Colors.NC}")
        
        pod_name = self._ensure_pod_running()
        
        try:
            # Get Pod spec to check lifecycle hooks
            res = subprocess.run([
                "kubectl", "get", "pod", pod_name, "-n", self.namespace,
                "-o", "json"
            ], capture_output=True, text=True, check=True)
            
            pod_data = json.loads(res.stdout)
            containers = pod_data["spec"]["containers"]
            
            # Check main container for preStop hook
            main_container = None
            for container in containers:
                if container["name"] == "main":
                    main_container = container
                    break
            
            if not main_container:
                pytest.fail("Main container not found")
            
            lifecycle = main_container.get("lifecycle", {})
            prestop = lifecycle.get("preStop", {})
            
            if prestop:
                print(f"{Colors.GREEN}✓ PreStop Hook Configured{Colors.NC}")
                
                # Check if it's an exec command (likely S3 sync)
                if "exec" in prestop:
                    command = prestop["exec"].get("command", [])
                    if any("s3" in str(cmd).lower() or "sync" in str(cmd).lower() for cmd in command):
                        print(f"{Colors.GREEN}✓ S3 Sync Command Found in PreStop{Colors.NC}")
                    else:
                        print(f"{Colors.YELLOW}⚠️ PreStop Command May Not Be S3 Sync{Colors.NC}")
                        self.warnings += 1
                else:
                    print(f"{Colors.YELLOW}⚠️ PreStop Hook Not Exec Type{Colors.NC}")
                    self.warnings += 1
            else:
                print(f"{Colors.RED}✗ PreStop Hook Not Found{Colors.NC}")
                self.errors += 1
                pytest.fail("PreStop hook missing")
                
        except subprocess.CalledProcessError as e:
            pytest.fail(f"PreStop hook validation failed: {e}")

    def test_resurrection(self):
        """Step 6: Perform Resurrection Test (Stable Identity & Data Persistence)"""
        print(f"{Colors.BLUE}Step: 6. Performing Resurrection Test{Colors.NC}")
        
        original_pod_name = self._ensure_pod_running()
        
        try:
            # Get Pod UID for tracking
            res = subprocess.run([
                "kubectl", "get", "pod", original_pod_name, "-n", self.namespace,
                "-o", "jsonpath={.metadata.uid}"
            ], capture_output=True, text=True, check=True)
            
            original_pod_uid = res.stdout.strip()
            print(f"{Colors.BLUE}Original Pod: {original_pod_name} (UID: {original_pod_uid[:8]}...){Colors.NC}")

            # Validate Stable Network Identity via Service Resolution
            print(f"{Colors.BLUE}Validating Stable Network Identity (Service Resolution)...{Colors.NC}")
            try:
                # Check Service Exists (composition creates {name}-http service)
                service_name = f"{self.test_claim_name}-http"
                subprocess.run([
                    "kubectl", "get", "service", service_name, "-n", self.namespace
                ], check=True, capture_output=True)
                print(f"{Colors.GREEN}✓ Stable Identity Confirmed: Service '{service_name}' exists{Colors.NC}")
                    
            except subprocess.CalledProcessError:
                print(f"{Colors.RED}✗ Stable Service '{service_name}' not found{Colors.NC}")
                self.errors += 1
                pytest.fail("Stable Network Identity Service missing")

            # Write Data for Persistence Test
            test_file = "/workspace/resurrection.txt"
            
            # Wait for main container to be ready before exec
            print(f"{Colors.BLUE}Ensuring main container is ready for exec...{Colors.NC}")
            timeout_exec = 60
            count_exec = 0
            
            while count_exec < timeout_exec:
                try:
                    # Check if 'main' container is ready
                    res_ready = subprocess.run([
                        "kubectl", "get", "pod", original_pod_name, "-n", self.namespace,
                        "-o", "jsonpath={.status.containerStatuses[?(@.name=='main')].ready}"
                    ], capture_output=True, text=True)
                    
                    if res_ready.stdout.strip() == "true":
                        break
                except:
                    pass
                
                time.sleep(2)
                count_exec += 2
            
            subprocess.run([
                "kubectl", "exec", original_pod_name, "-n", self.namespace, "-c", "main", "--",
                "sh", "-c", f"echo 'alive-{original_pod_uid[:8]}' > {test_file}"
            ], check=True)
            print(f"{Colors.GREEN}✓ Test Data Written{Colors.NC}")

            # Delete Pod to trigger recreation
            print(f"{Colors.BLUE}Deleting pod {original_pod_name}...{Colors.NC}")
            subprocess.run([
                "kubectl", "delete", "pod", original_pod_name, "-n", self.namespace, "--wait=true"
            ], check=True)

            # Wait for Recreation and force scale up
            print(f"{Colors.BLUE}Waiting for pod recreation...{Colors.NC}")
            time.sleep(10)
            new_pod_name = self._ensure_pod_running()
            
            # Get new pod UID
            res = subprocess.run([
                "kubectl", "get", "pod", new_pod_name, "-n", self.namespace,
                "-o", "jsonpath={.metadata.uid}"
            ], capture_output=True, text=True, check=True)
            
            new_pod_uid = res.stdout.strip()
            print(f"{Colors.BLUE}New Pod: {new_pod_name} (UID: {new_pod_uid[:8]}...){Colors.NC}")

            # Verify Data Persistence
            res = subprocess.run([
                "kubectl", "exec", new_pod_name, "-n", self.namespace, "-c", "main", "--", 
                "cat", test_file
            ], capture_output=True, text=True)
            
            expected_data = f"alive-{original_pod_uid[:8]}"
            if res.stdout.strip() == expected_data:
                print(f"{Colors.GREEN}✓ Data Persisted Across Pod Recreation{Colors.NC}")
            else:
                print(f"{Colors.RED}✗ Data Persistence Failed. Expected: {expected_data}, Got: {res.stdout.strip()}{Colors.NC}")
                self.errors += 1
                pytest.fail("Data Persistence Failed")

        except Exception as e:
            pytest.fail(f"Resurrection test failed: {e}")

    def test_cold_resume_valet_model(self):
        """Step 7: Test Cold Resume (Scorched Earth / Valet Model)"""
        print(f"{Colors.BLUE}Step: 7. Testing Cold Resume (Scorched Earth){Colors.NC}")
        
        claim_file = os.path.join(self.temp_dir, "test-claim.yaml")
        
        # Ensure pod is running for the test
        current_pod_name = self._ensure_pod_running()
        
        # 1. Write unique S3 proof data
        s3_proof_file = "/workspace/s3-proof.txt"
        s3_proof_data = f"valet-sandbox-{int(time.time())}"  # Use timestamp instead of PID
        print(f"{Colors.BLUE}Writing S3 proof data: {s3_proof_data}{Colors.NC}")
        subprocess.run([
            "kubectl", "exec", current_pod_name, "-n", self.namespace, "-c", "main", "--",
            "sh", "-c", f"echo '{s3_proof_data}' > {s3_proof_file}"
        ], check=True)

        # 2. Force Backup & Wait for Sidecar Sync
        print(f"{Colors.BLUE}Waiting 35s for Sidecar S3 sync...{Colors.NC}")
        time.sleep(35)

        # 3. Scorched Earth: Delete Claim (should delete PVC too)
        print(f"{Colors.BLUE}Simulating Cold State (Delete Claim)...{Colors.NC}")
        subprocess.run(["kubectl", "delete", "-f", claim_file], check=True)

        # Verify PVC is gone (deletionPolicy: Delete should clean it up)
        time.sleep(10)
        pvc_check = subprocess.run([
            "kubectl", "get", "pvc", f"{self.test_claim_name}-workspace", "-n", self.namespace
        ], capture_output=True)
        
        if pvc_check.returncode == 0:
            print(f"{Colors.YELLOW}⚠️ PVC still exists. Ensure deletionPolicy: Delete in composition.{Colors.NC}")
            self.warnings += 1

        # 4. Resume: Re-apply Claim
        print(f"{Colors.BLUE}Simulating Resume (Re-apply Claim)...{Colors.NC}")
        subprocess.run(["kubectl", "apply", "-f", claim_file], check=True)

        # 5. Wait for Ready and force scale up
        time.sleep(10)
        new_pod_name = self._ensure_pod_running()

        # 6. Verify Data Restored from S3
        # Give initContainer time to complete S3 restore
        print(f"{Colors.BLUE}Waiting for InitContainer S3 restore...{Colors.NC}")
        time.sleep(10)
        
        restore_check = subprocess.run([
            "kubectl", "exec", new_pod_name, "-n", self.namespace, "-c", "main", "--",
            "cat", s3_proof_file
        ], capture_output=True, text=True)
        
        if restore_check.returncode == 0 and restore_check.stdout.strip() == s3_proof_data:
            print(f"{Colors.GREEN}✓ [SUCCESS] Valet Model Validated: Data restored from S3{Colors.NC}")
        else:
            print(f"{Colors.RED}✗ S3 Restore failed. Expected: {s3_proof_data}, Got: {restore_check.stdout.strip()}{Colors.NC}")
            self.errors += 1
            pytest.fail("S3 Cold Resume failed")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
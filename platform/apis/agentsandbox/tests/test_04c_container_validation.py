#!/usr/bin/env python3
"""
Test Container Validation (InitContainer, Sidecar, PreStop Hook)
Validates S3 hydration, backup sidecar, and preStop hook configuration
Usage: pytest test_04c_container_validation.py -v
"""

import pytest
import subprocess
import tempfile
import os
import time
import json


class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'


class TestContainerValidation:
    def setup_method(self):
        self.namespace = "intelligence-deepagents"
        self.test_claim_name = "test-container-validation"
        self.temp_dir = tempfile.mkdtemp()
        print(f"{Colors.BLUE}[INFO] Container Validation Test{Colors.NC}")

    def teardown_method(self):
        try:
            subprocess.run([
                "kubectl", "delete", "agentsandboxservice", self.test_claim_name, "-n", self.namespace
            ], check=False)
            import shutil
            shutil.rmtree(self.temp_dir)
        except:
            pass

    def test_initcontainer_s3_hydration(self):
        """Test: InitContainer for S3 workspace hydration"""
        print(f"{Colors.BLUE}Testing InitContainer S3 Hydration{Colors.NC}")
        
        # Create claim and get pod
        self._create_test_claim()
        pod_name = self._wait_for_pod_running()
        
        # Validate InitContainer configuration
        pod_data = self._get_pod_spec(pod_name)
        init_containers = pod_data["spec"].get("initContainers", [])
        
        # Look for S3 hydration initContainer
        s3_init_found = False
        for container in init_containers:
            if "workspace-hydrator" in container["name"]:
                s3_init_found = True
                print(f"{Colors.GREEN}✓ S3 InitContainer found: {container['name']}{Colors.NC}")
                
                # Validate AWS credentials
                self._validate_aws_credentials(container, "InitContainer")
                
                # Validate S3 commands
                self._validate_s3_commands(container)
                break
        
        if not s3_init_found:
            available_containers = [c.get('name', 'unnamed') for c in init_containers]
            print(f"{Colors.RED}✗ S3 InitContainer not found{Colors.NC}")
            print(f"{Colors.BLUE}Available initContainers: {available_containers}{Colors.NC}")
            pytest.fail("S3 hydration initContainer missing")
        
        print(f"{Colors.GREEN}✓ InitContainer validation complete{Colors.NC}")

    def test_sidecar_backup_container(self):
        """Test: Sidecar container for continuous S3 backup"""
        print(f"{Colors.BLUE}Testing Sidecar S3 Backup{Colors.NC}")
        
        # Create claim and get pod
        self._create_test_claim("test-sidecar-backup")
        pod_name = self._wait_for_pod_running("test-sidecar-backup")
        
        # Validate sidecar configuration
        pod_data = self._get_pod_spec(pod_name)
        containers = pod_data["spec"]["containers"]
        
        # Should have more than just main container
        if len(containers) < 2:
            pytest.fail(f"Sidecar container missing (only {len(containers)} containers)")
        
        # Find backup sidecar (not main)
        sidecar_found = False
        for container in containers:
            if container["name"] != "main" and "backup" in container["name"]:
                sidecar_found = True
                print(f"{Colors.GREEN}✓ Backup sidecar found: {container['name']}{Colors.NC}")
                
                # Validate AWS credentials
                self._validate_aws_credentials(container, "Sidecar")
                
                # Validate backup commands
                self._validate_backup_commands(container)
                break
        
        if not sidecar_found:
            container_names = [c["name"] for c in containers]
            print(f"{Colors.RED}✗ Backup sidecar not found{Colors.NC}")
            print(f"{Colors.BLUE}Available containers: {container_names}{Colors.NC}")
            pytest.fail("Backup sidecar container missing")
        
        # Cleanup
        subprocess.run([
            "kubectl", "delete", "agentsandboxservice", "test-sidecar-backup", "-n", self.namespace
        ], check=False)
        
        print(f"{Colors.GREEN}✓ Sidecar validation complete{Colors.NC}")

    def test_prestop_hook_validation(self):
        """Test: PreStop hook for final S3 sync"""
        print(f"{Colors.BLUE}Testing PreStop Hook{Colors.NC}")
        
        # Create claim and get pod
        self._create_test_claim("test-prestop-hook")
        pod_name = self._wait_for_pod_running("test-prestop-hook")
        
        # Validate preStop hook configuration
        pod_data = self._get_pod_spec(pod_name)
        containers = pod_data["spec"]["containers"]
        
        # Find main container
        main_container = None
        for container in containers:
            if container["name"] == "main":
                main_container = container
                break
        
        if not main_container:
            pytest.fail("Main container not found")
        
        # Check lifecycle hooks
        lifecycle = main_container.get("lifecycle", {})
        prestop = lifecycle.get("preStop", {})
        
        if not prestop:
            pytest.fail("PreStop hook not configured")
        
        print(f"{Colors.GREEN}✓ PreStop hook configured{Colors.NC}")
        
        # Validate it's an exec command
        if "exec" not in prestop:
            pytest.fail("PreStop hook is not exec type")
        
        # Check for S3 sync commands
        command = prestop["exec"].get("command", [])
        command_str = " ".join(str(cmd) for cmd in command)
        
        if "s3" in command_str.lower() and ("sync" in command_str.lower() or "cp" in command_str.lower()):
            print(f"{Colors.GREEN}✓ S3 sync command found in PreStop hook{Colors.NC}")
        else:
            print(f"{Colors.YELLOW}⚠️ PreStop command may not be S3 sync: {command_str[:100]}...{Colors.NC}")
        
        # Cleanup
        subprocess.run([
            "kubectl", "delete", "agentsandboxservice", "test-prestop-hook", "-n", self.namespace
        ], check=False)
        
        print(f"{Colors.GREEN}✓ PreStop hook validation complete{Colors.NC}")

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
    stream: "CONTAINER_VALIDATION_STREAM"
    consumer: "container-validation-consumer"
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
                    print(f"{Colors.GREEN}✓ Pod running: {pod_name}{Colors.NC}")
                    return pod_name
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(3)
            count += 3
        
        pytest.fail(f"Pod failed to reach running state for {claim_name}")

    def _get_pod_spec(self, pod_name):
        """Get pod specification as JSON"""
        result = subprocess.run([
            "kubectl", "get", "pod", pod_name, "-n", self.namespace, "-o", "json"
        ], capture_output=True, text=True, check=True)
        
        return json.loads(result.stdout)

    def _validate_aws_credentials(self, container, container_type):
        """Validate container has AWS credentials configured"""
        env_from = container.get("envFrom", [])
        has_aws_secret = any("aws" in str(env).lower() for env in env_from)
        
        if has_aws_secret:
            print(f"{Colors.GREEN}✓ AWS credentials configured in {container_type}{Colors.NC}")
        else:
            print(f"{Colors.YELLOW}⚠️ AWS credentials not found in {container_type}{Colors.NC}")

    def _validate_s3_commands(self, container):
        """Validate container has S3 hydration commands"""
        command = container.get("command", [])
        command_str = " ".join(str(cmd) for cmd in command)
        
        if "s3" in command_str.lower() and ("ls" in command_str.lower() or "cp" in command_str.lower()):
            print(f"{Colors.GREEN}✓ S3 hydration commands found{Colors.NC}")
        else:
            print(f"{Colors.YELLOW}⚠️ S3 commands not clearly identified{Colors.NC}")

    def _validate_backup_commands(self, container):
        """Validate container has backup commands"""
        command = container.get("command", [])
        command_str = " ".join(str(cmd) for cmd in command)
        
        if "s3" in command_str.lower() and ("cp" in command_str.lower() or "sync" in command_str.lower()):
            print(f"{Colors.GREEN}✓ S3 backup commands found{Colors.NC}")
        else:
            print(f"{Colors.YELLOW}⚠️ Backup commands not clearly identified{Colors.NC}")
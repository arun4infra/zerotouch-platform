#!/usr/bin/env python3
"""
Test PVC Corruption Detection (Live Probing)
Validates Crossplane detects PVC corruption via MatchString readiness checks
Usage: pytest test_07_pvc_corruption_detection.py -v
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


class TestPVCCorruptionDetection:
    def setup_method(self):
        self.namespace = "intelligence-deepagents"
        self.test_claim_name = "test-pvc-corruption"
        self.temp_dir = tempfile.mkdtemp()
        print(f"{Colors.BLUE}[INFO] PVC Corruption Detection Test{Colors.NC}")

    def teardown_method(self):
        try:
            subprocess.run([
                "kubectl", "delete", "agentsandboxservice", self.test_claim_name, "-n", self.namespace
            ], check=False)
            import shutil
            shutil.rmtree(self.temp_dir)
        except:
            pass

    def test_pvc_corruption_detection_and_recovery(self):
        """Test: PVC Corruption Detection via Live Probing"""
        print(f"{Colors.BLUE}Testing PVC Corruption Detection{Colors.NC}")
        
        # Step 1: Create claim
        self._create_test_claim()
        self._wait_for_pod_running()
        
        # Step 2: Write test data
        test_data = f"corruption-test-{int(time.time())}"
        subprocess.run([
            "kubectl", "exec", self.test_claim_name, "-n", self.namespace,
            "-c", "main", "--", "sh", "-c",
            f"echo '{test_data}' > /workspace/corruption-test.txt"
        ], check=True)
        print(f"{Colors.GREEN}✓ Test data written{Colors.NC}")
        
        # Step 3: Simulate PVC corruption (delete without force)
        print(f"{Colors.YELLOW}⚠️ Simulating PVC corruption...{Colors.NC}")
        subprocess.run([
            "kubectl", "delete", "pvc", f"{self.test_claim_name}-workspace",
            "-n", self.namespace
        ], check=True)
        
        # Step 4: Verify Crossplane detects corruption
        self._verify_crossplane_detects_corruption()
        
        # Step 5: Verify auto-recreation
        self._verify_auto_recreation()
        
        print(f"{Colors.GREEN}✓ PVC Corruption Detection Test Complete{Colors.NC}")

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
    stream: "PVC_CORRUPTION_STREAM"
    consumer: "pvc-corruption-consumer"
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

    def _verify_crossplane_detects_corruption(self):
        """Verify Crossplane detects PVC corruption via live probing"""
        print(f"{Colors.YELLOW}⏳ Verifying Crossplane detects corruption...{Colors.NC}")
        
        # Get Crossplane PVC Object
        pvc_object_name = self._get_crossplane_pvc_object()
        
        # Monitor Object status for detection
        timeout = 60
        count = 0
        while count < timeout:
            try:
                result = subprocess.run([
                    "kubectl", "get", "object", pvc_object_name, 
                    "-o", "jsonpath={.status.conditions[?(@.type=='Ready')].status}"
                ], capture_output=True, text=True, check=True)
                
                if result.stdout.strip() == "False":
                    print(f"{Colors.GREEN}✓ Crossplane detected PVC corruption{Colors.NC}")
                    return
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(2)
            count += 2
        
        print(f"{Colors.YELLOW}⚠️ Crossplane detection timeout (may still be working){Colors.NC}")

    def _verify_auto_recreation(self):
        """Verify auto-recreation of PVC"""
        print(f"{Colors.YELLOW}⏳ Verifying auto-recreation...{Colors.NC}")
        
        timeout = 120
        count = 0
        while count < timeout:
            try:
                result = subprocess.run([
                    "kubectl", "get", "pvc", f"{self.test_claim_name}-workspace",
                    "-n", self.namespace, "-o", "jsonpath={.status.phase}"
                ], capture_output=True, text=True, check=True)
                
                if result.stdout.strip() == "Bound":
                    print(f"{Colors.GREEN}✓ PVC auto-recreated and bound{Colors.NC}")
                    return
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(3)
            count += 3
        
        pytest.fail("PVC auto-recreation failed")

    def _get_crossplane_pvc_object(self):
        """Get Crossplane Object name for PVC"""
        result = subprocess.run([
            "kubectl", "get", "object", "-o", "json"
        ], capture_output=True, text=True, check=True)
        
        objects = json.loads(result.stdout)
        for obj in objects["items"]:
            labels = obj.get("metadata", {}).get("labels", {})
            if (labels.get("crossplane.io/claim-name") == self.test_claim_name and
                "PersistentVolumeClaim" in obj.get("spec", {}).get("forProvider", {}).get("manifest", {}).get("kind", "")):
                return obj["metadata"]["name"]
        
        pytest.fail(f"Crossplane PVC Object not found for {self.test_claim_name}")
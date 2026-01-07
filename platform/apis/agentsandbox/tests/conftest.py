#!/usr/bin/env python3
"""
Common pytest fixtures for AgentSandbox tests
"""

import pytest
import subprocess
import tempfile
import os
import time
import json
from datetime import datetime, timezone
from typing import List, Optional


class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'


class KubectlUtility:
    """Enhanced kubectl utility with standardized operations"""
    
    @staticmethod
    def run(args: List[str], check: bool = True, timeout: int = 15) -> subprocess.CompletedProcess:
        """Execute kubectl command"""
        cmd = ["kubectl"] + args
        return subprocess.run(cmd, capture_output=True, text=True, check=check, timeout=timeout)
    
    @staticmethod
    def get_json(args: List[str]) -> dict:
        """Get kubectl output as JSON"""
        res = KubectlUtility.run(args + ["-o", "json"])
        return json.loads(res.stdout)
    
    @staticmethod
    def wait_for_pod(namespace: str, label: str, timeout: int = 120) -> str:
        """Standardized pod waiter used by persistence, e2e, and hibernation tests"""
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                pods = KubectlUtility.get_json(["get", "pods", "-n", namespace, "-l", label])
                if pods.get("items") and pods["items"][0]["status"]["phase"] == "Running":
                    # Ensure container is ready
                    container_statuses = pods["items"][0]["status"].get("containerStatuses", [])
                    if container_statuses and container_statuses[0].get("ready"):
                        pod_name = pods["items"][0]["metadata"]["name"]
                        print(f"{Colors.GREEN}✓ Pod running and ready: {pod_name}{Colors.NC}")
                        return pod_name
            except Exception:
                pass
            time.sleep(3)
        raise TimeoutError(f"Pod with label {label} failed to reach Running/Ready state")
    
    @staticmethod
    def wait_for_condition(resource_type: str, name: str, namespace: str, 
                          condition: str, status: str = "True", timeout: int = 120) -> bool:
        """Wait for any Kubernetes resource condition"""
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                result = KubectlUtility.get_json(["get", resource_type, name, "-n", namespace])
                conditions = result.get("status", {}).get("conditions", [])
                for cond in conditions:
                    if cond.get("type") == condition and cond.get("status") == status:
                        return True
            except Exception:
                pass
            time.sleep(3)
        return False


class KubectlHelper:
    """Legacy helper class for backward compatibility"""
    
    @staticmethod
    def kubectl_cmd(args: List[str], timeout: int = 15) -> subprocess.CompletedProcess:
        """Execute kubectl command with timeout"""
        return KubectlUtility.run(args, timeout=timeout)
    
    @staticmethod
    def kubectl_retry(args: List[str], max_attempts: int = 20, verbose: bool = False) -> subprocess.CompletedProcess:
        """Execute kubectl command with retry logic"""
        for attempt in range(1, max_attempts + 1):
            try:
                return KubectlHelper.kubectl_cmd(args, timeout=15)
            except Exception as e:
                if attempt < max_attempts:
                    delay = attempt * 2
                    if verbose:
                        print(f"{Colors.YELLOW}⚠️  kubectl command failed (attempt {attempt}/{max_attempts}). Retrying in {delay}s...{Colors.NC}")
                    time.sleep(delay)
                else:
                    raise Exception(f"kubectl command failed after {max_attempts} attempts: {e}")


@pytest.fixture(scope="session")
def k8s():
    """Provide enhanced kubectl utility"""
    return KubectlUtility()


@pytest.fixture
def nats_publisher(k8s):
    """Publishes messages to NATS streams to trigger KEDA scaling"""
    def _get_nats_box_pod(namespace: str = "nats") -> str:
        """Dynamically find nats-box pod"""
        result = k8s.get_json(["get", "pods", "-n", namespace, "-l", "app.kubernetes.io/component=nats-box"])
        if result.get("items"):
            return result["items"][0]["metadata"]["name"]
        raise RuntimeError("nats-box pod not found")
    
    def _publish(stream_name: str, subject: str, message: str, namespace: str = "nats"):
        """Publish message to NATS stream to trigger KEDA scaling"""
        print(f"{Colors.BLUE}📤 Publishing message to {stream_name}.{subject}: {message}{Colors.NC}")
        
        nats_box_pod = _get_nats_box_pod(namespace)
        nats_url = "nats://nats-headless.nats.svc.cluster.local:4222"
        
        k8s.run([
            "exec", "-n", namespace, nats_box_pod, "--",
            "nats", "pub", f"{stream_name}.{subject}", message, f"--server={nats_url}"
        ])
        print(f"{Colors.GREEN}✓ Message published to {stream_name}.{subject}{Colors.NC}")
        
        # Wait a moment for KEDA to detect the message
        time.sleep(5)
    
    return _publish


@pytest.fixture
def nats_stream(k8s):
    """Ensures a NATS stream exists for KEDA triggers"""
    created_streams = []
    
    def _get_nats_box_pod(namespace: str = "nats") -> str:
        """Dynamically find nats-box pod"""
        result = k8s.get_json(["get", "pods", "-n", namespace, "-l", "app.kubernetes.io/component=nats-box"])
        if result.get("items"):
            return result["items"][0]["metadata"]["name"]
        raise RuntimeError("nats-box pod not found")
    
    def _ensure(stream_name: str, namespace: str = "nats") -> str:
        """Ensure NATS stream exists"""
        print(f"{Colors.BLUE}📡 Ensuring NATS stream: {stream_name}{Colors.NC}")
        
        nats_box_pod = _get_nats_box_pod(namespace)
        nats_url = "nats://nats-headless.nats.svc.cluster.local:4222"
        
        # Check if stream already exists
        try:
            result = k8s.run([
                "exec", "-n", namespace, nats_box_pod, "--", 
                "nats", "stream", "info", stream_name, f"--server={nats_url}"
            ], check=False)
            if result.returncode == 0:
                print(f"{Colors.GREEN}✓ Stream {stream_name} already exists{Colors.NC}")
                return stream_name
        except Exception:
            pass
        
        # Create stream
        try:
            k8s.run([
                "exec", "-n", namespace, nats_box_pod, "--",
                "nats", "stream", "add", stream_name,
                f"--server={nats_url}",
                "--subjects", f"{stream_name}.*",
                "--retention", "limits",
                "--max-msgs=-1",
                "--max-age=1h",
                "--storage", "file",
                "--replicas", "1",
                "--discard", "old",
                "--defaults"
            ])
            created_streams.append(stream_name)
            print(f"{Colors.GREEN}✓ Created NATS stream: {stream_name}{Colors.NC}")
        except Exception as e:
            print(f"{Colors.YELLOW}⚠️  Could not create stream {stream_name}: {e}{Colors.NC}")
        
        return stream_name
    
    yield _ensure
    
    # Cleanup streams
    for stream in created_streams:
        try:
            nats_box_pod = _get_nats_box_pod()
            k8s.run([
                "exec", "-n", "nats", nats_box_pod, "--",
                "nats", "stream", "delete", stream, "--force"
            ], check=False)
        except Exception:
            pass


@pytest.fixture
def smart_cleanup(k8s):
    """Context-managed cleanup that handles cascading deletion logic"""
    cleanup_items = []
    
    def _register(resource_type: str, name: str, namespace: str):
        """Register a resource for cleanup"""
        cleanup_items.append((resource_type, name, namespace))
    
    yield _register
    
    # Cleanup registered resources
    for resource_type, name, namespace in cleanup_items:
        try:
            print(f"{Colors.BLUE}🧹 Cleaning up {resource_type}/{name} in {namespace}{Colors.NC}")
            k8s.run(["delete", resource_type, name, "-n", namespace, "--ignore-not-found=true"])
            
            # Wait for cascading deletion to complete
            if resource_type == "agentsandboxservice":
                # Wait for underlying sandbox and PVC to be deleted
                timeout = 60
                start_time = time.time()
                while time.time() - start_time < timeout:
                    try:
                        k8s.run(["get", "sandbox", name, "-n", namespace], check=True)
                        time.sleep(2)
                    except subprocess.CalledProcessError:
                        break
                        
            print(f"{Colors.GREEN}✓ Cleaned up {resource_type}/{name}{Colors.NC}")
        except Exception as e:
            print(f"{Colors.YELLOW}⚠️  Cleanup failed for {resource_type}/{name}: {e}{Colors.NC}")


@pytest.fixture
def colors():
    """Provide Colors class for test output formatting"""
    return Colors


@pytest.fixture
def kubectl_helper():
    """Provide KubectlHelper for kubectl operations (legacy)"""
    return KubectlHelper


@pytest.fixture
def test_namespace():
    """Create and cleanup test namespace"""
    namespace = f"agentsandbox-test-{os.getpid()}"
    
    # Create namespace
    try:
        subprocess.run(["kubectl", "create", "namespace", namespace], 
                     capture_output=True, text=True, check=False)
    except:
        pass
    
    yield namespace
    
    # Cleanup namespace
    try:
        subprocess.run(["kubectl", "delete", "namespace", namespace, "--ignore-not-found=true"], 
                     capture_output=True, text=True, check=False)
    except:
        pass


@pytest.fixture
def temp_dir():
    """Create and cleanup temporary directory"""
    temp_dir = tempfile.mkdtemp()
    yield temp_dir
    
    # Cleanup temp files
    import shutil
    try:
        shutil.rmtree(temp_dir)
    except:
        pass


@pytest.fixture
def test_counters():
    """Provide error and warning counters"""
    class Counters:
        def __init__(self):
            self.errors = 0
            self.warnings = 0
    
    return Counters()


@pytest.fixture
def tenant_config():
    """Provide default tenant configuration"""
    return {
        "tenant_name": "deepagents-runtime",
        "namespace": "intelligence-deepagents"
    }


@pytest.fixture
def claim_manager(k8s):
    """Manages AgentSandboxService claims with standardized YAML generation"""
    created_claims = []
    temp_dir = tempfile.mkdtemp()
    
    def _create_claim(name: str, namespace: str, **kwargs):
        """Create AgentSandboxService claim with standard configuration"""
        defaults = {
            "image": "python:3.12-slim",
            "size": "micro",
            "nats_url": "nats://nats-headless.nats.svc.cluster.local:4222",
            "nats_stream": "TEST_STREAM",
            "nats_consumer": "test-consumer",
            "httpPort": 8080,
            "healthPath": "/health",
            "readyPath": "/ready",
            "storageGB": 5,
            "secret1Name": "deepagents-runtime-db-conn",
            "secret2Name": "deepagents-runtime-cache-conn",
            "secret3Name": "deepagents-runtime-llm-keys"
        }
        defaults.update(kwargs)
        
        claim_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: {name}
  namespace: {namespace}
spec:
  image: "{defaults['image']}"
  size: "{defaults['size']}"
  nats:
    url: "{defaults['nats_url']}"
    stream: "{defaults['nats_stream']}"
    consumer: "{defaults['nats_consumer']}"
  httpPort: {defaults['httpPort']}
  healthPath: "{defaults['healthPath']}"
  readyPath: "{defaults['readyPath']}"
  storageGB: {defaults['storageGB']}
  secret1Name: "{defaults['secret1Name']}"
  secret2Name: "{defaults['secret2Name']}"
  secret3Name: "{defaults['secret3Name']}"
  command:
    - /bin/sh
    - -c
    - |
      cat > /tmp/server.py << 'EOF'
      import http.server
      import socketserver
      import json
      import os
      
      class HealthHandler(http.server.BaseHTTPRequestHandler):
          def do_GET(self):
              if self.path == '/health':
                  self.send_response(200)
                  self.send_header('Content-type', 'application/json')
                  self.end_headers()
                  self.wfile.write(json.dumps({{"status": "healthy"}}).encode())
              elif self.path == '/ready':
                  self.send_response(200)
                  self.send_header('Content-type', 'application/json')
                  self.end_headers()
                  self.wfile.write(json.dumps({{"status": "ready"}}).encode())
              else:
                  self.send_response(404)
                  self.end_headers()
      
      PORT = int(os.environ.get('PORT', 8080))
      with socketserver.TCPServer(("", PORT), HealthHandler) as httpd:
          print(f"Test server running on port {{PORT}}")
          httpd.serve_forever()
      EOF
      
      python3 /tmp/server.py
"""
        
        claim_file = os.path.join(temp_dir, f"{name}-claim.yaml")
        with open(claim_file, 'w') as f:
            f.write(claim_yaml)
        
        k8s.run(["apply", "-f", claim_file])
        created_claims.append((name, namespace))
        print(f"{Colors.GREEN}✓ Created claim {name} in {namespace}{Colors.NC}")
        return claim_file
    
    def _delete_claim(name: str, namespace: str):
        """Delete AgentSandboxService claim"""
        k8s.run(["delete", "agentsandboxservice", name, "-n", namespace, "--ignore-not-found=true"])
        print(f"{Colors.GREEN}✓ Deleted claim {name}{Colors.NC}")
    
    def _wait_for_cleanup(name: str, namespace: str, timeout: int = 60):
        """Wait for cascading deletion to complete"""
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                k8s.run(["get", "sandbox", name, "-n", namespace])
                time.sleep(2)
            except subprocess.CalledProcessError:
                print(f"{Colors.GREEN}✓ Sandbox {name} cleaned up{Colors.NC}")
                return True
        return False
    
    # Attach methods to the fixture
    _create_claim.delete = _delete_claim
    _create_claim.wait_cleanup = _wait_for_cleanup
    
    yield _create_claim
    
    # Cleanup all created claims - COMMENTED OUT FOR DEBUGGING
    # for name, namespace in created_claims:
    #     try:
    #         _delete_claim(name, namespace)
    #     except Exception as e:
    #         print(f"{Colors.YELLOW}⚠️  Cleanup failed for {name}: {e}{Colors.NC}")
    
    # Cleanup temp directory
    import shutil
    try:
        shutil.rmtree(temp_dir)
    except:
        pass


@pytest.fixture
def workspace_manager(k8s):
    """Manages workspace data operations for hibernation tests"""
    def _write_data(claim_name: str, namespace: str, filename: str, content: str):
        """Write test data to workspace"""
        k8s.run([
            "exec", claim_name, "-n", namespace, "-c", "main", "--", 
            "sh", "-c", f"echo '{content}' > /workspace/{filename}"
        ])
        print(f"{Colors.GREEN}✓ Written data to /workspace/{filename}: {content}{Colors.NC}")
        return content
    
    def _read_data(claim_name: str, namespace: str, filename: str) -> Optional[str]:
        """Read test data from workspace"""
        try:
            result = k8s.run([
                "exec", claim_name, "-n", namespace, "-c", "main", "--", 
                "cat", f"/workspace/{filename}"
            ])
            content = result.stdout.strip()
            print(f"{Colors.GREEN}✓ Read data from /workspace/{filename}: {content}{Colors.NC}")
            return content
        except subprocess.CalledProcessError:
            print(f"{Colors.YELLOW}⚠️  File /workspace/{filename} not found{Colors.NC}")
            return None
    
    def _verify_pvc_deleted(claim_name: str, namespace: str) -> bool:
        """Verify PVC is deleted (Cold State validation)"""
        try:
            k8s.run(["get", "pvc", f"{claim_name}-workspace", "-n", namespace])
            return False  # PVC still exists
        except subprocess.CalledProcessError:
            print(f"{Colors.GREEN}✓ PVC {claim_name}-workspace deleted - True Cold State{Colors.NC}")
            return True  # PVC deleted
    
    # Attach methods
    _write_data.read = _read_data
    _write_data.verify_pvc_deleted = _verify_pvc_deleted
    
    return _write_data


@pytest.fixture
def ttl_manager(k8s):
    """Manages TTL annotations and claim lifecycle for hibernation testing"""
    def _set_last_active(claim_name: str, namespace: str, timestamp: str = None):
        """Set last-active annotation (simulates Gateway heartbeat)"""
        if not timestamp:
            timestamp = datetime.now(timezone.utc).isoformat()
        
        k8s.run([
            "annotate", "agentsandboxservice", claim_name, 
            "-n", namespace,
            f"platform.bizmatters.io/last-active={timestamp}",
            "--overwrite"
        ])
        print(f"{Colors.GREEN}✓ TTL heartbeat set: {timestamp}{Colors.NC}")
        return timestamp
    
    def _get_last_active(claim_name: str, namespace: str) -> str:
        """Get last-active annotation"""
        result = k8s.run([
            "get", "agentsandboxservice", claim_name,
            "-n", namespace,
            "-o", "jsonpath={.metadata.annotations.platform\\.bizmatters\\.io/last-active}"
        ])
        return result.stdout.strip()
    
    def _wait_for_claim_ready(claim_name: str, namespace: str, timeout: int = 120) -> str:
        """Wait for claim to be ready and return pod name"""
        # Wait for pod to be running
        pod_name = k8s.wait_for_pod(namespace, f"app.kubernetes.io/name={claim_name}")
        
        # Wait for claim to be synced and ready
        k8s.wait_for_condition("agentsandboxservice", claim_name, namespace, "Synced")
        k8s.wait_for_condition("agentsandboxservice", claim_name, namespace, "Ready")
        
        print(f"{Colors.GREEN}✓ Claim {claim_name} ready with pod: {pod_name}{Colors.NC}")
        return pod_name
    
    def _verify_claim_deleted(claim_name: str, namespace: str) -> bool:
        """Verify claim is completely deleted"""
        try:
            k8s.run(["get", "agentsandboxservice", claim_name, "-n", namespace])
            return False  # Claim still exists
        except subprocess.CalledProcessError:
            print(f"{Colors.GREEN}✓ Claim {claim_name} successfully deleted{Colors.NC}")
            return True  # Claim deleted
    
    def _simulate_keda_scale_to_zero(claim_name: str, namespace: str):
        """Simulate KEDA scaling to 0 (Warm state)"""
        # Find the actual deployment created by Crossplane
        try:
            result = k8s.get_json(["get", "deployment", "-n", namespace, "-l", f"app.kubernetes.io/name={claim_name}"])
            if result.get("items"):
                deployment_name = result["items"][0]["metadata"]["name"]
                k8s.run(["scale", "deployment", deployment_name, "-n", namespace, "--replicas=0"])
                print(f"{Colors.GREEN}✓ KEDA scaled {deployment_name} to 0 replicas (Warm state){Colors.NC}")
                return deployment_name
        except Exception as e:
            print(f"{Colors.YELLOW}⚠️  Could not scale deployment: {e}{Colors.NC}")
            return None
    
    def _verify_warm_state(claim_name: str, namespace: str) -> bool:
        """Verify system is in Warm state (replicas=0, PVC exists)"""
        try:
            # Check deployment has 0 replicas
            result = k8s.get_json(["get", "deployment", "-n", namespace, "-l", f"app.kubernetes.io/name={claim_name}"])
            if result.get("items"):
                replicas = result["items"][0]["spec"]["replicas"]
                if replicas != 0:
                    return False
            
            # Check PVC still exists
            k8s.run(["get", "pvc", f"{claim_name}-workspace", "-n", namespace])
            print(f"{Colors.GREEN}✓ Warm State verified: replicas=0, PVC preserved{Colors.NC}")
            return True
        except Exception:
            return False
    
    def _verify_cold_state(claim_name: str, namespace: str) -> bool:
        """Verify system is in Cold state (claim deleted, PVC deleted)"""
        try:
            # Check claim is deleted
            k8s.run(["get", "agentsandboxservice", claim_name, "-n", namespace])
            return False  # Claim still exists
        except subprocess.CalledProcessError:
            pass
        
        try:
            # Check PVC is deleted
            k8s.run(["get", "pvc", f"{claim_name}-workspace", "-n", namespace])
            return False  # PVC still exists
        except subprocess.CalledProcessError:
            print(f"{Colors.GREEN}✓ Cold State verified: Claim deleted, PVC wiped{Colors.NC}")
            return True
    
    # Attach methods
    _set_last_active.get = _get_last_active
    _set_last_active.wait_ready = _wait_for_claim_ready
    _set_last_active.verify_deleted = _verify_claim_deleted
    _set_last_active.scale_to_zero = _simulate_keda_scale_to_zero
    _set_last_active.verify_warm = _verify_warm_state
    _set_last_active.verify_cold = _verify_cold_state
    
    return _set_last_active


@pytest.fixture
def test_claim_name():
    """Generate unique test claim name"""
    return f"test-hibernation-{os.getpid()}"
    
    # Attach methods
    _set_last_active.get = _get_last_active
    
@pytest.fixture
def test_claim_name():
    """Generate unique test claim name"""
    return f"test-hibernation-{os.getpid()}"
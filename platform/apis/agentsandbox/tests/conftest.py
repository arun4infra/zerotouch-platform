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
    
    @staticmethod
    def get_pod_uid(pod_name: str, namespace: str = "intelligence-deepagents") -> str:
        """Get pod UID"""
        result = KubectlUtility.run([
            "get", "pod", pod_name, "-n", namespace,
            "-o", "jsonpath={.metadata.uid}"
        ])
        return result.stdout.strip()
    
    @staticmethod
    def service_exists(service_name: str, namespace: str = "intelligence-deepagents") -> bool:
        """Check if service exists"""
        try:
            KubectlUtility.run(["get", "service", service_name, "-n", namespace])
            return True
        except subprocess.CalledProcessError:
            return False
    
    @staticmethod
    def exec_in_pod(pod_name: str, command: str, namespace: str = "intelligence-deepagents", container: str = "main") -> str:
        """Execute command in pod and return output"""
        result = KubectlUtility.run([
            "exec", pod_name, "-n", namespace, "-c", container, "--",
            "sh", "-c", command
        ])
        return result.stdout
    
    @staticmethod
    def delete_pod(pod_name: str, namespace: str = "intelligence-deepagents", wait: bool = False, force: bool = False):
        """Delete pod"""
        args = ["delete", "pod", pod_name, "-n", namespace]
        if force:
            args.extend(["--force", "--grace-period=0"])
        if wait:
            args.append("--wait=true")
        KubectlUtility.run(args)
    
    @staticmethod
    def delete_pods_by_label(label: str, namespace: str = "intelligence-deepagents", force: bool = False):
        """Delete pods by label"""
        args = ["delete", "pod", "-n", namespace, "-l", label]
        if force:
            args.extend(["--force", "--grace-period=0"])
        KubectlUtility.run(args, check=False)
    
    @staticmethod
    def wait_for_pod_termination(claim_name: str, namespace: str = "intelligence-deepagents", timeout: int = 30):
        """Wait for pod to be fully terminated"""
        count = 0
        while count < timeout:
            try:
                result = KubectlUtility.run([
                    "get", "pods", "-n", namespace,
                    "-l", f"app.kubernetes.io/name={claim_name}"
                ], check=False)
                
                if "No resources found" in result.stdout or result.returncode != 0:
                    break
                    
            except Exception:
                break
                
            time.sleep(2)
            count += 2
    
    @staticmethod
    def delete_pvc(pvc_name: str, namespace: str = "intelligence-deepagents", force: bool = False, ignore_not_found: bool = False):
        """Delete PVC"""
        args = ["delete", "pvc", pvc_name, "-n", namespace]
        if force:
            args.extend(["--force", "--grace-period=0"])
        if ignore_not_found:
            args.append("--ignore-not-found=true")
        KubectlUtility.run(args, check=not ignore_not_found)
    
    @staticmethod
    def wait_for_pvc_bound(pvc_name: str, namespace: str = "intelligence-deepagents", timeout: int = 120):
        """Wait for PVC to be bound"""
        count = 0
        while count < timeout:
            try:
                result = KubectlUtility.run([
                    "get", "pvc", pvc_name, "-n", namespace,
                    "-o", "jsonpath={.status.phase}"
                ])
                
                if result.stdout.strip() == "Bound":
                    return
                    
            except subprocess.CalledProcessError:
                pass
                
            time.sleep(3)
            count += 3
        
        raise TimeoutError(f"PVC {pvc_name} failed to reach Bound state")
    
    @staticmethod
    def get_running_pods(claim_name: str, namespace: str = "intelligence-deepagents") -> List[str]:
        """Get list of running pod names for claim"""
        try:
            result = KubectlUtility.run([
                "get", "pods", "-n", namespace,
                "-l", f"app.kubernetes.io/name={claim_name}",
                "--field-selector=status.phase=Running",
                "-o", "jsonpath={.items[*].metadata.name}"
            ])
            
            pod_names = result.stdout.strip().split()
            return [name for name in pod_names if name]
        except subprocess.CalledProcessError:
            return []
    
    @staticmethod
    def get_object_ready_status(object_name: str) -> str:
        """Get Crossplane Object ready status"""
        result = KubectlUtility.run([
            "get", "object", object_name, 
            "-o", "jsonpath={.status.conditions[?(@.type=='Ready')].status}"
        ])
        return result.stdout.strip()
    
    @staticmethod
    def get_crossplane_objects() -> dict:
        """Get all Crossplane objects"""
        return KubectlUtility.get_json(["get", "object"])
    
    @staticmethod
    def delete_sandbox(sandbox_name: str, namespace: str = "intelligence-deepagents"):
        """Delete Sandbox resource"""
        KubectlUtility.run(["delete", "sandbox", sandbox_name, "-n", namespace])
    
    @staticmethod
    def sandbox_exists(sandbox_name: str, namespace: str = "intelligence-deepagents") -> bool:
        """Check if Sandbox exists"""
        try:
            KubectlUtility.run(["get", "sandbox", sandbox_name, "-n", namespace])
            return True
        except subprocess.CalledProcessError:
            return False
    
    @staticmethod
    def get_container_logs(pod_name: str, container_name: str, namespace: str = "intelligence-deepagents") -> str:
        """Get container logs"""
        result = KubectlUtility.run([
            "logs", pod_name, "-n", namespace, "-c", container_name
        ])
        return result.stdout
    
    @staticmethod
    def get_pvc_size(pvc_name: str, namespace: str = "intelligence-deepagents") -> str:
        """Get PVC size"""
        result = KubectlUtility.run([
            "get", "pvc", pvc_name, "-n", namespace,
            "-o", "jsonpath={.spec.resources.requests.storage}"
        ])
        return result.stdout.strip()
    
    @staticmethod
    def get_pvc_storage_class(pvc_name: str, namespace: str = "intelligence-deepagents") -> str:
        """Get PVC storage class"""
        result = KubectlUtility.run([
            "get", "pvc", pvc_name, "-n", namespace,
            "-o", "jsonpath={.spec.storageClassName}"
        ])
        return result.stdout.strip()
    
    @staticmethod
    def patch_pvc_storage_class(pvc_name: str, storage_class: str, namespace: str = "intelligence-deepagents"):
        """Patch PVC storage class (may fail due to immutable field)"""
        KubectlUtility.run([
            "patch", "pvc", pvc_name, "-n", namespace,
            "--type=merge", "-p", f'{{"spec":{{"storageClassName":"{storage_class}"}}}}'
        ], check=False)


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
                k8s.run(["get", "agentsandboxservice", name, "-n", namespace])
                time.sleep(2)
            except subprocess.CalledProcessError:
                print(f"{Colors.GREEN}✓ Claim {name} cleaned up{Colors.NC}")
                return True
        return False
    
    # Attach methods to the fixture
    _create_claim.delete = _delete_claim
    _create_claim.wait_cleanup = _wait_for_cleanup
    
    yield _create_claim
    
    # # Cleanup all created claims (enable after testing complete)
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
def ready_claim_manager(claim_manager, nats_stream, nats_publisher, k8s):
    """Complete claim setup: create → NATS stream → trigger → pod ready"""
    def _create_ready_claim(name: str, stream_name: str, namespace: str = "intelligence-deepagents", **kwargs):
        """Create claim and ensure pod is ready for testing"""
        # Use existing claim_manager to create claim
        kwargs['nats_stream'] = stream_name
        claim_manager(name, namespace, **kwargs)
        
        # Use existing nats_stream fixture to ensure stream exists
        nats_stream(stream_name)
        
        # Wait for claim infrastructure to be ready
        k8s.wait_for_condition("agentsandboxservice", name, namespace, "Ready")
        print(f"{Colors.GREEN}✓ Claim {name} infrastructure ready{Colors.NC}")
        
        # Use existing nats_publisher to trigger KEDA scaling FIRST
        nats_publisher(stream_name, "trigger", f"test-message-{name}")
        
        # Wait for PVC to be bound (now pod will be scheduled due to KEDA)
        k8s.wait_for_pvc_bound(f"{name}-workspace", namespace)
        print(f"{Colors.GREEN}✓ PVC {name}-workspace bound and ready{Colors.NC}")
        
        # Use existing k8s.wait_for_pod to wait for pod readiness
        pod_name = k8s.wait_for_pod(namespace, f"app.kubernetes.io/name={name}")
        print(f"{Colors.GREEN}✓ Pod {pod_name} ready for testing{Colors.NC}")
        
        return pod_name
    
    # Reuse claim_manager's delete and cleanup methods
    _create_ready_claim.delete = claim_manager.delete
    _create_ready_claim.wait_cleanup = claim_manager.wait_cleanup
    
    return _create_ready_claim


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
    
    # Attach methods
    _write_data.read = _read_data
    
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
        
        # Wait for PVC to be completely deleted (not just Terminating)
        timeout = 60
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                result = k8s.run(["get", "pvc", f"{claim_name}-workspace", "-n", namespace], check=False)
                if result.returncode != 0:
                    # PVC not found - fully deleted
                    print(f"{Colors.GREEN}✓ Cold State verified: Claim deleted, PVC wiped{Colors.NC}")
                    return True
                # PVC still exists (might be Terminating), wait more
                time.sleep(2)
            except Exception:
                # PVC not found - fully deleted
                print(f"{Colors.GREEN}✓ Cold State verified: Claim deleted, PVC wiped{Colors.NC}")
                return True
        
        print(f"{Colors.YELLOW}⚠️  PVC still exists after {timeout}s timeout{Colors.NC}")
        return False
    
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
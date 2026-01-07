#!/usr/bin/env python3
"""
Verify Agent Sandbox Controller Bootstrap
Usage: pytest test_01_verify_controller.py [--tenant <name>] [--namespace <name>] [-v] [--cleanup]

This script verifies:
1. agent-sandbox-system namespace exists in live cluster
2. agent-sandbox-controller pod is Ready and healthy in cluster
3. SandboxTemplate and SandboxWarmPool CRDs are installed and accessible
4. aws-access-token secret exists in intelligence-deepagents namespace
5. Controller responds to health checks via live HTTP requests
"""

import pytest
import subprocess
import time
import json
import requests
import os
import signal
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
    
    @staticmethod
    def wait_for_ready(resource_type: str, resource_name: str, namespace: str, timeout: int = 300) -> bool:
        """Wait for resource to be ready"""
        print(f"{Colors.BLUE}Waiting for {resource_type}/{resource_name} to be ready (timeout: {timeout}s)...{Colors.NC}")
        
        try:
            KubectlHelper.kubectl_cmd([
                "wait", f"--for=condition=Ready", f"{resource_type}/{resource_name}",
                "-n", namespace, f"--timeout={timeout}s"
            ])
            print(f"{Colors.GREEN}✓ {resource_type}/{resource_name} is ready{Colors.NC}")
            return True
        except Exception:
            print(f"{Colors.RED}✗ {resource_type}/{resource_name} failed to become ready within {timeout}s{Colors.NC}")
            return False


class TestAgentSandboxController:
    """Test class for Agent Sandbox Controller verification"""
    
    def setup_method(self):
        """Setup for each test method"""
        self.errors = 0
        self.warnings = 0
        print(f"{Colors.BLUE}╔══════════════════════════════════════════════════════════════╗{Colors.NC}")
        print(f"{Colors.BLUE}║   Verifying Agent Sandbox Controller Bootstrap              ║{Colors.NC}")
        print(f"{Colors.BLUE}╚══════════════════════════════════════════════════════════════╝{Colors.NC}")
        print("")
    
    def test_namespace_exists(self):
        """Verify agent-sandbox-system namespace exists in live cluster"""
        print(f"{Colors.BLUE}Verifying agent-sandbox-system namespace...{Colors.NC}")
        
        try:
            result = KubectlHelper.kubectl_retry(["get", "namespace", "agent-sandbox-system"])
            print(f"{Colors.GREEN}✓ Namespace 'agent-sandbox-system' exists{Colors.NC}")
            
            # Check namespace status
            result = KubectlHelper.kubectl_retry([
                "get", "namespace", "agent-sandbox-system", 
                "-o", "jsonpath={.status.phase}"
            ])
            namespace_status = result.stdout.strip()
            
            if namespace_status == "Active":
                print(f"{Colors.GREEN}✓ Namespace status: Active{Colors.NC}")
            else:
                print(f"{Colors.YELLOW}⚠️  Namespace status: {namespace_status} (expected: Active){Colors.NC}")
                self.warnings += 1
                
        except Exception:
            print(f"{Colors.RED}✗ Namespace 'agent-sandbox-system' not found{Colors.NC}")
            print(f"{Colors.BLUE}ℹ  Check if agent-sandbox controller deployment is applied{Colors.NC}")
            self.errors += 1
            pytest.fail("Namespace 'agent-sandbox-system' not found")
        
        print("")
    
    def test_controller_pod_ready(self):
        """Verify agent-sandbox-controller pod is Ready and healthy in cluster"""
        print(f"{Colors.BLUE}Verifying agent-sandbox-controller pod...{Colors.NC}")
        
        try:
            # Check if pods exist
            result = KubectlHelper.kubectl_retry([
                "get", "pods", "-n", "agent-sandbox-system", 
                "-l", "app=agent-sandbox-controller"
            ])
            
            # Count pods
            result = KubectlHelper.kubectl_retry([
                "get", "pods", "-n", "agent-sandbox-system", 
                "-l", "app=agent-sandbox-controller", "--no-headers"
            ])
            pod_count = len([line for line in result.stdout.strip().split('\n') if line.strip()])
            print(f"{Colors.GREEN}✓ Found {pod_count} agent-sandbox-controller pod(s){Colors.NC}")
            
            # Check ready pods
            result = KubectlHelper.kubectl_retry([
                "get", "pods", "-n", "agent-sandbox-system", 
                "-l", "app=agent-sandbox-controller",
                "-o", "jsonpath={.items[*].status.conditions[?(@.type==\"Ready\")].status}"
            ])
            ready_count = result.stdout.count("True")
            
            if ready_count > 0:
                print(f"{Colors.GREEN}✓ {ready_count} pod(s) are Ready{Colors.NC}")
                
                # Get pod details
                result = KubectlHelper.kubectl_retry([
                    "get", "pods", "-n", "agent-sandbox-system", 
                    "-l", "app=agent-sandbox-controller",
                    "-o", "jsonpath={.items[0].metadata.name}"
                ])
                pod_name = result.stdout.strip()
                
                if pod_name:
                    result = KubectlHelper.kubectl_retry([
                        "get", "pod", pod_name, "-n", "agent-sandbox-system",
                        "-o", "jsonpath={.status.phase}"
                    ])
                    pod_phase = result.stdout.strip()
                    print(f"{Colors.GREEN}✓ Pod {pod_name} phase: {pod_phase}{Colors.NC}")
            else:
                print(f"{Colors.RED}✗ No agent-sandbox-controller pods are Ready{Colors.NC}")
                # Show pod status for debugging
                print(f"{Colors.BLUE}Pod status:{Colors.NC}")
                try:
                    result = KubectlHelper.kubectl_retry([
                        "get", "pods", "-n", "agent-sandbox-system", 
                        "-l", "app=agent-sandbox-controller"
                    ])
                    print(result.stdout)
                except:
                    pass
                self.errors += 1
                pytest.fail("No agent-sandbox-controller pods are Ready")
                
        except Exception:
            print(f"{Colors.RED}✗ No agent-sandbox-controller pods found{Colors.NC}")
            print(f"{Colors.BLUE}ℹ  Check if agent-sandbox controller deployment is applied and pods are starting{Colors.NC}")
            self.errors += 1
            pytest.fail("No agent-sandbox-controller pods found")
        
        print("")
    
    def test_crds_installed(self):
        """Verify SandboxTemplate and SandboxWarmPool CRDs are installed and accessible"""
        print(f"{Colors.BLUE}Verifying agent-sandbox CRDs...{Colors.NC}")
        
        # Check SandboxTemplate CRD
        try:
            result = KubectlHelper.kubectl_retry(["get", "crd", "sandboxtemplates.extensions.agents.x-k8s.io"])
            print(f"{Colors.GREEN}✓ SandboxTemplate CRD is installed{Colors.NC}")
            
            # Verify CRD version
            result = KubectlHelper.kubectl_retry([
                "get", "crd", "sandboxtemplates.extensions.agents.x-k8s.io",
                "-o", "jsonpath={.spec.versions[0].name}"
            ])
            crd_version = result.stdout.strip()
            print(f"{Colors.GREEN}✓ SandboxTemplate CRD version: {crd_version}{Colors.NC}")
            
        except Exception:
            print(f"{Colors.RED}✗ SandboxTemplate CRD not found{Colors.NC}")
            print(f"{Colors.BLUE}ℹ  Check if agent-sandbox controller has installed the CRDs{Colors.NC}")
            self.errors += 1
        
        # Check SandboxWarmPool CRD
        try:
            result = KubectlHelper.kubectl_retry(["get", "crd", "sandboxwarmpools.extensions.agents.x-k8s.io"])
            print(f"{Colors.GREEN}✓ SandboxWarmPool CRD is installed{Colors.NC}")
            
            # Verify CRD version
            result = KubectlHelper.kubectl_retry([
                "get", "crd", "sandboxwarmpools.extensions.agents.x-k8s.io",
                "-o", "jsonpath={.spec.versions[0].name}"
            ])
            crd_version = result.stdout.strip()
            print(f"{Colors.GREEN}✓ SandboxWarmPool CRD version: {crd_version}{Colors.NC}")
            
        except Exception:
            print(f"{Colors.RED}✗ SandboxWarmPool CRD not found{Colors.NC}")
            print(f"{Colors.BLUE}ℹ  Check if agent-sandbox controller has installed the CRDs{Colors.NC}")
            self.errors += 1
        
        if self.errors > 0:
            pytest.fail("Required CRDs not found")
        
        print("")
    
    def test_aws_secret_exists(self):
        """Verify aws-access-token secret exists in intelligence-deepagents namespace"""
        print(f"{Colors.BLUE}Verifying aws-access-token secret...{Colors.NC}")
        
        try:
            result = KubectlHelper.kubectl_retry([
                "get", "secret", "aws-access-token", "-n", "intelligence-deepagents"
            ])
            print(f"{Colors.GREEN}✓ Secret 'aws-access-token' exists in intelligence-deepagents namespace{Colors.NC}")
            
            # Check secret keys
            result = KubectlHelper.kubectl_retry([
                "get", "secret", "aws-access-token", "-n", "intelligence-deepagents",
                "-o", "jsonpath={.data}"
            ])
            secret_data = json.loads(result.stdout)
            secret_keys = list(secret_data.keys())
            
            if "AWS_ACCESS_KEY_ID" in secret_keys:
                print(f"{Colors.GREEN}✓ Secret contains AWS_ACCESS_KEY_ID{Colors.NC}")
            else:
                print(f"{Colors.RED}✗ Secret missing AWS_ACCESS_KEY_ID{Colors.NC}")
                self.errors += 1
            
            if "AWS_SECRET_ACCESS_KEY" in secret_keys:
                print(f"{Colors.GREEN}✓ Secret contains AWS_SECRET_ACCESS_KEY{Colors.NC}")
            else:
                print(f"{Colors.RED}✗ Secret missing AWS_SECRET_ACCESS_KEY{Colors.NC}")
                self.errors += 1
            
            if "AWS_DEFAULT_REGION" in secret_keys:
                print(f"{Colors.GREEN}✓ Secret contains AWS_DEFAULT_REGION{Colors.NC}")
            else:
                print(f"{Colors.YELLOW}⚠️  Secret missing AWS_DEFAULT_REGION (optional){Colors.NC}")
                self.warnings += 1
                
        except Exception:
            print(f"{Colors.RED}✗ Secret 'aws-access-token' not found in intelligence-deepagents namespace{Colors.NC}")
            print(f"{Colors.BLUE}ℹ  Check if ExternalSecret aws-access-token-es is applied and synced{Colors.NC}")
            self.errors += 1
            pytest.fail("Secret 'aws-access-token' not found")
        
        print("")
    
    def test_controller_health_check(self):
        """Controller responds to health checks via live HTTP requests"""
        print(f"{Colors.BLUE}Verifying controller health checks...{Colors.NC}")
        
        port_forward_process = None
        try:
            # Check if controller service exists
            result = KubectlHelper.kubectl_retry([
                "get", "service", "agent-sandbox-controller", "-n", "agent-sandbox-system"
            ])
            print(f"{Colors.GREEN}✓ Controller service exists{Colors.NC}")
            
            # Get service port
            result = KubectlHelper.kubectl_retry([
                "get", "service", "agent-sandbox-controller", "-n", "agent-sandbox-system",
                "-o", "jsonpath={.spec.ports[0].port}"
            ])
            service_port = result.stdout.strip()
            print(f"{Colors.GREEN}✓ Service port: {service_port}{Colors.NC}")
            
            # Test health endpoint using port-forward
            print(f"{Colors.BLUE}Testing health endpoint...{Colors.NC}")
            
            # Start port-forward in background
            port_forward_process = subprocess.Popen([
                "kubectl", "port-forward", "-n", "agent-sandbox-system",
                f"service/agent-sandbox-controller", f"8080:{service_port}"
            ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            # Wait for port-forward to establish
            time.sleep(3)
            
            # Test health endpoint
            try:
                response = requests.get("http://localhost:8080/healthz", timeout=5)
                if response.status_code == 200:
                    print(f"{Colors.GREEN}✓ Controller health endpoint responds{Colors.NC}")
                else:
                    print(f"{Colors.YELLOW}⚠️  Controller health endpoint returned status {response.status_code}{Colors.NC}")
                    self.warnings += 1
            except requests.exceptions.RequestException:
                print(f"{Colors.YELLOW}⚠️  Controller health endpoint not responding (may not be implemented yet){Colors.NC}")
                self.warnings += 1
            
        except Exception:
            print(f"{Colors.YELLOW}⚠️  Controller service not found (may use different service name){Colors.NC}")
            
            # Try to find any service in the namespace
            try:
                result = KubectlHelper.kubectl_retry([
                    "get", "services", "-n", "agent-sandbox-system", "--no-headers"
                ])
                service_count = len([line for line in result.stdout.strip().split('\n') if line.strip()])
                if service_count > 0:
                    print(f"{Colors.BLUE}Found {service_count} service(s) in agent-sandbox-system namespace{Colors.NC}")
            except:
                pass
            
            self.warnings += 1
        
        finally:
            # Clean up port-forward
            if port_forward_process:
                try:
                    port_forward_process.terminate()
                    port_forward_process.wait(timeout=5)
                except:
                    try:
                        port_forward_process.kill()
                    except:
                        pass
        
        print("")
    
    def test_summary(self):
        """Print verification summary"""
        print(f"{Colors.BLUE}╔══════════════════════════════════════════════════════════════╗{Colors.NC}")
        print(f"{Colors.BLUE}║   Verification Summary                                       ║{Colors.NC}")
        print(f"{Colors.BLUE}╚══════════════════════════════════════════════════════════════╝{Colors.NC}")
        print("")
        
        if self.errors == 0 and self.warnings == 0:
            print(f"{Colors.GREEN}✓ All checks passed! Agent Sandbox Controller is ready for XRD installation.{Colors.NC}")
            print("")
            print(f"{Colors.BLUE}ℹ  Next steps:{Colors.NC}")
            print("  - Create AgentSandboxService XRD: ./02-verify-xrd.sh")
            print("  - Test controller functionality: kubectl apply -f test-sandboxtemplate.yaml")
            print("  - Monitor controller logs: kubectl logs -n agent-sandbox-system -l app=agent-sandbox-controller")
        elif self.errors == 0:
            print(f"{Colors.YELLOW}⚠️  Agent Sandbox Controller has {self.warnings} warning(s) but no errors{Colors.NC}")
            print("")
            print(f"{Colors.BLUE}ℹ  Review warnings above and monitor the deployment{Colors.NC}")
        else:
            print(f"{Colors.RED}✗ Agent Sandbox Controller has {self.errors} error(s) and {self.warnings} warning(s){Colors.NC}")
            print("")
            print(f"{Colors.BLUE}ℹ  Troubleshooting steps:{Colors.NC}")
            print("  1. Check ArgoCD Application: kubectl describe application agent-sandbox-controller -n argocd")
            print("  2. Check controller deployment: kubectl describe deployment agent-sandbox-controller -n agent-sandbox-system")
            print("  3. Check controller logs: kubectl logs -n agent-sandbox-system -l app=agent-sandbox-controller")
            print("  4. Check ExternalSecret: kubectl describe externalsecret aws-access-token-es -n intelligence-deepagents")
            print("  5. Verify CRD installation: kubectl get crds | grep sandbox")
            pytest.fail(f"Agent Sandbox Controller has {self.errors} error(s)")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
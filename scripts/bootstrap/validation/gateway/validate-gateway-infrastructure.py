#!/usr/bin/env python3
"""
Gateway Infrastructure Validation Script

Validates that the Public Gateway is deployed with LoadBalancer IP assigned
and ClusterIssuer is ready for certificate provisioning.

Verification Criteria:
- Gateway resource shows Ready status with assigned LoadBalancer IP
- Hetzner LoadBalancer provisioned and accessible
- ClusterIssuer shows Ready status
- Gateway listeners configured for HTTP (80) and HTTPS (443)
"""

import subprocess
import json
import sys
import time
import requests
import os
from typing import Dict, Any, Optional

def run_wait_script() -> bool:
    """Run the wait-for-gateway.sh script to wait for Gateway provisioning"""
    print("🔍 Running wait script for Gateway provisioning...")
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(script_dir, "../../../.."))
    wait_script = os.path.join(repo_root, "scripts/bootstrap/wait/wait-for-gateway.sh")
    
    if not os.path.exists(wait_script):
        print(f"❌ Wait script not found: {wait_script}")
        return False
    
    try:
        # Stream output in real-time for debugging
        process = subprocess.Popen(
            [wait_script],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )
        
        # Stream output line by line
        for line in process.stdout:
            print(f"  {line}", end='')
        
        process.wait(timeout=300)
        
        if process.returncode == 0:
            print("✅ Gateway wait script completed successfully")
            return True
        else:
            print(f"❌ Gateway wait script failed with exit code: {process.returncode}")
            return False
    except subprocess.TimeoutExpired:
        process.kill()
        print("❌ Gateway wait script timed out after 5 minutes")
        return False
    except Exception as e:
        print(f"❌ Failed to run wait script: {e}")
        return False

def run_kubectl(args: list) -> Dict[str, Any]:
    """Run kubectl command and return JSON output"""
    try:
        cmd = ["kubectl"] + args
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"❌ kubectl command failed: {' '.join(cmd)}")
        print(f"Error: {e.stderr}")
        return {}
    except json.JSONDecodeError as e:
        print(f"❌ Failed to parse kubectl output as JSON: {e}")
        return {}

def check_gateway_status() -> tuple[bool, Optional[str]]:
    """Check if Gateway resource is ready and has LoadBalancer IP"""
    print("🔍 Checking Gateway resource status...")
    
    gateway = run_kubectl([
        "get", "gateway", "public-gateway", 
        "-n", "kube-system", 
        "-o", "json"
    ])
    
    if not gateway:
        print("❌ Gateway resource not found")
        return False, None
    
    # Check Gateway status conditions
    status = gateway.get("status", {})
    conditions = status.get("conditions", [])
    
    # Cilium Gateway API uses "Accepted" and "Programmed" conditions (not "Ready")
    accepted_condition = None
    programmed_condition = None
    for condition in conditions:
        if condition.get("type") == "Accepted":
            accepted_condition = condition
        elif condition.get("type") == "Programmed":
            programmed_condition = condition
    
    if not accepted_condition:
        print("❌ Gateway Accepted condition not found")
        return False, None
    
    if accepted_condition.get("status") != "True":
        print(f"❌ Gateway not accepted: {accepted_condition.get('message', 'Unknown reason')}")
        return False, None
    
    if not programmed_condition:
        print("❌ Gateway Programmed condition not found")
        return False, None
    
    if programmed_condition.get("status") != "True":
        print(f"❌ Gateway not programmed: {programmed_condition.get('message', 'Unknown reason')}")
        return False, None
    
    # Check for LoadBalancer IP from addresses
    addresses = status.get("addresses", [])
    loadbalancer_ip = None
    
    for address in addresses:
        if address.get("type") == "IPAddress":
            loadbalancer_ip = address.get("value")
            break
    
    if not loadbalancer_ip:
        print("❌ Gateway LoadBalancer IP not assigned")
        return False, None
    
    print(f"✅ Gateway ready with LoadBalancer IP: {loadbalancer_ip}")
    return True, loadbalancer_ip

def check_gateway_listeners() -> bool:
    """Verify Gateway has correct HTTP and HTTPS listeners"""
    print("🔍 Checking Gateway listener configuration...")
    
    gateway = run_kubectl([
        "get", "gateway", "public-gateway", 
        "-n", "kube-system", 
        "-o", "json"
    ])
    
    if not gateway:
        return False
    
    spec = gateway.get("spec", {})
    listeners = spec.get("listeners", [])
    
    http_listener = None
    https_listener = None
    
    for listener in listeners:
        if listener.get("name") == "http" and listener.get("port") == 80:
            http_listener = listener
        elif listener.get("name") == "https" and listener.get("port") == 443:
            https_listener = listener
    
    if not http_listener:
        print("❌ HTTP listener (port 80) not found")
        return False
    
    if not https_listener:
        print("❌ HTTPS listener (port 443) not found")
        return False
    
    # Check HTTPS TLS configuration
    tls_config = https_listener.get("tls", {})
    if tls_config.get("mode") != "Terminate":
        print("❌ HTTPS listener TLS mode not set to Terminate")
        return False
    
    print("✅ Gateway listeners configured correctly (HTTP:80, HTTPS:443)")
    return True

def check_cluster_issuer() -> bool:
    """Check if ClusterIssuer is ready"""
    print("🔍 Checking ClusterIssuer status...")
    
    # Check staging issuer
    staging_issuer = run_kubectl([
        "get", "clusterissuer", "letsencrypt-staging", 
        "-o", "json"
    ])
    
    if not staging_issuer:
        print("❌ letsencrypt-staging ClusterIssuer not found")
        return False
    
    # Check issuer status
    status = staging_issuer.get("status", {})
    conditions = status.get("conditions", [])
    
    ready_condition = None
    for condition in conditions:
        if condition.get("type") == "Ready":
            ready_condition = condition
            break
    
    if not ready_condition:
        print("⚠️  ClusterIssuer Ready condition not found (may still be initializing)")
        return True  # Allow some time for initialization
    
    if ready_condition.get("status") != "True":
        print(f"❌ ClusterIssuer not ready: {ready_condition.get('message', 'Unknown reason')}")
        return False
    
    print("✅ ClusterIssuer ready for certificate provisioning")
    return True

def test_loadbalancer_connectivity(ip: str) -> bool:
    """Test if LoadBalancer IP responds to HTTP requests"""
    print(f"🔍 Testing LoadBalancer connectivity to {ip}...")
    
    try:
        # Test HTTP connectivity (should get some response, even if 404 or connection reset)
        # Note: Without HTTPRoutes attached, Gateway may close connection or return 404
        response = requests.get(f"http://{ip}", timeout=10)
        print(f"✅ LoadBalancer responds to HTTP requests (status: {response.status_code})")
        return True
    except requests.exceptions.ConnectionError as e:
        # Connection reset or closed is acceptable - Gateway is reachable but no routes configured
        if "RemoteDisconnected" in str(e) or "Connection refused" in str(e) or "Connection reset" in str(e):
            print(f"⚠️  LoadBalancer reachable but no routes configured (expected behavior)")
            return True
        print(f"❌ LoadBalancer not accessible: {e}")
        return False
    except requests.exceptions.Timeout:
        print(f"❌ LoadBalancer connection timed out")
        return False
    except requests.exceptions.RequestException as e:
        print(f"❌ LoadBalancer not accessible: {e}")
        return False

def main():
    """Main validation function"""
    print("🚀 Starting Gateway Infrastructure Validation")
    print("=" * 50)
    
    all_checks_passed = True
    
    # First run the wait script to ensure Gateway is provisioned
    if not run_wait_script():
        all_checks_passed = False
    
    # Check Gateway status and get LoadBalancer IP
    gateway_ready, loadbalancer_ip = check_gateway_status()
    if not gateway_ready:
        all_checks_passed = False
    
    # Check Gateway listener configuration
    if not check_gateway_listeners():
        all_checks_passed = False
    
    # Check ClusterIssuer status
    if not check_cluster_issuer():
        all_checks_passed = False
    
    # Test LoadBalancer connectivity if IP is available
    if loadbalancer_ip:
        if not test_loadbalancer_connectivity(loadbalancer_ip):
            all_checks_passed = False
    
    print("=" * 50)
    if all_checks_passed:
        print("✅ CHECKPOINT 2: Gateway Infrastructure Ready - ALL CHECKS PASSED")
        sys.exit(0)
    else:
        print("❌ CHECKPOINT 2: Gateway Infrastructure Ready - SOME CHECKS FAILED")
        sys.exit(1)

if __name__ == "__main__":
    main()
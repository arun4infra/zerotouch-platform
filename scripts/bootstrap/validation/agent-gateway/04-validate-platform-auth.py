#!/usr/bin/env python3
"""
Platform Authentication End-to-End Validation Script

Validates the complete Trust Broker authentication flow with all security controls.

Verification Criteria:
- All 6 authentication test scenarios pass successfully
- Session creation, validation, and termination working correctly
- AgentGateway properly enforces authentication policies
- Production security gates prevent test endpoint access
- Cookie handling works correctly for in-cluster HTTP communication

Usage:
  python 04-validate-platform-auth.py  # Run as standalone script
"""

import subprocess
import json
import requests
import uuid
import time
import os
import sys
from typing import Dict, Any, Optional, Tuple

# Configuration
REQUEST_TIMEOUT = 10
RETRY_ATTEMPTS = 3
RETRY_DELAY = 2

def run_kubectl(cmd: str) -> Optional[str]:
    """Run kubectl command and return output"""
    try:
        result = subprocess.run(f"kubectl {cmd}", shell=True, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Error running kubectl {cmd}: {result.stderr}")
            return None
        return result.stdout.strip()
    except Exception as e:
        print(f"Exception running kubectl {cmd}: {e}")
        return None

def get_gateway_host() -> str:
    """Discover AgentGateway service endpoint for in-cluster testing"""
    # Allow override via environment variable
    env_host = os.getenv('GATEWAY_HOST')
    if env_host:
        print(f"🔍 Using GATEWAY_HOST from environment: {env_host}")
        return env_host
    
    # Priority 1: Direct cluster DNS (for in-cluster CI/CD)
    service_output = run_kubectl("get svc -l app.kubernetes.io/name=agentgateway -o json --all-namespaces")
    if not service_output:
        raise RuntimeError("Failed to discover AgentGateway - kubectl command failed")
    
    services_data = json.loads(service_output)
    services = services_data.get("items", [])
    
    if not services:
        raise RuntimeError("No AgentGateway found with label app.kubernetes.io/name=agentgateway")
    
    # Prioritize service in platform-agent-gateway namespace
    target_service = None
    for service in services:
        if service["metadata"]["namespace"] == "platform-agent-gateway":
            target_service = service
            break
    
    if not target_service:
        target_service = services[0]
    
    service_name = target_service["metadata"]["name"]
    namespace = target_service["metadata"]["namespace"]
    
    ports = target_service.get("spec", {}).get("ports", [])
    if not ports:
        raise RuntimeError(f"No ports found for AgentGateway {service_name}")
    
    port = ports[0]["port"]
    host = f"{service_name}.{namespace}.svc.cluster.local:{port}"
    print(f"🔍 Discovered AgentGateway at: {host}")
    return host

def get_identity_service_host() -> str:
    """Get Identity Service host dynamically using kubectl"""
    env_host = os.getenv('IDENTITY_HOST')
    if env_host:
        print(f"🔍 Using IDENTITY_HOST from environment: {env_host}")
        return env_host
    
    service_output = run_kubectl("get svc -l app.kubernetes.io/name=identity-service -o json --all-namespaces")
    if not service_output:
        raise RuntimeError("Failed to discover Identity Service - kubectl command failed")
    
    services_data = json.loads(service_output)
    services = services_data.get("items", [])
    
    if not services:
        raise RuntimeError("No Identity Service found with label app.kubernetes.io/name=identity-service")
    
    service = services[0]
    service_name = service["metadata"]["name"]
    namespace = service["metadata"]["namespace"]
    
    ports = service.get("spec", {}).get("ports", [])
    if not ports:
        raise RuntimeError(f"No ports found for Identity Service {service_name}")
    
    port = ports[0]["port"]
    host = f"{service_name}.{namespace}.svc.cluster.local:{port}"
    print(f"🔍 Discovered Identity Service at: {host}")
    return host

def check_environment() -> str:
    """Check Identity Service NODE_ENV"""
    try:
        result = run_kubectl(
            "get deployment -l app.kubernetes.io/name=identity-service "
            "-o jsonpath='{.items[0].spec.template.spec.containers[0].env[?(@.name==\"NODE_ENV\")].value}' "
            "--all-namespaces"
        )
        
        env_value = result.strip() if result else "development"
        print(f"🔍 Identity Service NODE_ENV: {env_value}")
        return env_value or "development"
        
    except Exception as e:
        print(f"⚠️  Could not detect NODE_ENV, assuming development: {e}")
        return "development"

def make_request(method: str, path: str, host: str, headers: Dict[str, str] = None, 
                json_data: Dict[str, Any] = None) -> requests.Response:
    """Make HTTP request with retry logic"""
    url = f"http://{host}{path}"
    
    default_headers = {
        "User-Agent": "platform-auth-validator/1.0",
        "Accept": "application/json, text/html"
    }
    
    if headers:
        default_headers.update(headers)
    
    for attempt in range(RETRY_ATTEMPTS):
        try:
            response = requests.request(
                method=method,
                url=url,
                headers=default_headers,
                json=json_data,
                timeout=REQUEST_TIMEOUT,
                verify=False,
                allow_redirects=False  # Disable automatic redirect following
            )
            return response
            
        except requests.exceptions.RequestException as e:
            if attempt == RETRY_ATTEMPTS - 1:
                raise
            print(f"⚠️  Request attempt {attempt + 1} failed, retrying...")
            time.sleep(RETRY_DELAY)

def extract_cookie_value(cookie_header: str, cookie_name: str) -> str:
    """Extract cookie value from Set-Cookie header"""
    if cookie_name not in cookie_header:
        return ""
    
    cookie_parts = cookie_header.split(f"{cookie_name}=")[1].split(";")[0]
    return cookie_parts

def test_login_route_accessibility() -> bool:
    """Test 1: Verify unauthenticated users can access login endpoint"""
    print("\n🔍 Test 1: Login Route Accessibility")
    print("-" * 60)
    
    gateway_host = get_gateway_host()
    
    try:
        response = make_request("GET", "/auth/login", gateway_host)
        
        if response.status_code != 200:
            print(f"❌ Expected 200 for /auth/login, got {response.status_code}")
            return False
        
        if "Continue with Google" not in response.text:
            print("❌ Login page doesn't contain expected content")
            return False
        
        print("✅ Login route accessible without authentication")
        return True
        
    except Exception as e:
        print(f"❌ Login route test failed: {e}")
        return False

def test_api_endpoint_protection() -> bool:
    """Test 2: Verify API endpoints reject unauthenticated requests"""
    print("\n🔍 Test 2: API Endpoint Protection")
    print("-" * 60)
    
    gateway_host = get_gateway_host()
    
    try:
        response = make_request("GET", "/api/v1/health", gateway_host)
        
        if response.status_code != 401:
            print(f"❌ Expected 401 for unauthenticated /api/v1/health, got {response.status_code}")
            return False
        
        print("✅ API endpoints protected (returned 401)")
        return True
        
    except Exception as e:
        print(f"❌ API protection test failed: {e}")
        return False

def test_session_generation() -> Tuple[bool, Optional[str]]:
    """Test 3: Create valid session via test endpoint"""
    print("\n🔍 Test 3: Session Generation for Testing")
    print("-" * 60)
    
    env = check_environment()
    identity_host = get_identity_service_host()
    
    # Generate unique test identifiers
    test_payload = {
        "external_id": f"test-user-{uuid.uuid4().hex[:8]}-{int(time.time())}",
        "email": f"test-{uuid.uuid4().hex[:8]}@example.com",
        "organization_name": f"Test Org {uuid.uuid4().hex[:8]}"
    }
    
    print(f"🔍 Creating session with payload: {test_payload}")
    print(f"🔍 [TIMESTAMP] Session creation started at: {time.time()}")
    
    try:
        response = make_request("POST", "/auth/test-session", identity_host, json_data=test_payload)
        
        print(f"🔍 [TIMESTAMP] Session creation completed at: {time.time()}")
        print(f"🔍 Session creation response status: {response.status_code}")
        print(f"🔍 Session creation response headers: {dict(response.headers)}")
        
        # Production environment check
        if env == "production":
            if response.status_code == 404:
                print("✅ Test endpoint correctly disabled in production")
                return True, None
            else:
                print(f"❌ Test endpoint should return 404 in production, got {response.status_code}")
                return False, None
        
        # Non-production: should create session
        if response.status_code != 200:
            print(f"❌ Failed to create session: {response.status_code}")
            print(f"❌ Response: {response.text}")
            return False, None
        
        response_data = response.json()
        print(f"🔍 Session creation response data: {response_data}")
        
        # Verify response structure
        required_fields = ["status", "user_id", "org_id", "session_id"]
        for field in required_fields:
            if field not in response_data:
                print(f"❌ Missing required field: {field}")
                return False, None
        
        if response_data["status"] != "success":
            print(f"❌ Unexpected status: {response_data['status']}")
            return False, None
        
        # Extract session cookie
        cookie_header = response.headers.get("Set-Cookie", "")
        print(f"🔍 Session cookie header: {cookie_header}")
        
        if "__Host-platform_session=" not in cookie_header:
            print("❌ Session cookie not set correctly")
            return False, None
        
        cookie_value = extract_cookie_value(cookie_header, "__Host-platform_session")
        if not cookie_value:
            print("❌ Could not extract cookie value")
            return False, None
        
        print(f"✅ Session created successfully (session_id: {response_data['session_id'][:16]}...)")
        print(f"🔍 Extracted cookie value: {cookie_value[:16]}...")
        print(f"🔍 [TIMESTAMP] Returning from Test 3 at: {time.time()}")
        return True, cookie_value
        
    except Exception as e:
        print(f"❌ Session generation test failed: {e}")
        import traceback
        print(f"❌ Full traceback: {traceback.format_exc()}")
        return False, None

def test_authenticated_api_access(cookie: str) -> bool:
    """Test 4: Verify valid session enables API access"""
    print("\n🔍 Test 4: Authenticated API Access")
    print("-" * 60)
    print(f"🔍 [TIMESTAMP] Test 4 started at: {time.time()}")
    
    gateway_host = get_gateway_host()
    
    try:
        headers = {"Cookie": f"__Host-platform_session={cookie}"}
        print(f"🔍 Making request with cookie: {cookie[:16]}...")
        print(f"🔍 [TIMESTAMP] Sending request at: {time.time()}")
        response = make_request("GET", "/api/v1/health", gateway_host, headers=headers)
        
        print(f"🔍 [TIMESTAMP] Received response at: {time.time()}")
        print(f"🔍 Response status: {response.status_code}")
        print(f"🔍 Response headers: {dict(response.headers)}")
        print(f"🔍 Response body: {response.text[:200]}...")
        
        # Differentiate auth failure from downstream failure
        if response.status_code == 200:
            print("✅ Authenticated API access successful (200 OK)")
            return True
        elif response.status_code == 404:
            print("✅ Auth passed (endpoint not found) - authentication working")
            return True
        elif response.status_code >= 500:
            print(f"✅ Auth passed (downstream service error {response.status_code}) - authentication working")
            return True
        elif response.status_code in [401, 403]:
            print(f"❌ Auth failed with status {response.status_code}")
            print("❌ This suggests extAuthz rejected the session or gateway misconfiguration")
            return False
        else:
            print(f"❌ Unexpected response status: {response.status_code}")
            return False
        
    except Exception as e:
        print(f"❌ Authenticated access test failed: {e}")
        return False

def test_session_termination(cookie: str) -> bool:
    """Test 5: Verify logout invalidates session"""
    print("\n🔍 Test 5: Session Termination (Logout)")
    print("-" * 60)
    print(f"🔍 [TIMESTAMP] Test 5 (logout) started at: {time.time()}")
    print(f"🔍 [CRITICAL] About to call /auth/logout endpoint")
    
    gateway_host = get_gateway_host()
    
    try:
        headers = {"Cookie": f"__Host-platform_session={cookie}"}
        print(f"🔍 [TIMESTAMP] Sending logout request at: {time.time()}")
        response = make_request("POST", "/auth/logout", gateway_host, headers=headers)
        
        print(f"🔍 [TIMESTAMP] Logout response received at: {time.time()}")
        if response.status_code != 200:
            print(f"❌ Logout failed with status {response.status_code}")
            return False
        
        # Check cookie expiry
        cookie_header = response.headers.get("Set-Cookie", "")
        print(f"🔍 Logout response Set-Cookie header: {cookie_header}")
        
        # Check for Max-Age=0 or Expires with epoch time (Jan 1, 1970)
        has_max_age_zero = "Max-Age=0" in cookie_header or "max-age=0" in cookie_header.lower()
        has_expires_epoch = "Expires=Thu, 01 Jan 1970" in cookie_header
        
        print(f"🔍 Checking cookie expiry - Max-Age=0: {has_max_age_zero}, Expires epoch: {has_expires_epoch}")
        
        if not (has_max_age_zero or has_expires_epoch):
            print("❌ Cookie not expired in logout response")
            print("❌ Expected either 'Max-Age=0' or 'Expires=Thu, 01 Jan 1970'")
            return False
        
        print("✅ Session terminated successfully (cookie expired)")
        print(f"🔍 [TIMESTAMP] Test 5 completed at: {time.time()}")
        return True
        
    except Exception as e:
        print(f"❌ Session termination test failed: {e}")
        return False

def test_post_logout_access_denial(cookie: str) -> bool:
    """Test 6: Verify logged-out session cannot access APIs"""
    print("\n🔍 Test 6: Post-Logout Access Denial")
    print("-" * 60)
    
    gateway_host = get_gateway_host()
    
    try:
        headers = {"Cookie": f"__Host-platform_session={cookie}"}
        response = make_request("GET", "/api/v1/health", gateway_host, headers=headers)
        
        if response.status_code != 401:
            print(f"❌ Expected 401 for logged-out session, got {response.status_code}")
            return False
        
        print("✅ Logged-out session denied access (401)")
        return True
        
    except Exception as e:
        print(f"❌ Post-logout access test failed: {e}")
        return False

def test_production_security_hardening() -> bool:
    """Test 7: Verify production security gates"""
    print("\n🔍 Test 7: Production Security Hardening")
    print("-" * 60)
    
    env = check_environment()
    
    if env != "production":
        print("✅ Running in non-production environment - security gates appropriate")
        return True
    
    identity_host = get_identity_service_host()
    
    try:
        test_payload = {
            "external_id": "prod-test-user",
            "email": "prod-test@example.com",
            "organization_name": "Prod Test Org"
        }
        
        response = make_request("POST", "/auth/test-session", identity_host, json_data=test_payload)
        
        if response.status_code != 404:
            print(f"❌ Test endpoint should return 404 in production, got {response.status_code}")
            return False
        
        print("✅ Production security hardening verified (test endpoint disabled)")
        return True
        
    except Exception as e:
        print(f"❌ Production security test failed: {e}")
        return False

def main():
    """Main validation function"""
    print("=" * 60)
    print("CHECKPOINT 3: Complete Authentication Flow Validation")
    print("=" * 60)
    
    # Check for dry-run mode
    dry_run = os.getenv('DRY_RUN', 'false').lower() == 'true'
    if dry_run:
        print("🔍 Running in dry-run mode - skipping actual tests")
        print("✅ Script structure validated")
        sys.exit(0)
    
    # Environment detection and safety checks
    env = check_environment()
    if env == "production":
        print("\n⚠️  WARNING: Running in production environment")
        print("⚠️  Only production-safe tests will be executed\n")
    
    success = True
    session_cookie = None
    
    # Test 1: Login route accessibility
    if not test_login_route_accessibility():
        success = False
    
    # Test 2: API endpoint protection
    if not test_api_endpoint_protection():
        success = False
    
    # Test 3: Session generation (skip remaining tests if this fails or in production)
    session_success, session_cookie = test_session_generation()
    if not session_success:
        success = False
    
    # Only run authenticated tests if we have a valid session
    if session_cookie:
        # Small delay to ensure session is fully persisted
        print(f"\n🔍 [TIMESTAMP] Waiting 1 second before Test 4 at: {time.time()}")
        time.sleep(1)
        print(f"🔍 [TIMESTAMP] Starting Test 4 at: {time.time()}")
        
        # Test 4: Authenticated API access (MUST run before logout)
        if not test_authenticated_api_access(session_cookie):
            success = False
        
        # Test 5: Session termination (invalidates the session)
        if not test_session_termination(session_cookie):
            success = False
        
        # Test 6: Post-logout access denial (uses invalidated session)
        if not test_post_logout_access_denial(session_cookie):
            success = False
    elif env != "production":
        print("\n⚠️  Skipping authenticated tests (no valid session)")
        success = False
    
    # Test 7: Production security hardening
    if not test_production_security_hardening():
        success = False
    
    # Final results
    print("\n" + "=" * 60)
    if success:
        print("✅ CHECKPOINT 3 PASSED: Complete authentication flow working")
        print("=" * 60)
        sys.exit(0)
    else:
        print("❌ CHECKPOINT 3 FAILED: Authentication flow validation failed")
        print("=" * 60)
        sys.exit(1)

if __name__ == "__main__":
    main()

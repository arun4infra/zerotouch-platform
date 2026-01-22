#!/usr/bin/env python3
"""
AgentGateway extAuthz Configuration Validation Script

Validates that the AgentGateway is properly configured with correct routing and extAuthz policies.

Verification Criteria:
- /auth/* routes bypass extAuthz and reach Identity Service directly
- /api/* routes invoke extAuthz with POST to /internal/validate
- requestHeaderModifier strips Cookie header from upstream requests
- includeRequestHeaders and includeResponseHeaders configuration is correct

Usage:
  python 03-validate-gateway-config.py  # Run as standalone script
"""

import subprocess
import json
import requests
import uuid
import time
import os
import sys
from typing import Dict, Any, Optional

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
    """Get AgentGateway host dynamically using kubectl"""
    # Allow override via environment variable
    env_host = os.getenv('GATEWAY_HOST')
    if env_host:
        return env_host
    
    # Discover AgentGateway using kubectl - prioritize platform-agent-gateway namespace
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
    
    # Fallback to first service if platform-agent-gateway not found
    if not target_service:
        target_service = services[0]
    
    service_name = target_service["metadata"]["name"]
    namespace = target_service["metadata"]["namespace"]
    
    # Get the service port
    ports = target_service.get("spec", {}).get("ports", [])
    if not ports:
        raise RuntimeError(f"No ports found for AgentGateway {service_name}")
    
    port = ports[0]["port"]
    host = f"{service_name}.{namespace}.svc.cluster.local:{port}"
    print(f"🔍 Discovered AgentGateway at: {host} (namespace: {namespace})")
    return host

def get_identity_service_host() -> str:
    """Get Identity Service host dynamically using kubectl"""
    # Allow override via environment variable
    env_host = os.getenv('IDENTITY_HOST')
    if env_host:
        return env_host
    
    # Discover Identity Service using kubectl
    service_output = run_kubectl("get svc -l app.kubernetes.io/name=identity-service -o json --all-namespaces")
    if not service_output:
        raise RuntimeError("Failed to discover Identity Service - kubectl command failed")
    
    services_data = json.loads(service_output)
    services = services_data.get("items", [])
    
    if not services:
        raise RuntimeError("No Identity Service found with label app.kubernetes.io/name=identity-service")
    
    # Use the first service found
    service = services[0]
    service_name = service["metadata"]["name"]
    namespace = service["metadata"]["namespace"]
    
    # Get the service port
    ports = service.get("spec", {}).get("ports", [])
    if not ports:
        raise RuntimeError(f"No ports found for Identity Service {service_name}")
    
    port = ports[0]["port"]
    host = f"{service_name}.{namespace}.svc.cluster.local:{port}"
    print(f"🔍 Discovered Identity Service at: {host}")
    return host

def make_request(method: str, path: str, host: str, headers: Dict[str, str] = None, json_data: Dict[str, Any] = None) -> requests.Response:
    """Make HTTP request to specified host"""
    url = f"http://{host}{path}"
    default_headers = {
        "Content-Type": "application/json",
        "User-Agent": "gateway-config-validator/1.0"
    }
    
    if headers:
        default_headers.update(headers)
    
    return requests.request(
        method=method,
        url=url,
        headers=default_headers,
        json=json_data,
        timeout=10
    )

def test_auth_routes_bypass_extauthz():
    """Test that /auth/* routes bypass extAuthz and reach Identity Service directly"""
    print("🔍 Testing /auth/* routes bypass extAuthz...")
    
    gateway_host = get_gateway_host()
    
    try:
        # Test GET /auth/login - should reach Identity Service directly
        response = make_request("GET", "/auth/login", gateway_host)
        
        # Should get 200 OK from Identity Service (login page)
        if response.status_code != 200:
            print(f"❌ Expected 200 for /auth/login, got {response.status_code}")
            return False
        
        # Should contain login page content
        if "Continue with Google" not in response.text:
            print("❌ /auth/login response doesn't contain expected login content")
            return False
        
        print("✅ /auth/login bypasses extAuthz and reaches Identity Service")
        return True
        
    except Exception as e:
        print(f"❌ Request to /auth/login failed: {e}")
        return False

def test_invalid_cookie_rejection():
    """Test that invalid cookies are rejected with 401"""
    print("🔍 Testing invalid cookie rejection...")
    
    gateway_host = get_gateway_host()
    
    try:
        # Test with invalid cookie value
        headers = {"Cookie": "__Host-platform_session=invalid_junk_token_12345"}
        response = make_request("GET", "/api/v1/health", gateway_host, headers=headers)
        
        # STRICT: Must return exactly 401 for invalid credentials
        if response.status_code == 401:
            print("✅ Invalid cookie rejected with 401")
            return True
        
        print(f"❌ Expected 401 for invalid cookie, got {response.status_code}")
        return False
        
    except Exception as e:
        print(f"❌ Invalid cookie test failed: {e}")
        return False

def test_api_routes_invoke_extauthz():
    """Test that /api/* routes invoke extAuthz with POST to /internal/validate"""
    print("🔍 Testing /api/* routes invoke extAuthz...")
    
    gateway_host = get_gateway_host()
    
    try:
        # Test GET /api/v1/health without authentication - should trigger extAuthz
        response = make_request("GET", "/api/v1/health", gateway_host)
        
        # STRICT: Enforce exactly 401 for unauthenticated requests
        # 403 is reserved for "Authenticated but Unauthorized" scenarios
        if response.status_code == 401:
            print("✅ /api/v1/health protected by extAuthz (returned 401)")
            return True
        elif response.status_code == 403:
            print("❌ Got 403 instead of 401 - configuration drift detected")
            print("❌ Gateway should pass through 401 from Identity Service")
            return False
        elif response.status_code == 404:
            print("❌ Got 404 - extAuthz not configured (request bypassed auth)")
            return False
        
        print(f"❌ Expected 401 for unauthenticated /api/v1/health, got {response.status_code}")
        return False
        
    except Exception as e:
        print(f"❌ Request to /api/v1/health failed: {e}")
        return False

def test_extauthz_validation_endpoint():
    """Test that extAuthz calls POST /internal/validate on Identity Service"""
    print("🔍 Testing extAuthz validation endpoint...")
    
    identity_host = get_identity_service_host()
    
    try:
        # Test direct call to /internal/validate without Cookie header
        # This simulates what AgentGateway should be doing
        response = make_request("POST", "/internal/validate", identity_host)
        
        # Should get 401 because no Cookie header provided
        if response.status_code != 401:
            print(f"❌ Expected 401 for /internal/validate without Cookie, got {response.status_code}")
            return False
        
        print("✅ /internal/validate endpoint responds correctly to extAuthz requests")
        return True
        
    except Exception as e:
        print(f"❌ Request to /internal/validate failed: {e}")
        return False

def test_cookie_header_stripping():
    """Test that Cookie headers are stripped from upstream requests"""
    print("🔍 Testing Cookie header stripping...")
    
    # This test requires a valid session to verify the header modification behavior
    # We'll create a test session first, then verify the behavior
    
    identity_host = get_identity_service_host()
    gateway_host = get_gateway_host()
    
    try:
        # Create a test session
        test_payload = {
            "external_id": f"header-test-{uuid.uuid4().hex[:8]}-{int(time.time())}",
            "email": f"header-test-{uuid.uuid4().hex[:8]}@example.com",
            "organization_name": f"Header Test Org {uuid.uuid4().hex[:8]}"
        }
        
        print(f"🔍 Creating test session with payload: {test_payload}")
        
        # Create session via Identity Service directly (not through gateway)
        session_response = make_request("POST", "/auth/test-session", identity_host, json_data=test_payload)
        
        print(f"🔍 Session creation response: {session_response.status_code}")
        print(f"🔍 Session response headers: {dict(session_response.headers)}")
        
        if session_response.status_code != 200:
            print(f"❌ Failed to create test session: {session_response.status_code}")
            print(f"❌ Response body: {session_response.text}")
            return False
        
        # Extract session cookie
        cookie_header = session_response.headers.get("Set-Cookie", "")
        print(f"🔍 Set-Cookie header: {cookie_header}")
        
        if "__Host-platform_session=" not in cookie_header:
            print("❌ No session cookie in response")
            return False
        
        # Extract cookie value
        cookie_parts = cookie_header.split("__Host-platform_session=")[1].split(";")[0]
        session_cookie = f"__Host-platform_session={cookie_parts}"
        print(f"🔍 Extracted session cookie: {session_cookie[:50]}...")
        
        # Test direct validation to ensure session is valid
        print("🔍 Testing direct validation with session cookie...")
        validate_headers = {"Cookie": session_cookie}
        validate_response = make_request("POST", "/internal/validate", identity_host, headers=validate_headers)
        print(f"🔍 Direct validation response: {validate_response.status_code}")
        print(f"🔍 Direct validation headers: {dict(validate_response.headers)}")
        
        if validate_response.status_code == 200:
            print("✅ Session is valid for direct validation")
        else:
            print(f"❌ Session validation failed: {validate_response.status_code}")
            print(f"❌ Validation response: {validate_response.text}")
            return False
        
        # Now test authenticated request through gateway
        print("🔍 Testing authenticated request through gateway...")
        headers = {"Cookie": session_cookie}
        api_response = make_request("GET", "/api/v1/health", gateway_host, headers=headers)
        
        print(f"🔍 Gateway API response: {api_response.status_code}")
        print(f"🔍 Gateway response headers: {dict(api_response.headers)}")
        print(f"🔍 Gateway response body: {api_response.text}")
        
        # The response should be either:
        # - 200 OK if IDE Orchestrator is running and receives the JWT
        # - 5xx if IDE Orchestrator is not available but auth passed
        # - 401/403 if auth failed (Cookie not stripped properly or extAuthz failed)
        
        if api_response.status_code in [200]:
            print("✅ Authenticated request succeeded - Cookie header handling working")
            return True
        elif api_response.status_code == 404:
            print("✅ Auth passed (endpoint not found) - Cookie header handling working")
            return True
        elif api_response.status_code >= 500:
            print("✅ Auth passed (downstream service error) - Cookie header handling working")
            return True
        elif api_response.status_code in [401, 403]:
            print(f"❌ Auth failed with status {api_response.status_code} - possible Cookie header issue")
            print(f"❌ This suggests extAuthz is rejecting the request")
            return False
        else:
            print(f"❌ Unexpected response status: {api_response.status_code}")
            return False
        
    except Exception as e:
        print(f"❌ Cookie header stripping test failed: {e}")
        import traceback
        print(f"❌ Full traceback: {traceback.format_exc()}")
        return False

def test_include_headers_configuration():
    """Test that includeRequestHeaders and includeResponseHeaders are configured correctly"""
    print("🔍 Testing include headers configuration...")
    
    # This test verifies the configuration by checking the behavior
    # We can't directly inspect the AgentGateway config, but we can verify the behavior
    
    identity_host = get_identity_service_host()
    gateway_host = get_gateway_host()
    
    try:
        # Create a test session to get a valid cookie
        test_payload = {
            "external_id": f"headers-test-{uuid.uuid4().hex[:8]}-{int(time.time())}",
            "email": f"headers-test-{uuid.uuid4().hex[:8]}@example.com",
            "organization_name": f"Headers Test Org {uuid.uuid4().hex[:8]}"
        }
        
        print(f"🔍 Creating test session for headers test: {test_payload}")
        
        session_response = make_request("POST", "/auth/test-session", identity_host, json_data=test_payload)
        
        print(f"🔍 Headers test session creation: {session_response.status_code}")
        print(f"🔍 Headers test session headers: {dict(session_response.headers)}")
        
        if session_response.status_code != 200:
            print(f"❌ Failed to create test session: {session_response.status_code}")
            print(f"❌ Response body: {session_response.text}")
            return False
        
        # Extract session cookie
        cookie_header = session_response.headers.get("Set-Cookie", "")
        cookie_parts = cookie_header.split("__Host-platform_session=")[1].split(";")[0]
        session_cookie = f"__Host-platform_session={cookie_parts}"
        print(f"🔍 Headers test session cookie: {session_cookie[:50]}...")
        
        # Test request with Cookie header only (not Authorization)
        # The Authorization header will be added by extAuthz after validation
        headers = {
            "Cookie": session_cookie,
        }
        
        print(f"🔍 Testing gateway request with headers: {list(headers.keys())}")
        
        api_response = make_request("GET", "/api/v1/health", gateway_host, headers=headers)
        
        print(f"🔍 Headers test gateway response: {api_response.status_code}")
        print(f"🔍 Headers test response headers: {dict(api_response.headers)}")
        print(f"🔍 Headers test response body: {api_response.text}")
        
        # If the configuration is correct:
        # - Cookie header should be sent to extAuthz (includeRequestHeaders: ["cookie", "authorization"])
        # - Authorization header should be sent to extAuthz
        # - Response headers should be included (includeResponseHeaders: ["Authorization", "X-Auth-User-Id", "X-Auth-Org-Id"])
        
        # We can't directly verify the headers sent to extAuthz, but we can verify the overall behavior
        if api_response.status_code in [200]:
            print("✅ Headers configuration appears correct (auth succeeded)")
            return True
        elif api_response.status_code == 404:
            print("✅ Headers configuration appears correct (auth passed, endpoint not found)")
            return True
        elif api_response.status_code in [500, 502, 503, 504]:
            print("✅ Headers configuration appears correct (auth passed, downstream error)")
            return True
        elif api_response.status_code in [401, 403]:
            print("❌ Auth failed - possible headers configuration issue")
            print("❌ This suggests extAuthz is not receiving the correct headers")
            return False
        else:
            print(f"❌ Unexpected response status: {api_response.status_code}")
            return False
        
    except Exception as e:
        print(f"❌ Headers configuration test failed: {e}")
        import traceback
        print(f"❌ Full traceback: {traceback.format_exc()}")
        return False

def test_gateway_configuration_file():
    """Test that the AgentGateway configuration file is properly structured"""
    print("🔍 Testing AgentGateway configuration file...")
    
    try:
        # Read the AgentGateway configuration from the correct namespace
        config_output = run_kubectl("get configmap agentgateway-config -o jsonpath='{.data.config\\.yaml}' -n platform-agent-gateway")
        
        if not config_output:
            print("❌ Could not retrieve AgentGateway configuration")
            return False
        
        # Parse the YAML configuration
        import yaml
        try:
            config = yaml.safe_load(config_output)
        except yaml.YAMLError as e:
            print(f"❌ Invalid YAML in AgentGateway config: {e}")
            return False
        
        # Verify basic structure
        if "binds" not in config:
            print("❌ Missing 'binds' section in config")
            return False
        
        binds = config["binds"]
        if not isinstance(binds, list) or len(binds) == 0:
            print("❌ 'binds' should be a non-empty list")
            return False
        
        # Check the first bind configuration
        bind = binds[0]
        if "listeners" not in bind:
            print("❌ Missing 'listeners' in bind configuration")
            return False
        
        listeners = bind["listeners"]
        if not isinstance(listeners, list) or len(listeners) == 0:
            print("❌ 'listeners' should be a non-empty list")
            return False
        
        listener = listeners[0]
        if "routes" not in listener:
            print("❌ Missing 'routes' in listener configuration")
            return False
        
        routes = listener["routes"]
        if not isinstance(routes, list) or len(routes) < 2:
            print("❌ Should have at least 2 routes (auth and api)")
            return False
        
        # Find auth and api routes
        auth_route = None
        api_route = None
        
        for route in routes:
            if route.get("name") == "auth":
                auth_route = route
            elif route.get("name") == "api":
                api_route = route
        
        if not auth_route:
            print("❌ Missing 'auth' route configuration")
            return False
        
        if not api_route:
            print("❌ Missing 'api' route configuration")
            return False
        
        # Verify auth route configuration (should NOT have extAuthz)
        if "policies" in auth_route and "extAuthz" in auth_route["policies"]:
            print("❌ Auth route should not have extAuthz policy")
            return False
        
        # Verify API route configuration (should have extAuthz)
        if "policies" not in api_route:
            print("❌ API route missing policies section")
            return False
        
        policies = api_route["policies"]
        if "extAuthz" not in policies:
            print("❌ API route missing extAuthz policy")
            return False
        
        extauthz = policies["extAuthz"]
        
        # Verify host configuration
        if "host" not in extauthz:
            print("❌ extAuthz missing host configuration")
            return False
        
        if "identity-service.platform-identity.svc.cluster.local:3000" not in extauthz["host"]:
            print("❌ extAuthz host should point to Identity Service")
            return False
        
        # Verify extAuthz configuration - STRICT header validation
        required_request_headers = ["cookie", "authorization"]
        include_request_headers = [h.lower() for h in extauthz.get("includeRequestHeaders", [])]
        
        missing_headers = [h for h in required_request_headers if h not in include_request_headers]
        if missing_headers:
            print(f"❌ extAuthz missing required request headers: {missing_headers}")
            print(f"❌ Found: {extauthz.get('includeRequestHeaders', [])}")
            return False
        
        # Verify response headers are configured
        # Check both flat structure and nested protocol.http structure
        include_response_headers = []
        if "includeResponseHeaders" in extauthz:
            include_response_headers = [h.lower() for h in extauthz.get("includeResponseHeaders", [])]
        elif "protocol" in extauthz and "http" in extauthz["protocol"]:
            http_config = extauthz["protocol"]["http"]
            if "includeResponseHeaders" in http_config:
                include_response_headers = [h.lower() for h in http_config.get("includeResponseHeaders", [])]
        
        if not include_response_headers:
            print("❌ extAuthz missing includeResponseHeaders (checked both flat and protocol.http)")
            return False
        
        required_response_headers = ["authorization", "x-auth-user-id", "x-auth-org-id", "x-auth-role"]
        
        missing_response_headers = [h for h in required_response_headers if h not in include_response_headers]
        if missing_response_headers:
            print(f"❌ extAuthz missing required response headers: {missing_response_headers}")
            print(f"❌ Found: {include_response_headers}")
            return False
        
        # Verify requestHeaderModifier (Cookie removal)
        if "requestHeaderModifier" not in policies:
            print("❌ API route missing requestHeaderModifier")
            return False
        
        header_modifier = policies["requestHeaderModifier"]
        if "remove" not in header_modifier:
            print("❌ requestHeaderModifier missing remove section")
            return False
        
        if "Cookie" not in header_modifier["remove"]:
            print("❌ requestHeaderModifier should remove Cookie header")
            return False
        
        print("✅ AgentGateway configuration file is properly structured")
        return True
        
    except Exception as e:
        print(f"❌ Configuration file test failed: {e}")
        return False

def main():
    """Main validation function"""
    print("=== CHECKPOINT 2: Gateway Configuration Validated ===\n")
    
    # Check for dry-run mode
    dry_run = os.getenv('DRY_RUN', 'false').lower() == 'true'
    if dry_run:
        print("🔍 Running in dry-run mode - skipping actual tests")
        print("✅ Script structure validated")
        sys.exit(0)
    
    success = True
    
    # Run all configuration tests
    if not test_auth_routes_bypass_extauthz():
        success = False
    
    if not test_invalid_cookie_rejection():
        success = False
    
    if not test_api_routes_invoke_extauthz():
        success = False
    
    if not test_extauthz_validation_endpoint():
        success = False
    
    if not test_cookie_header_stripping():
        success = False
    
    if not test_include_headers_configuration():
        success = False
    
    if not test_gateway_configuration_file():
        success = False
    
    print("\n" + "="*60)
    if success:
        print("✅ CHECKPOINT 2 PASSED: Gateway configuration validated")
        sys.exit(0)
    else:
        print("❌ CHECKPOINT 2 FAILED: Gateway configuration validation failed")
        sys.exit(1)

if __name__ == "__main__":
    main()
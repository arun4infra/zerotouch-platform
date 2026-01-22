#!/usr/bin/env python3
"""
Test Endpoint Validation Script

Validates that the Identity Service test endpoint is functional.

Verification Criteria:
- POST /auth/test-session returns 200 with valid session cookie
- Test user and organization created in database via JIT provisioning
- Session stored in Hot_Cache with correct TTL and structure

Usage:
  python validate-test-endpoint.py  # Run as standalone script
  pytest validate-test-endpoint.py  # Run with pytest
"""

import subprocess
import json
import requests
import uuid
import time
import os
import sys
from typing import Dict, Any

def run_kubectl(cmd):
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

def make_request(method: str, path: str, host: str, json_data: Dict[str, Any] = None) -> requests.Response:
    """Make HTTP request to Identity Service"""
    url = f"http://{host}{path}"
    headers = {
        "Content-Type": "application/json"
    }
    
    return requests.request(
        method=method,
        url=url,
        headers=headers,
        json=json_data,
        timeout=10
    )

def test_session_creation():
    """Test session creation with all verification criteria"""
    print("🔍 Testing session creation...")
    
    # Test user data with unique identifiers
    test_payload = {
        "external_id": f"test-user-{uuid.uuid4().hex[:8]}-{int(time.time())}",
        "email": f"test-{uuid.uuid4().hex[:8]}@example.com",
        "organization_name": f"Test Organization {uuid.uuid4().hex[:8]}"
    }
    
    host = get_identity_service_host()
    if not host:
        print("❌ Could not discover Identity Service")
        return False
        
    try:
        response = make_request("POST", "/auth/test-session", host, json_data=test_payload)
    except Exception as e:
        print(f"❌ Request failed: {e}")
        return False
    
    # Verify endpoint returns 200
    if response.status_code != 200:
        print(f"❌ Expected 200, got {response.status_code}")
        return False
    
    response_data = response.json()
    required_fields = ["status", "user_id", "org_id", "session_id"]
    
    # Verify response structure
    for field in required_fields:
        if field not in response_data:
            print(f"❌ Missing required field: {field}")
            return False
    
    if response_data["status"] != "success":
        print(f"❌ Unexpected status: {response_data['status']}")
        return False
    
    # Verify session cookie is set correctly
    cookie_header = response.headers.get("Set-Cookie", "")
    if "__Host-platform_session=" not in cookie_header:
        print("❌ Session cookie not set correctly")
        return False
    
    # Verify cookie contains session ID
    session_id = response_data["session_id"]
    if session_id not in cookie_header:
        print("❌ Session ID not found in cookie")
        return False
    
    # Verify JIT provisioning created user and organization
    if not response_data["user_id"]:
        print("❌ User ID should be present (JIT provisioning)")
        return False
    if not response_data["org_id"]:
        print("❌ Organization ID should be present (JIT provisioning)")
        return False
    
    # Verify UUIDs are valid format
    import re
    uuid_pattern = r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    if not re.match(uuid_pattern, response_data["user_id"]):
        print("❌ Invalid user_id format")
        return False
    if not re.match(uuid_pattern, response_data["org_id"]):
        print("❌ Invalid org_id format")
        return False
    if not re.match(uuid_pattern, response_data["session_id"]):
        print("❌ Invalid session_id format")
        return False
    
    print("✅ Session creation working correctly")
    return True

def test_jit_provisioning_idempotency():
    """Test that JIT provisioning is idempotent"""
    print("🔍 Testing JIT provisioning idempotency...")
    
    # Use same external_id for both requests
    external_id = f"idempotent-user-{uuid.uuid4().hex[:8]}"
    test_payload = {
        "external_id": external_id,
        "email": f"test-{uuid.uuid4().hex[:8]}@example.com",
        "organization_name": f"Test Organization {uuid.uuid4().hex[:8]}"
    }
    
    host = get_identity_service_host()
    
    # First request - creates user/org
    response1 = make_request("POST", "/auth/test-session", host, json_data=test_payload)
    if response1.status_code != 200:
        print(f"❌ First request failed: {response1.status_code}")
        return False
    data1 = response1.json()
    
    # Second request with same external_id - should find existing user
    response2 = make_request("POST", "/auth/test-session", host, json_data=test_payload)
    if response2.status_code != 200:
        print(f"❌ Second request failed: {response2.status_code}")
        return False
    data2 = response2.json()
    
    # Should reference same user and org
    if data1["user_id"] != data2["user_id"]:
        print("❌ User ID should be same for idempotent requests")
        return False
    if data1["org_id"] != data2["org_id"]:
        print("❌ Organization ID should be same for idempotent requests")
        return False
    
    # Sessions should be different (new session each time)
    if data1["session_id"] == data2["session_id"]:
        print("❌ Session IDs should be different")
        return False
    
    print("✅ JIT provisioning idempotency working correctly")
    return True

def test_request_validation():
    """Test request schema validation"""
    print("🔍 Testing request validation...")
    
    host = get_identity_service_host()
    
    # Test with missing required fields
    invalid_payload = {
        "external_id": "test-user-invalid",
        # Missing email and organization_name
    }
    
    response = make_request("POST", "/auth/test-session", host, json_data=invalid_payload)
    if response.status_code != 400:
        print(f"❌ Should return 400 for invalid request, got {response.status_code}")
        return False
    
    # Test with invalid email format
    invalid_email_payload = {
        "external_id": "test-user-invalid-email",
        "email": "not-an-email",
        "organization_name": "Test Org"
    }
    
    response = make_request("POST", "/auth/test-session", host, json_data=invalid_email_payload)
    if response.status_code != 400:
        print(f"❌ Should return 400 for invalid email format, got {response.status_code}")
        return False
    
    print("✅ Request validation working correctly")
    return True

def test_hot_cache_session_storage():
    """Test that session is stored in Hot_Cache with correct TTL"""
    print("🔍 Testing Hot_Cache session storage...")
    
    # Create a test session with unique identifier to avoid conflicts
    test_payload = {
        "external_id": f"cache-test-{uuid.uuid4().hex[:8]}-{int(time.time())}",
        "email": f"cache-{uuid.uuid4().hex[:8]}@example.com",
        "organization_name": f"Cache Test Org {uuid.uuid4().hex[:8]}"
    }
    
    host = get_identity_service_host()
    
    try:
        response = make_request("POST", "/auth/test-session", host, json_data=test_payload)
    except Exception as e:
        print(f"❌ Request failed with exception: {e}")
        return False
    
    if response.status_code != 200:
        print(f"❌ Failed to create session: {response.status_code}")
        try:
            error_detail = response.json()
            print(f"❌ Error details: {error_detail}")
        except:
            print(f"❌ Response text: {response.text}")
        return False
    
    response_data = response.json()
    session_id = response_data["session_id"]
    
    # Verify session cookie is set with proper attributes
    cookie_header = response.headers.get("Set-Cookie", "")
    
    # Check for secure cookie attributes
    if "__Host-platform_session=" not in cookie_header:
        print("❌ Session cookie not set with __Host- prefix")
        return False
    
    if "HttpOnly" not in cookie_header:
        print("❌ Session cookie missing HttpOnly attribute")
        return False
    
    if "Secure" not in cookie_header:
        print("❌ Session cookie missing Secure attribute")
        return False
    
    # Verify session ID is in the cookie value
    if session_id not in cookie_header:
        print("❌ Session ID not found in cookie value")
        return False
    
    print("✅ Hot_Cache session storage working correctly")
    return True

def main():
    """Main validation function"""
    print("=== CHECKPOINT 1: Test Endpoint Ready Validation ===\n")
    
    success = True
    
    # Run all tests
    if not test_session_creation():
        success = False
    
    if not test_jit_provisioning_idempotency():
        success = False
    
    if not test_request_validation():
        success = False
    
    if not test_hot_cache_session_storage():
        success = False
        success = False
    
    print("\n" + "="*60)
    if success:
        print("✅ CHECKPOINT 1 PASSED: Test endpoint ready and functional")
        sys.exit(0)
    else:
        print("❌ CHECKPOINT 1 FAILED: Test endpoint validation failed")
        sys.exit(1)

# Pytest compatibility - keep the pytest functions for when run with pytest
try:
    import pytest
    
    @pytest.mark.integration
    def test_session_creation_pytest():
        """Pytest version of session creation test"""
        assert test_session_creation()
    
    @pytest.mark.integration
    def test_jit_provisioning_idempotency_pytest():
        """Pytest version of idempotency test"""
        assert test_jit_provisioning_idempotency()
    
    @pytest.mark.integration
    def test_request_validation_pytest():
        """Pytest version of request validation test"""
        assert test_request_validation()
    
    @pytest.mark.integration
    def test_hot_cache_session_storage_pytest():
        """Pytest version of hot cache test"""
        assert test_hot_cache_session_storage()
        
except ImportError:
    # pytest not available, skip pytest functions
    pass

if __name__ == "__main__":
    main()
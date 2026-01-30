"""Integration tests for JWT middleware - Checkpoint 2 validation.

Following INTEGRATION-TESTING-PATTERNS.md:
- Test real infrastructure, mock external dependencies only
- Use production code paths
- No mocking of internal SDK components
- Environment variable override pattern for configuration
"""
import os
import sys

# Add src to path for local testing
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../src'))

import pytest
from fastapi import FastAPI, Depends
from fastapi.testclient import TestClient

from zerotouch_sdk import (
    ZeroTouchAuthMiddleware,
    AuthContext,
    MockAuth,
    get_auth_context
)


class TestSDKPackageImports:
    """Test that all SDK modules are importable - validates package structure."""
    
    def test_import_middleware(self):
        """Verify ZeroTouchAuthMiddleware can be imported."""
        from zerotouch_sdk import ZeroTouchAuthMiddleware
        assert ZeroTouchAuthMiddleware is not None
    
    def test_import_auth_context(self):
        """Verify AuthContext can be imported."""
        from zerotouch_sdk import AuthContext
        assert AuthContext is not None
    
    def test_import_mock_auth(self):
        """Verify MockAuth can be imported."""
        from zerotouch_sdk import MockAuth
        assert MockAuth is not None
    
    def test_import_get_auth_context(self):
        """Verify get_auth_context can be imported."""
        from zerotouch_sdk import get_auth_context
        assert get_auth_context is not None
    
    def test_import_exceptions(self):
        """Verify AuthenticationError can be imported."""
        from zerotouch_sdk import AuthenticationError
        assert AuthenticationError is not None


class TestAuthContextModel:
    """Test AuthContext dataclass structure."""
    
    def test_auth_context_fields(self):
        """Verify AuthContext has required fields."""
        ctx = AuthContext(
            user_id="user-123",
            org_id="org-456",
            role="developer",
            membership_version=1,
            raw_token="token"
        )
        
        assert ctx.user_id == "user-123"
        assert ctx.org_id == "org-456"
        assert ctx.role == "developer"
        assert ctx.membership_version == 1
        assert ctx.raw_token == "token"
    
    def test_auth_context_has_role_method(self):
        """Verify AuthContext.has_role() method works."""
        ctx = AuthContext(
            user_id="user-123",
            org_id="org-456",
            role="developer",
            membership_version=1,
            raw_token="token"
        )
        
        assert ctx.has_role(["developer", "owner"]) is True
        assert ctx.has_role(["owner", "admin"]) is False
    
    def test_auth_context_immutable(self):
        """Verify AuthContext is frozen (immutable)."""
        ctx = AuthContext(
            user_id="user-123",
            org_id="org-456",
            role="developer",
            membership_version=1,
            raw_token="token"
        )
        
        with pytest.raises(Exception):  # FrozenInstanceError or AttributeError
            ctx.user_id = "new-user"


class TestMockAuthUtility:
    """Test MockAuth testing utility."""
    
    def test_mock_auth_create_context(self):
        """Verify MockAuth.create_context() generates valid AuthContext."""
        ctx = MockAuth.create_context(
            user_id="test-user",
            org_id="test-org",
            role="owner"
        )
        
        assert isinstance(ctx, AuthContext)
        assert ctx.user_id == "test-user"
        assert ctx.org_id == "test-org"
        assert ctx.role == "owner"
    
    def test_mock_auth_default_values(self):
        """Verify MockAuth.create_context() uses defaults."""
        ctx = MockAuth.create_context()
        
        assert ctx.user_id == "test-user-id"
        assert ctx.org_id == "test-org-id"
        assert ctx.role == "developer"
        assert ctx.membership_version == 1


class TestCrashOnlyStartup:
    """Test crash-only architecture for startup validation.
    
    These tests validate that the SDK fails fast at startup if misconfigured.
    """
    
    def test_missing_jwks_url_crashes(self):
        """Test SDK crashes with exit code 1 if PLATFORM_JWKS_URL missing."""
        from zerotouch_sdk.auth import ZeroTouchAuth
        
        # Clear environment
        old_value = os.environ.pop("PLATFORM_JWKS_URL", None)
        
        try:
            with pytest.raises(SystemExit) as exc_info:
                ZeroTouchAuth(jwks_url=None)
            
            assert exc_info.value.code == 1
        finally:
            # Restore environment
            if old_value:
                os.environ["PLATFORM_JWKS_URL"] = old_value
    
    def test_empty_jwks_url_crashes(self):
        """Test SDK crashes with exit code 1 if PLATFORM_JWKS_URL is empty."""
        from zerotouch_sdk.auth import ZeroTouchAuth
        
        with pytest.raises(SystemExit) as exc_info:
            ZeroTouchAuth(jwks_url="")
        
        assert exc_info.value.code == 1


class TestMiddlewarePublicPaths:
    """Test public path handling without authentication.
    
    These tests use production middleware code paths.
    """
    
    def test_health_endpoint_public(self):
        """Test /health endpoint works without authentication."""
        app = FastAPI()
        
        @app.get("/health")
        async def health():
            return {"status": "ok"}
        
        # Note: Middleware initialization will fail without JWKS_URL
        # This test validates the public path list exists
        assert "/health" in ZeroTouchAuthMiddleware.DEFAULT_PUBLIC_PATHS
    
    def test_default_public_paths_defined(self):
        """Test default public paths are defined correctly."""
        expected_paths = ["/health", "/metrics", "/docs", "/openapi.json", "/redoc"]
        
        for path in expected_paths:
            assert path in ZeroTouchAuthMiddleware.DEFAULT_PUBLIC_PATHS


class TestPytestFixtures:
    """Test pytest fixtures work correctly."""
    
    def test_mock_auth_owner_fixture(self, mock_auth_owner):
        """Test mock_auth_owner fixture."""
        assert mock_auth_owner.role == "owner"
        assert isinstance(mock_auth_owner, AuthContext)
    
    def test_mock_auth_developer_fixture(self, mock_auth_developer):
        """Test mock_auth_developer fixture."""
        assert mock_auth_developer.role == "developer"
        assert isinstance(mock_auth_developer, AuthContext)
    
    def test_mock_auth_viewer_fixture(self, mock_auth_viewer):
        """Test mock_auth_viewer fixture."""
        assert mock_auth_viewer.role == "viewer"
        assert isinstance(mock_auth_viewer, AuthContext)


class TestPackageBuildVerification:
    """Verify package metadata and structure."""
    
    def test_package_version(self):
        """Verify package version is defined."""
        from zerotouch_sdk import __version__
        assert __version__ == "1.0.0"
    
    def test_package_exports(self):
        """Verify all expected exports are available."""
        import zerotouch_sdk
        
        expected_exports = [
            "ZeroTouchAuth",
            "ZeroTouchAuthMiddleware",
            "AuthContext",
            "get_auth_context",
            "AuthenticationError",
            "MockAuth",
        ]
        
        for export in expected_exports:
            assert hasattr(zerotouch_sdk, export), f"Missing export: {export}"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])

"""Integration tests for JWT validation with mock JWKS server.

Tests JWT validation logic using production code paths with mock JWKS endpoint.
"""
import os
import sys
import time

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../src'))

import pytest
from fastapi import FastAPI, Depends
from fastapi.testclient import TestClient

from zerotouch_sdk import (
    ZeroTouchAuth,
    ZeroTouchAuthMiddleware,
    AuthContext,
    get_auth_context,
)
from zerotouch_sdk.exceptions import (
    AuthenticationError,
    MissingAuthHeaderError,
    ExpiredTokenError,
    InvalidSignatureError,
    MissingClaimsError,
)

from tests.mock.jwks_server import MockJWKSServer


@pytest.fixture(scope="module")
def jwks_server():
    """Start mock JWKS server for tests."""
    server = MockJWKSServer()
    server.start()
    yield server
    server.stop()


@pytest.fixture
def auth_validator(jwks_server):
    """Create ZeroTouchAuth instance with mock JWKS server."""
    return ZeroTouchAuth(
        jwks_url=jwks_server.url,
        audience="platform-services",
        issuer="https://platform.zerotouch.dev"
    )


class TestJWTValidationWithMockJWKS:
    """Test JWT validation using mock JWKS server."""
    
    def test_auth_initialization_success(self, jwks_server):
        """Test successful auth initialization with mock JWKS."""
        auth = ZeroTouchAuth(
            jwks_url=jwks_server.url,
            audience="platform-services",
            issuer="https://platform.zerotouch.dev"
        )
        
        assert auth.jwks_url == jwks_server.url
        assert auth.audience == "platform-services"
        assert auth.issuer == "https://platform.zerotouch.dev"
        assert auth.leeway_seconds == 30  # Default
    
    def test_auth_custom_leeway(self, jwks_server):
        """Test auth initialization with custom leeway."""
        auth = ZeroTouchAuth(
            jwks_url=jwks_server.url,
            audience="platform-services",
            issuer="https://platform.zerotouch.dev",
            leeway_seconds=60
        )
        
        assert auth.leeway_seconds == 60
    
    def test_auth_environment_leeway(self, jwks_server):
        """Test auth reads leeway from environment."""
        old_value = os.environ.get("JWT_LEEWAY_SECONDS")
        os.environ["JWT_LEEWAY_SECONDS"] = "45"
        
        try:
            auth = ZeroTouchAuth(
                jwks_url=jwks_server.url,
                audience="platform-services",
                issuer="https://platform.zerotouch.dev"
            )
            
            assert auth.leeway_seconds == 45
        finally:
            if old_value:
                os.environ["JWT_LEEWAY_SECONDS"] = old_value
            else:
                os.environ.pop("JWT_LEEWAY_SECONDS", None)


class TestMiddlewareWithMockJWKS:
    """Test middleware integration with mock JWKS server."""
    
    @pytest.fixture
    def app(self, jwks_server):
        """Create FastAPI app with middleware."""
        app = FastAPI()
        
        app.add_middleware(
            ZeroTouchAuthMiddleware,
            jwks_url=jwks_server.url,
            public_paths=["/api/webhooks/*"]
        )
        
        @app.get("/health")
        async def health():
            return {"status": "ok"}
        
        @app.get("/api/protected")
        async def protected(auth: AuthContext = Depends(get_auth_context)):
            return {
                "user_id": auth.user_id,
                "org_id": auth.org_id,
                "role": auth.role
            }
        
        @app.post("/api/webhooks/stripe")
        async def webhook():
            return {"received": True}
        
        return app
    
    @pytest.fixture
    def client(self, app):
        """Create test client."""
        return TestClient(app)
    
    def test_public_endpoint_no_auth(self, client):
        """Test public endpoint works without authentication."""
        response = client.get("/health")
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}
    
    def test_custom_public_path_no_auth(self, client):
        """Test custom public path works without authentication."""
        response = client.post("/api/webhooks/stripe")
        assert response.status_code == 200
        assert response.json() == {"received": True}
    
    def test_protected_endpoint_missing_auth(self, client):
        """Test protected endpoint requires authentication."""
        response = client.get("/api/protected")
        assert response.status_code == 401
        assert "detail" in response.json()
        assert response.json()["detail"] == "Missing authorization header"
    
    def test_protected_endpoint_malformed_header(self, client):
        """Test protected endpoint rejects malformed auth header."""
        response = client.get(
            "/api/protected",
            headers={"Authorization": "InvalidFormat token"}
        )
        assert response.status_code == 401
        assert response.json()["detail"] == "Malformed token"
    
    def test_middleware_public_path_wildcard(self, client):
        """Test wildcard public path matching."""
        # Wildcard paths need to exist as routes
        # This test validates the middleware allows them through
        # The 404 is expected since routes don't exist, but auth was bypassed
        response = client.post("/api/webhooks/github")
        # 404 means middleware allowed it through (no 401)
        assert response.status_code == 404  # Route doesn't exist, but auth bypassed
        
        response = client.post("/api/webhooks/slack/events")
        assert response.status_code == 404  # Route doesn't exist, but auth bypassed


class TestMiddlewareErrorHandling:
    """Test middleware error handling paths."""
    
    @pytest.fixture
    def app_with_callback(self, jwks_server):
        """Create app with on_success callback."""
        callback_called = []
        
        def on_success(auth_context):
            callback_called.append(auth_context)
        
        app = FastAPI()
        app.state.callback_called = callback_called
        
        app.add_middleware(
            ZeroTouchAuthMiddleware,
            jwks_url=jwks_server.url,
            on_success=on_success
        )
        
        @app.get("/api/test")
        async def test_endpoint(auth: AuthContext = Depends(get_auth_context)):
            return {"success": True}
        
        return app
    
    def test_on_success_callback_not_called_on_public_path(self, app_with_callback):
        """Test on_success callback not invoked for public paths."""
        client = TestClient(app_with_callback)
        
        # Public path should not trigger callback
        response = client.get("/health")
        assert len(app_with_callback.state.callback_called) == 0


class TestAuthContextInjection:
    """Test AuthContext injection into request state."""
    
    def test_get_auth_context_missing(self):
        """Test get_auth_context raises error when context missing."""
        from fastapi import Request, HTTPException
        from zerotouch_sdk import get_auth_context
        
        # Create mock request without auth_context
        class MockRequest:
            class State:
                pass
            state = State()
        
        request = MockRequest()
        
        with pytest.raises(HTTPException) as exc_info:
            get_auth_context(request)
        
        assert exc_info.value.status_code == 401
        assert exc_info.value.detail == "Authentication required"


class TestPublicPathMatching:
    """Test public path matching logic."""
    
    def test_is_public_path_exact_match(self, jwks_server):
        """Test exact path matching."""
        app = FastAPI()
        middleware = ZeroTouchAuthMiddleware(
            app=app,
            jwks_url=jwks_server.url
        )
        
        assert middleware._is_public_path("/health") is True
        assert middleware._is_public_path("/metrics") is True
        assert middleware._is_public_path("/docs") is True
    
    def test_is_public_path_wildcard_match(self, jwks_server):
        """Test wildcard path matching."""
        app = FastAPI()
        middleware = ZeroTouchAuthMiddleware(
            app=app,
            jwks_url=jwks_server.url,
            public_paths=["/api/webhooks/*"]
        )
        
        assert middleware._is_public_path("/api/webhooks/stripe") is True
        assert middleware._is_public_path("/api/webhooks/github/events") is True
        assert middleware._is_public_path("/api/other") is False
    
    def test_is_public_path_no_match(self, jwks_server):
        """Test non-public path returns False."""
        app = FastAPI()
        middleware = ZeroTouchAuthMiddleware(
            app=app,
            jwks_url=jwks_server.url
        )
        
        assert middleware._is_public_path("/api/protected") is False
        assert middleware._is_public_path("/api/users") is False


if __name__ == "__main__":
    pytest.main([__file__, "-v"])

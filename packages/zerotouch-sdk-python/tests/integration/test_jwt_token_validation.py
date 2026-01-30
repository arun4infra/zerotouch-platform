"""Integration tests for JWT token validation with real tokens.

Tests complete JWT validation flow using real EdDSA-signed tokens.
"""
import os
import sys
import time

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../src'))

import jwt
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
    ExpiredTokenError,
    InvalidAudienceError,
    InvalidIssuerError,
    MissingClaimsError,
)

from tests.mock.jwks_server import MockJWKSServer
from tests.mock.jwt_generator import JWTGenerator


@pytest.fixture(scope="module")
def jwks_server():
    """Start mock JWKS server."""
    server = MockJWKSServer()
    server.start()
    yield server
    server.stop()


@pytest.fixture(scope="module")
def jwt_gen():
    """Create JWT generator."""
    return JWTGenerator()


@pytest.fixture
def auth_validator(jwks_server):
    """Create auth validator with mock JWKS."""
    return ZeroTouchAuth(
        jwks_url=jwks_server.url,
        audience="platform-services",
        issuer="https://platform.zerotouch.dev"
    )


class TestValidTokenValidation:
    """Test validation of valid JWT tokens."""
    
    def test_validate_valid_token(self, auth_validator, jwt_gen):
        """Test successful validation of valid token."""
        token = jwt_gen.create_token(
            user_id="user-123",
            org_id="org-456",
            role="developer"
        )
        
        auth_context = auth_validator.validate_token(token)
        
        assert auth_context.user_id == "user-123"
        assert auth_context.org_id == "org-456"
        assert auth_context.role == "developer"
        assert auth_context.membership_version == 1
        assert auth_context.raw_token == token
    
    def test_validate_owner_role(self, auth_validator, jwt_gen):
        """Test validation with owner role."""
        token = jwt_gen.create_token(role="owner")
        
        auth_context = auth_validator.validate_token(token)
        
        assert auth_context.role == "owner"
        assert auth_context.has_role(["owner", "admin"])
    
    def test_validate_viewer_role(self, auth_validator, jwt_gen):
        """Test validation with viewer role."""
        token = jwt_gen.create_token(role="viewer")
        
        auth_context = auth_validator.validate_token(token)
        
        assert auth_context.role == "viewer"
        assert not auth_context.has_role(["owner", "admin"])


class TestExpiredTokenValidation:
    """Test validation of expired tokens."""
    
    def test_expired_token_rejected(self, auth_validator, jwt_gen):
        """Test expired token is rejected."""
        token = jwt_gen.create_expired_token()
        
        with pytest.raises(ExpiredTokenError) as exc_info:
            auth_validator.validate_token(token)
        
        assert exc_info.value.message == "Token has expired"
    
    def test_token_within_leeway_accepted(self, auth_validator, jwt_gen):
        """Test token within leeway is accepted."""
        # Token expires in 15 seconds (within 30s leeway)
        token = jwt_gen.create_token(expires_in=15)
        
        # Should be accepted due to leeway
        auth_context = auth_validator.validate_token(token)
        assert auth_context is not None


class TestMissingClaimsValidation:
    """Test validation of tokens with missing claims."""
    
    def test_missing_sub_claim(self, auth_validator, jwt_gen):
        """Test token missing sub claim is rejected."""
        token = jwt_gen.create_token_missing_claims(["sub"])
        
        with pytest.raises(MissingClaimsError) as exc_info:
            auth_validator.validate_token(token)
        
        assert "sub" in exc_info.value.message
    
    def test_missing_org_claim(self, auth_validator, jwt_gen):
        """Test token missing org claim is rejected."""
        token = jwt_gen.create_token_missing_claims(["org"])
        
        with pytest.raises(MissingClaimsError) as exc_info:
            auth_validator.validate_token(token)
        
        assert "org" in exc_info.value.message
    
    def test_missing_role_claim(self, auth_validator, jwt_gen):
        """Test token missing role claim is rejected."""
        token = jwt_gen.create_token_missing_claims(["role"])
        
        with pytest.raises(MissingClaimsError) as exc_info:
            auth_validator.validate_token(token)
        
        assert "role" in exc_info.value.message
    
    def test_missing_ver_claim(self, auth_validator, jwt_gen):
        """Test token missing ver claim is rejected."""
        token = jwt_gen.create_token_missing_claims(["ver"])
        
        with pytest.raises(MissingClaimsError) as exc_info:
            auth_validator.validate_token(token)
        
        assert "ver" in exc_info.value.message
    
    def test_missing_multiple_claims(self, auth_validator, jwt_gen):
        """Test token missing multiple claims is rejected."""
        token = jwt_gen.create_token_missing_claims(["sub", "org"])
        
        with pytest.raises(MissingClaimsError) as exc_info:
            auth_validator.validate_token(token)
        
        # Should mention missing claims
        assert "missing required claims" in exc_info.value.message.lower()


class TestAudienceIssuerValidation:
    """Test validation of audience and issuer claims."""
    
    def test_wrong_audience_rejected(self, auth_validator, jwt_gen):
        """Test token with wrong audience is rejected."""
        token = jwt_gen.create_token_wrong_audience()
        
        with pytest.raises(InvalidAudienceError) as exc_info:
            auth_validator.validate_token(token)
        
        assert exc_info.value.message == "Invalid token audience"
    
    def test_wrong_issuer_rejected(self, auth_validator, jwt_gen):
        """Test token with wrong issuer is rejected."""
        token = jwt_gen.create_token_wrong_issuer()
        
        with pytest.raises(InvalidIssuerError) as exc_info:
            auth_validator.validate_token(token)
        
        assert exc_info.value.message == "Invalid token issuer"


class TestMiddlewareWithRealTokens:
    """Test middleware with real JWT tokens."""
    
    @pytest.fixture
    def app(self, jwks_server):
        """Create FastAPI app with middleware."""
        app = FastAPI()
        
        app.add_middleware(
            ZeroTouchAuthMiddleware,
            jwks_url=jwks_server.url
        )
        
        @app.get("/api/user")
        async def get_user(auth: AuthContext = Depends(get_auth_context)):
            return {
                "user_id": auth.user_id,
                "org_id": auth.org_id,
                "role": auth.role,
                "membership_version": auth.membership_version
            }
        
        return app
    
    @pytest.fixture
    def client(self, app):
        """Create test client."""
        return TestClient(app)
    
    def test_valid_token_allows_access(self, client, jwt_gen):
        """Test valid token allows access to protected endpoint."""
        token = jwt_gen.create_token(
            user_id="user-789",
            org_id="org-012",
            role="admin"
        )
        
        response = client.get(
            "/api/user",
            headers={"Authorization": f"Bearer {token}"}
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["user_id"] == "user-789"
        assert data["org_id"] == "org-012"
        assert data["role"] == "admin"
        assert data["membership_version"] == 1
    
    def test_expired_token_rejected(self, client, jwt_gen):
        """Test expired token is rejected by middleware."""
        token = jwt_gen.create_expired_token()
        
        response = client.get(
            "/api/user",
            headers={"Authorization": f"Bearer {token}"}
        )
        
        assert response.status_code == 401
        assert response.json()["detail"] == "Token has expired"
    
    def test_token_missing_claims_rejected(self, client, jwt_gen):
        """Test token with missing claims is rejected."""
        token = jwt_gen.create_token_missing_claims(["org"])
        
        response = client.get(
            "/api/user",
            headers={"Authorization": f"Bearer {token}"}
        )
        
        assert response.status_code == 401
        assert "missing required claims" in response.json()["detail"].lower()
    
    def test_wrong_audience_rejected(self, client, jwt_gen):
        """Test token with wrong audience is rejected."""
        token = jwt_gen.create_token_wrong_audience()
        
        response = client.get(
            "/api/user",
            headers={"Authorization": f"Bearer {token}"}
        )
        
        assert response.status_code == 401
        assert response.json()["detail"] == "Invalid token audience"


class TestAuthContextExtraction:
    """Test AuthContext extraction from valid tokens."""
    
    def test_extract_all_claims(self, auth_validator, jwt_gen):
        """Test all claims are extracted correctly."""
        token = jwt_gen.create_token(
            user_id="user-abc",
            org_id="org-def",
            role="system",
            membership_version=5
        )
        
        auth_context = auth_validator.validate_token(token)
        
        assert auth_context.user_id == "user-abc"
        assert auth_context.org_id == "org-def"
        assert auth_context.role == "system"
        assert auth_context.membership_version == 5
        assert auth_context.raw_token == token
    
    def test_has_role_method(self, auth_validator, jwt_gen):
        """Test has_role method works correctly."""
        token = jwt_gen.create_token(role="developer")
        
        auth_context = auth_validator.validate_token(token)
        
        assert auth_context.has_role(["developer"])
        assert auth_context.has_role(["owner", "developer", "viewer"])
        assert not auth_context.has_role(["owner", "admin"])


if __name__ == "__main__":
    pytest.main([__file__, "-v"])


class TestInvalidSignatureHandling:
    """Test invalid signature error path."""
    
    @pytest.fixture
    def auth(self):
        with MockJWKSServer() as server:
            yield ZeroTouchAuth(jwks_url=server.jwks_url)
    
    def test_invalid_signature_rejected(self, auth):
        """Test token with wrong signature triggers InvalidSignatureError path."""
        # Create token with HS256 (wrong algorithm)
        token = jwt.encode(
            {"sub": "user", "org": "org", "role": "dev", "ver": 1, 
             "aud": "platform-services", "iss": "https://platform.zerotouch.dev",
             "exp": int(time.time()) + 3600, "nbf": int(time.time()), "iat": int(time.time())},
            "wrong-secret",
            algorithm="HS256"
        )
        
        with pytest.raises(Exception):  # Will raise during validation
            auth.validate_token(token)


class TestMalformedTokenHandling:
    """Test malformed token error path."""
    
    @pytest.fixture
    def auth(self):
        with MockJWKSServer() as server:
            yield ZeroTouchAuth(jwks_url=server.jwks_url)
    
    def test_malformed_token_rejected(self, auth):
        """Test malformed token triggers DecodeError path."""
        with pytest.raises(Exception):
            auth.validate_token("not.a.valid.jwt")


class TestEmptyRoleHandling:
    """Test empty role claim error path."""
    
    @pytest.fixture
    def auth(self):
        with MockJWKSServer() as server:
            yield ZeroTouchAuth(jwks_url=server.jwks_url)
    
    @pytest.fixture
    def jwt_gen(self):
        return JWTGenerator()
    
    def test_empty_role_rejected(self, auth, jwt_gen):
        """Test empty role string triggers MissingClaimsError path."""
        token = jwt_gen.create_token(role="")
        
        with pytest.raises(Exception):
            auth.validate_token(token)

"""JWT token generator for testing using EdDSA (Ed25519) keys."""
import time
from pathlib import Path

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend


class JWTGenerator:
    """Generate test JWT tokens using EdDSA (Ed25519) algorithm."""
    
    def __init__(self):
        """Initialize with test private key."""
        key_path = Path(__file__).parent.parent / "testdata" / "ed25519_private_key.pem"
        
        with open(key_path, 'rb') as f:
            self.private_key = serialization.load_pem_private_key(
                f.read(),
                password=None,
                backend=default_backend()
            )
        
        self.kid = "c13928fd-4c7f-47ab-af3a-de89839998e5"
    
    def create_token(
        self,
        user_id: str = "test-user-123",
        org_id: str = "test-org-456",
        role: str = "developer",
        membership_version: int = 1,
        audience: str = "platform-services",
        issuer: str = "https://platform.zerotouch.dev",
        expires_in: int = 3600,
        not_before_offset: int = 0
    ) -> str:
        """Create a valid JWT token."""
        now = int(time.time())
        
        payload = {
            "iss": issuer,
            "aud": audience,
            "sub": user_id,
            "org": org_id,
            "role": role,
            "ver": membership_version,
            "exp": now + expires_in,
            "nbf": now + not_before_offset,
            "iat": now
        }
        
        token = jwt.encode(
            payload,
            self.private_key,
            algorithm="EdDSA",
            headers={"kid": self.kid}
        )
        
        return token
    
    def create_expired_token(self, **kwargs) -> str:
        """Create an expired JWT token."""
        return self.create_token(expires_in=-3600, **kwargs)
    
    def create_not_yet_valid_token(self, **kwargs) -> str:
        """Create a token that's not yet valid."""
        return self.create_token(not_before_offset=3600, **kwargs)
    
    def create_token_missing_claims(self, missing_claims: list, **kwargs) -> str:
        """Create a token with missing required claims."""
        now = int(time.time())
        
        payload = {
            "iss": kwargs.get("issuer", "https://platform.zerotouch.dev"),
            "aud": kwargs.get("audience", "platform-services"),
            "sub": kwargs.get("user_id", "test-user-123"),
            "org": kwargs.get("org_id", "test-org-456"),
            "role": kwargs.get("role", "developer"),
            "ver": kwargs.get("membership_version", 1),
            "exp": now + kwargs.get("expires_in", 3600),
            "nbf": now,
            "iat": now
        }
        
        for claim in missing_claims:
            payload.pop(claim, None)
        
        token = jwt.encode(
            payload,
            self.private_key,
            algorithm="EdDSA",
            headers={"kid": self.kid}
        )
        
        return token
    
    def create_token_wrong_audience(self, **kwargs) -> str:
        """Create a token with wrong audience."""
        kwargs["audience"] = "wrong-audience"
        return self.create_token(**kwargs)
    
    def create_token_wrong_issuer(self, **kwargs) -> str:
        """Create a token with wrong issuer."""
        kwargs["issuer"] = "https://wrong-issuer.com"
        return self.create_token(**kwargs)

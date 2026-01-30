"""Core JWT validation logic."""
import asyncio
import logging
import os
import sys
import time
from typing import Optional, Set

import jwt
from jwt import PyJWKClient

from .exceptions import (
    AuthenticationError,
    ExpiredTokenError,
    InvalidAudienceError,
    InvalidIssuerError,
    InvalidSignatureError,
    MalformedTokenError,
    MissingClaimsError,
)
from .models import AuthContext

logger = logging.getLogger(__name__)


class ZeroTouchAuth:
    """Core JWT validator with JWKS caching and key rotation support.
    
    Implements crash-only architecture: exits with code 1 if authentication
    is misconfigured at startup.
    """
    
    def __init__(
        self,
        jwks_url: Optional[str] = None,
        audience: str = "platform-services",
        issuer: str = "https://platform.zerotouch.dev",
        leeway_seconds: Optional[int] = None,
        jwks_timeout: int = 5
    ):
        """Initialize with JWKS URL and expected claims.
        
        Args:
            jwks_url: JWKS endpoint URL (defaults to PLATFORM_JWKS_URL env var)
            audience: Expected 'aud' claim value
            issuer: Expected 'iss' claim value
            leeway_seconds: Clock skew tolerance (defaults to JWT_LEEWAY_SECONDS env or 30s)
            jwks_timeout: HTTP timeout for JWKS fetch in seconds (default 5s)
        
        Raises:
            SystemExit(1): If jwks_url is None/empty or JWKS keys cannot be fetched
        """
        # Get JWKS URL from parameter or environment
        self.jwks_url = jwks_url or os.getenv("PLATFORM_JWKS_URL")
        
        if not self.jwks_url:
            logger.error("PLATFORM_JWKS_URL environment variable is required")
            sys.exit(1)
        
        self.audience = audience
        self.issuer = issuer
        
        # Get leeway from parameter, environment, or default to 30 seconds
        if leeway_seconds is not None:
            self.leeway_seconds = leeway_seconds
        else:
            self.leeway_seconds = int(os.getenv("JWT_LEEWAY_SECONDS", "30"))
        
        self.jwks_timeout = jwks_timeout
        
        # Initialize JWKS client with strict timeout
        try:
            self.jwk_client = PyJWKClient(
                self.jwks_url,
                timeout=self.jwks_timeout
            )
            
            # Force initial JWKS fetch to validate configuration
            keys = self.jwk_client.get_signing_keys()
            
            if not keys or len(keys) == 0:
                raise ValueError("JWKS response contains no active keys")
            
            # Initialize cache tracking
            self.cached_kids: Set[str] = {key.key_id for key in keys}
            self.last_refresh: float = time.time()
            self.cache_created_at: float = time.time()
            
            logger.info(f"Successfully initialized auth with JWKS from {self.jwks_url}")
            
        except Exception as e:
            logger.error(f"Failed to fetch JWKS from {self.jwks_url}: {e}")
            sys.exit(1)
    
    def validate_token(self, token: str) -> AuthContext:
        """Validate JWT and return AuthContext.
        
        Args:
            token: Raw JWT string from Authorization header
            
        Returns:
            AuthContext with user_id, org_id, role, membership_version, raw_token
            
        Raises:
            AuthenticationError: With specific error message for each failure case
        """
        try:
            # Decode header to get kid (key ID)
            unverified_header = jwt.get_unverified_header(token)
            kid = unverified_header.get("kid")
            
            # Get signing key from JWKS
            try:
                signing_key = self.jwk_client.get_signing_key(kid)
            except jwt.exceptions.PyJWKClientError:
                # Unknown kid - attempt refresh if rate limit allows
                # Note: This is synchronous, but refresh logic handles async safety
                if kid and kid not in self.cached_kids:
                    # Trigger refresh (will be rate-limited)
                    try:
                        keys = self.jwk_client.get_signing_keys(refresh=True)
                        self.cached_kids = {key.key_id for key in keys}
                        self.last_refresh = time.time()
                        logger.info(f"JWKS cache refreshed (kid: {kid}, keys: {len(keys)})")
                    except Exception as refresh_error:
                        logger.warning(f"JWKS refresh failed: {refresh_error}")
                
                # Retry getting signing key
                signing_key = self.jwk_client.get_signing_key(kid)
            
            # Decode and validate JWT
            # Support both EdDSA (Ed25519) and RS256 algorithms
            payload = jwt.decode(
                token,
                signing_key.key,
                algorithms=["EdDSA", "RS256"],
                audience=self.audience,
                issuer=self.issuer,
                leeway=self.leeway_seconds,
                options={
                    "verify_signature": True,
                    "verify_exp": True,
                    "verify_nbf": True,
                    "verify_aud": True,
                    "verify_iss": True,
                }
            )
            
            # Validate required claims presence
            required_claims = ["sub", "org", "role", "ver"]
            missing_claims = [claim for claim in required_claims if claim not in payload]
            
            if missing_claims:
                raise MissingClaimsError(
                    f"Token missing required claims: {missing_claims}",
                    log_details=f"Missing claims: {missing_claims}"
                )
            
            # Validate role is non-empty string (no enum validation)
            if not isinstance(payload["role"], str) or not payload["role"]:
                raise MissingClaimsError(
                    "Token missing required claims: [role]",
                    log_details="Role claim is empty or invalid type"
                )
            
            # Create AuthContext
            auth_context = AuthContext(
                user_id=payload["sub"],
                org_id=payload["org"],
                role=payload["role"],
                membership_version=int(payload["ver"]),
                raw_token=token
            )
            
            # Log success at DEBUG level (reduce log volume)
            logger.debug(
                f"Authentication successful - user_id={auth_context.user_id} "
                f"org_id={auth_context.org_id} role={auth_context.role}"
            )
            
            return auth_context
            
        except jwt.exceptions.ExpiredSignatureError:
            raise ExpiredTokenError(
                "Token has expired",
                log_details="JWT exp claim validation failed"
            )
        except jwt.exceptions.InvalidSignatureError:
            raise InvalidSignatureError(
                "Invalid token signature",
                log_details="JWT signature validation failed"
            )
        except jwt.exceptions.InvalidAudienceError:
            raise InvalidAudienceError(
                "Invalid token audience",
                log_details=f"Expected audience: {self.audience}"
            )
        except jwt.exceptions.InvalidIssuerError:
            raise InvalidIssuerError(
                "Invalid token issuer",
                log_details=f"Expected issuer: {self.issuer}"
            )
        except jwt.exceptions.DecodeError:
            raise MalformedTokenError(
                "Malformed token",
                log_details="JWT decode failed"
            )
        except MissingClaimsError:
            # Re-raise our custom exception
            raise
        except Exception as e:
            # Catch-all for unexpected errors
            logger.error(f"Unexpected authentication error: {e}")
            raise AuthenticationError(
                "Authentication failed",
                log_details=str(e)
            )

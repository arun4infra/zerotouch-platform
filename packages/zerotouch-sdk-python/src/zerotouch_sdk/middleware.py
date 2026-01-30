"""FastAPI middleware for JWT validation."""
import logging
from typing import Callable, List, Optional

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

from .auth import ZeroTouchAuth
from .exceptions import AuthenticationError, MissingAuthHeaderError

logger = logging.getLogger(__name__)


class ZeroTouchAuthMiddleware(BaseHTTPMiddleware):
    """FastAPI middleware for automatic JWT validation.
    
    Intercepts requests, validates JWT tokens, and injects AuthContext
    into request.state for route handlers.
    """
    
    # Default public paths that skip authentication
    DEFAULT_PUBLIC_PATHS = [
        "/health",
        "/metrics",
        "/docs",
        "/openapi.json",
        "/redoc",
    ]
    
    def __init__(
        self,
        app,
        public_paths: Optional[List[str]] = None,
        on_success: Optional[Callable] = None,
        jwks_url: Optional[str] = None,
        audience: str = "platform-services",
        issuer: str = "https://platform.zerotouch.dev"
    ):
        """Initialize middleware with optional public paths and success callback.
        
        Args:
            app: FastAPI application instance
            public_paths: Additional paths to skip authentication (beyond defaults)
            on_success: Optional callback invoked after successful authentication
                       (use for custom observability, e.g., OTel span tagging)
            jwks_url: JWKS endpoint URL (defaults to PLATFORM_JWKS_URL env var)
            audience: Expected 'aud' claim value
            issuer: Expected 'iss' claim value
        """
        super().__init__(app)
        
        # Initialize auth validator
        self.auth = ZeroTouchAuth(
            jwks_url=jwks_url,
            audience=audience,
            issuer=issuer
        )
        
        # Combine default and custom public paths
        self.public_paths = self.DEFAULT_PUBLIC_PATHS.copy()
        if public_paths:
            self.public_paths.extend(public_paths)
        
        self.on_success = on_success
    
    def _is_public_path(self, path: str) -> bool:
        """Check if request path should skip authentication.
        
        Supports exact matches and wildcard patterns (e.g., /api/webhooks/*).
        
        Args:
            path: Request path to check
            
        Returns:
            True if path is public, False otherwise
        """
        for public_path in self.public_paths:
            # Exact match
            if path == public_path:
                return True
            
            # Wildcard match (e.g., /api/webhooks/*)
            if public_path.endswith("/*"):
                prefix = public_path[:-2]  # Remove /*
                if path.startswith(prefix):
                    return True
        
        return False
    
    async def dispatch(self, request: Request, call_next):
        """Process request through authentication pipeline.
        
        Flow:
        1. Check if path is public (skip auth)
        2. Extract Authorization header
        3. Validate JWT via ZeroTouchAuth
        4. Inject AuthContext into request.state
        5. Invoke on_success callback if provided (for custom observability)
        6. Call next middleware/handler
        
        Returns:
            Response from handler or 401 JSONResponse on auth failure
        """
        # Skip authentication for public paths
        if self._is_public_path(request.url.path):
            return await call_next(request)
        
        # Extract Authorization header
        auth_header = request.headers.get("Authorization")
        
        if not auth_header:
            logger.warning(f"Missing authorization header - path={request.url.path}")
            return JSONResponse(
                status_code=401,
                content={"detail": "Missing authorization header"}
            )
        
        # Extract Bearer token
        if not auth_header.startswith("Bearer "):
            logger.warning(f"Malformed authorization header - path={request.url.path}")
            return JSONResponse(
                status_code=401,
                content={"detail": "Malformed token"}
            )
        
        token = auth_header[7:]  # Remove "Bearer " prefix
        
        # Validate JWT
        try:
            auth_context = self.auth.validate_token(token)
            
            # Inject AuthContext into request state
            request.state.auth_context = auth_context
            
            # Invoke success callback if provided
            if self.on_success:
                try:
                    self.on_success(auth_context)
                except Exception as e:
                    logger.warning(f"on_success callback failed: {e}")
            
            # Continue to next middleware/handler
            response = await call_next(request)
            return response
            
        except AuthenticationError as e:
            # Log failure without exposing token
            if e.log_details:
                logger.warning(
                    f"Authentication failed: {e.log_details} - "
                    f"path={request.url.path}"
                )
            else:
                logger.warning(
                    f"Authentication failed: {e.message} - "
                    f"path={request.url.path}"
                )
            
            # Return user-facing error message
            return JSONResponse(
                status_code=401,
                content={"detail": e.message}
            )

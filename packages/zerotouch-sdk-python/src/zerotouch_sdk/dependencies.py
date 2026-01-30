"""FastAPI dependencies for authentication."""
from fastapi import Request, HTTPException

from .models import AuthContext


def get_auth_context(request: Request) -> AuthContext:
    """FastAPI dependency for extracting AuthContext from request.
    
    Args:
        request: FastAPI request object
        
    Returns:
        AuthContext injected by ZeroTouchAuthMiddleware
        
    Raises:
        HTTPException: 401 if AuthContext not found in request.state
    """
    auth_context = getattr(request.state, "auth_context", None)
    
    if auth_context is None:
        raise HTTPException(
            status_code=401,
            detail="Authentication required"
        )
    
    return auth_context

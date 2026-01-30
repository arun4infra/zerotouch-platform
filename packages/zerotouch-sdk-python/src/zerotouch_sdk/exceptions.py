"""Authentication exception hierarchy."""
from typing import Optional


class AuthenticationError(Exception):
    """Base exception for authentication failures."""
    
    def __init__(self, message: str, log_details: Optional[str] = None):
        """Initialize authentication error.
        
        Args:
            message: User-facing error message
            log_details: Internal details for logging (never exposed to users)
        """
        self.message = message
        self.log_details = log_details
        super().__init__(message)


class MissingAuthHeaderError(AuthenticationError):
    """Authorization header is missing from request."""
    pass


class MalformedTokenError(AuthenticationError):
    """JWT token is malformed or cannot be decoded."""
    pass


class InvalidSignatureError(AuthenticationError):
    """JWT signature validation failed."""
    pass


class ExpiredTokenError(AuthenticationError):
    """JWT token has expired beyond leeway."""
    pass


class InvalidAudienceError(AuthenticationError):
    """JWT audience claim does not match expected value."""
    pass


class InvalidIssuerError(AuthenticationError):
    """JWT issuer claim does not match expected value."""
    pass


class MissingClaimsError(AuthenticationError):
    """Required JWT claims are missing."""
    pass

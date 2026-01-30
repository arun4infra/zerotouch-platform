"""ZeroTouch SDK - Centralized JWT validation for platform services."""

from .auth import ZeroTouchAuth
from .middleware import ZeroTouchAuthMiddleware
from .models import AuthContext
from .dependencies import get_auth_context
from .exceptions import AuthenticationError
from .testing import MockAuth

__version__ = "1.0.0"

__all__ = [
    "ZeroTouchAuth",
    "ZeroTouchAuthMiddleware",
    "AuthContext",
    "get_auth_context",
    "AuthenticationError",
    "MockAuth",
]

# Optional OpenTelemetry integration
try:
    from opentelemetry import trace
    from opentelemetry.trace import Status, StatusCode
    OTEL_AVAILABLE = True
except ImportError:
    OTEL_AVAILABLE = False


def update_span_with_auth_context(auth_context: AuthContext):
    """Inject auth context into current OTel span if available.
    
    Args:
        auth_context: Authenticated user context
    """
    if not OTEL_AVAILABLE:
        return
    
    try:
        span = trace.get_current_span()
        if span.is_recording():
            span.set_attributes({
                "user.id": auth_context.user_id,
                "org.id": auth_context.org_id,
                "user.role": auth_context.role
            })
    except Exception:
        # Silently ignore OTel errors
        pass

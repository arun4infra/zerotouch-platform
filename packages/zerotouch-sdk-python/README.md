# ZeroTouch SDK Python

Centralized JWT validation SDK for ZeroTouch platform services.

## Installation

```bash
pip install zerotouch-sdk-python
```

## Quick Start

### FastAPI Integration

```python
from fastapi import FastAPI, Depends
from zerotouch_sdk import ZeroTouchAuthMiddleware, AuthContext, get_auth_context

app = FastAPI()

# Add JWT validation middleware
app.add_middleware(
    ZeroTouchAuthMiddleware,
    public_paths=["/health", "/metrics", "/api/webhooks/*"]
)

# Use auth context in route handlers
@app.get("/api/projects")
async def list_projects(auth: AuthContext = Depends(get_auth_context)):
    # Access authenticated user information
    user_id = auth.user_id
    org_id = auth.org_id
    role = auth.role
    
    # Check role-based permissions
    if auth.has_role("owner"):
        # Owner-specific logic
        pass
    
    return {"projects": []}
```

### Environment Configuration

The SDK requires the following environment variable:

- `PLATFORM_JWKS_URL`: URL to fetch JWT public keys (required)
- `JWT_LEEWAY_SECONDS`: Clock skew tolerance in seconds (optional, default: 30)

Example:
```bash
export PLATFORM_JWKS_URL="https://platform.zerotouch.dev/.well-known/jwks.json"
export JWT_LEEWAY_SECONDS="30"
```

### Testing with MockAuth

```python
import pytest
from zerotouch_sdk.testing import MockAuth, mock_auth_owner

def test_protected_endpoint(client, mock_auth_owner):
    """Test endpoint with mocked authentication."""
    with MockAuth.override_auth(mock_auth_owner):
        response = client.get("/api/projects")
        assert response.status_code == 200

def test_custom_auth_context(client):
    """Test with custom auth context."""
    auth_ctx = MockAuth.create_context(
        user_id="user_123",
        org_id="org_456",
        role="developer"
    )
    
    with MockAuth.override_auth(auth_ctx):
        response = client.get("/api/projects")
        assert response.status_code == 200
```

## Features

- **Crash-Only Architecture**: Services fail immediately at startup if authentication is misconfigured
- **EdDSA & RS256 Support**: Validates JWT signatures using EdDSA (Ed25519) or RS256 algorithms
- **Clock Skew Tolerance**: 30-second leeway for exp/nbf claims (configurable)
- **Public Path Exclusion**: Skip authentication for health checks, docs, and webhooks
- **Testing Utilities**: MockAuth for integration tests without real Identity Service
- **OpenTelemetry Integration**: Optional context propagation to spans
- **Key Rotation Support**: Automatic JWKS refresh with DDoS protection

## API Reference

### ZeroTouchAuthMiddleware

FastAPI middleware for JWT validation.

**Parameters:**
- `public_paths` (list[str], optional): Paths to exclude from authentication. Supports wildcards.

### AuthContext

Dataclass containing authenticated user information.

**Fields:**
- `user_id` (str): User identifier from JWT sub claim
- `org_id` (str): Organization identifier from JWT org claim
- `role` (str): User role from JWT role claim
- `membership_version` (int): Membership version from JWT ver claim
- `raw_token` (str): Original JWT token

**Methods:**
- `has_role(role: str) -> bool`: Check if user has specific role

### get_auth_context

FastAPI dependency for extracting AuthContext from request.

**Usage:**
```python
@app.get("/api/resource")
async def handler(auth: AuthContext = Depends(get_auth_context)):
    return {"user_id": auth.user_id}
```

### MockAuth

Testing utility for mock authentication.

**Methods:**
- `create_context(**kwargs) -> AuthContext`: Create test AuthContext
- `override_auth(context: AuthContext)`: Context manager to inject mock auth

**Pytest Fixtures:**
- `mock_auth_owner`: AuthContext with owner role
- `mock_auth_developer`: AuthContext with developer role
- `mock_auth_viewer`: AuthContext with viewer role

## Error Handling

The SDK returns 401 Unauthorized for authentication failures:

- Missing Authorization header: "Missing authorization header"
- Malformed token: "Malformed token"
- Invalid signature: "Invalid token signature"
- Expired token: "Token has expired"
- Invalid audience: "Invalid token audience"
- Invalid issuer: "Invalid token issuer"
- Missing claims: "Token missing required claims: [list]"

## License

MIT

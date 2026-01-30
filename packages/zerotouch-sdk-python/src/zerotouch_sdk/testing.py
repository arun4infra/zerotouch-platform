"""Testing utilities for mock authentication."""
from contextlib import contextmanager
from typing import Optional
from unittest.mock import patch

import pytest

from .models import AuthContext


class MockAuth:
    """Testing utility for mock authentication without real Identity Service."""
    
    @staticmethod
    def create_context(
        user_id: str = "test-user-id",
        org_id: str = "test-org-id",
        role: str = "developer",
        membership_version: int = 1,
        raw_token: str = "mock-jwt-token"
    ) -> AuthContext:
        """Create test AuthContext with default or custom values.
        
        Args:
            user_id: User UUID (default: test-user-id)
            org_id: Organization UUID (default: test-org-id)
            role: User role (default: developer)
            membership_version: Membership version (default: 1)
            raw_token: Raw JWT token (default: mock-jwt-token)
            
        Returns:
            AuthContext instance for testing
        """
        return AuthContext(
            user_id=user_id,
            org_id=org_id,
            role=role,
            membership_version=membership_version,
            raw_token=raw_token
        )
    
    @staticmethod
    @contextmanager
    def override_auth(auth_context: AuthContext):
        """Context manager to inject mock authentication in tests.
        
        Bypasses JWT validation and uses the provided AuthContext.
        
        Args:
            auth_context: AuthContext to inject into requests
            
        Usage:
            with MockAuth.override_auth(MockAuth.create_context(role="owner")):
                response = client.get("/api/projects")
                assert response.status_code == 200
        """
        # Patch the middleware's validate_token method to return mock context
        with patch("zerotouch_sdk.auth.ZeroTouchAuth.validate_token") as mock_validate:
            mock_validate.return_value = auth_context
            yield


# Pytest fixtures for common roles
@pytest.fixture
def mock_auth_owner():
    """Fixture for owner role testing."""
    return MockAuth.create_context(role="owner")


@pytest.fixture
def mock_auth_developer():
    """Fixture for developer role testing."""
    return MockAuth.create_context(role="developer")


@pytest.fixture
def mock_auth_viewer():
    """Fixture for viewer role testing."""
    return MockAuth.create_context(role="viewer")

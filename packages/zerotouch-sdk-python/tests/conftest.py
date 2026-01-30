"""Shared pytest fixtures for SDK tests."""
import sys
import os

# Add src to path for local testing
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../src'))

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from zerotouch_sdk.testing import MockAuth


@pytest.fixture
def app():
    """Create FastAPI test application."""
    app = FastAPI()
    
    @app.get("/health")
    async def health():
        return {"status": "ok"}
    
    @app.get("/api/test")
    async def test_endpoint():
        return {"message": "protected"}
    
    return app


@pytest.fixture
def client(app):
    """Create test client."""
    return TestClient(app)


# Import fixtures from testing module
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

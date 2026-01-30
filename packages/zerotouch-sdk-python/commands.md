# Commands for testing 

- python3 -m build
- pip install -e ".[dev]"
- pytest tests/integration/test_jwt_middleware_integration.py -v
- python3 -m pytest tests/integration/test_jwt_middleware_integration.py -v --tb=short
- python3 -m pytest tests/integration/test_jwt_middleware_integration.py --cov=src/zerotouch_sdk --cov-report=term-missing -v
- python3 -m pytest tests/integration/test_jwt_token_validation.py -v --cov=src/zerotouch_sdk --cov-report=term-missing

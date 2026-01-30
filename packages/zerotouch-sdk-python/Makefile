.PHONY: help install build test test-integration clean publish

help:
	@echo "Available commands:"
	@echo "  make install          - Install package with dev dependencies using uv"
	@echo "  make build            - Build package distribution"
	@echo "  make test             - Run all tests"
	@echo "  make test-integration - Run integration tests only"
	@echo "  make clean            - Remove build artifacts"
	@echo "  make publish          - Publish to PyPI"

install:
	uv pip install -e .[dev]

build:
	uv run python -m build

test:
	uv run pytest tests/

test-integration:
	uv run pytest tests/integration/ -v

clean:
	rm -rf dist/ build/ *.egg-info
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete

publish: build
	uv run twine upload dist/*

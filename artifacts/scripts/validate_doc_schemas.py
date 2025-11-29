#!/usr/bin/env python3
"""
Validate documentation frontmatter schemas.

This script validates that documentation files have correct frontmatter
based on their category (spec, runbook, adr).

Usage:
    python3 validate_doc_schemas.py <file_path>

Exit codes:
    0: Validation passed
    1: Validation failed
"""

import sys
import re
import yaml
from pathlib import Path
from typing import Dict, Any, List, Optional
from datetime import datetime, date

# Schema definitions for each category
SCHEMAS = {
    "spec": {
        "required_fields": [
            "schema_version",
            "category",
            "resource",
            "api_version",
            "kind",
            "composition_file",
            "created_at",
            "last_updated",
            "tags"
        ],
        "field_types": {
            "schema_version": str,
            "category": str,
            "resource": str,
            "api_version": str,
            "kind": str,
            "composition_file": str,
            "created_at": str,
            "last_updated": str,
            "tags": list
        },
        "field_constraints": {
            "category": lambda v: v == "spec",
            "schema_version": lambda v: v == "1.0"
        }
    },
    "runbook": {
        "required_fields": [
            "schema_version",
            "category",
            "resource",
            "issue_type",
            "severity",
            "created_at",
            "last_updated",
            "tags"
        ],
        "field_types": {
            "schema_version": str,
            "category": str,
            "resource": str,
            "issue_type": str,
            "severity": str,
            "created_at": str,
            "last_updated": str,
            "tags": list
        },
        "field_constraints": {
            "category": lambda v: v == "runbook",
            "schema_version": lambda v: v == "1.0",
            "issue_type": lambda v: v in ["operational", "performance", "security"],
            "severity": lambda v: v in ["critical", "high", "medium", "low"]
        }
    },
    "adr": {
        "required_fields": [
            "schema_version",
            "category",
            "status",
            "created_at",
            "last_updated"
        ],
        "field_types": {
            "schema_version": str,
            "category": str,
            "status": str,
            "created_at": str,
            "last_updated": str
        },
        "field_constraints": {
            "category": lambda v: v == "adr",
            "schema_version": lambda v: v == "1.0",
            "status": lambda v: v in ["proposed", "accepted", "rejected", "deprecated", "superseded"]
        }
    }
}


def extract_frontmatter(content: str) -> Optional[Dict[str, Any]]:
    """Extract YAML frontmatter from markdown content."""
    # Match frontmatter between --- delimiters
    pattern = r'^---\s*\n(.*?)\n---\s*\n'
    match = re.match(pattern, content, re.DOTALL)
    
    if not match:
        return None
    
    try:
        frontmatter = yaml.safe_load(match.group(1))
        return frontmatter
    except yaml.YAMLError as e:
        print(f"Error parsing YAML frontmatter: {e}", file=sys.stderr)
        return None


def validate_schema(frontmatter: Dict[str, Any], file_path: str) -> List[str]:
    """Validate frontmatter against schema requirements."""
    errors = []
    
    # Determine category
    category = frontmatter.get("category")
    if not category:
        errors.append("Missing 'category' field in frontmatter")
        return errors
    
    if category not in SCHEMAS:
        errors.append(f"Unknown category '{category}'. Must be one of: {', '.join(SCHEMAS.keys())}")
        return errors
    
    schema = SCHEMAS[category]
    
    # Check required fields
    for field in schema["required_fields"]:
        if field not in frontmatter:
            errors.append(f"Missing required field: '{field}'")
    
    # Check field types
    for field, expected_type in schema["field_types"].items():
        if field in frontmatter:
            value = frontmatter[field]
            # Allow datetime/date objects for date fields (YAML parser converts them)
            if field in ["created_at", "last_updated"] and isinstance(value, (datetime, date)):
                continue
            if not isinstance(value, expected_type):
                errors.append(
                    f"Field '{field}' has wrong type. "
                    f"Expected {expected_type.__name__}, got {type(value).__name__}"
                )
    
    # Check field constraints
    for field, constraint in schema.get("field_constraints", {}).items():
        if field in frontmatter:
            value = frontmatter[field]
            if not constraint(value):
                errors.append(f"Field '{field}' has invalid value: '{value}'")
    
    # Validate resource name format (kebab-case)
    if "resource" in frontmatter:
        resource = frontmatter["resource"]
        if not re.match(r'^[a-z0-9]+(-[a-z0-9]+)*$', resource):
            errors.append(
                f"Field 'resource' must be in kebab-case format. Got: '{resource}'"
            )
    
    # Validate date format (ISO 8601)
    date_fields = ["created_at", "last_updated"]
    for field in date_fields:
        if field in frontmatter:
            date_value = frontmatter[field]
            # Convert datetime objects to string (YAML parser may parse dates)
            if hasattr(date_value, 'isoformat'):
                date_value = date_value.isoformat()
            # Convert to string if not already
            date_value = str(date_value)
            # Basic ISO 8601 check (YYYY-MM-DDTHH:MM:SSZ or YYYY-MM-DD)
            if not re.match(r'^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2})?', date_value):
                errors.append(
                    f"Field '{field}' must be in ISO 8601 format (YYYY-MM-DDTHH:MM:SSZ or YYYY-MM-DD). "
                    f"Got: '{date_value}'"
                )
    
    return errors


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 validate_doc_schemas.py <file_path>", file=sys.stderr)
        sys.exit(1)
    
    file_path = Path(sys.argv[1])
    
    if not file_path.exists():
        print(f"Error: File not found: {file_path}", file=sys.stderr)
        sys.exit(1)
    
    # Read file content
    try:
        content = file_path.read_text()
    except Exception as e:
        print(f"Error reading file: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Extract frontmatter
    frontmatter = extract_frontmatter(content)
    if frontmatter is None:
        print("Error: No valid YAML frontmatter found", file=sys.stderr)
        sys.exit(1)
    
    # Validate schema
    errors = validate_schema(frontmatter, str(file_path))
    
    if errors:
        print(f"Schema validation failed for {file_path}:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        sys.exit(1)
    
    print(f"✓ Schema validation passed for {file_path}")
    sys.exit(0)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Validate documentation filenames against naming conventions.

Filename rules:
1. Must be in kebab-case (lowercase with hyphens)
2. Maximum 3 words (2 hyphens)
3. No timestamps (YYYY, MM, DD patterns)
4. No version numbers (v1, v2, etc.)
5. Must end with .md extension

Valid examples:
- web-service.md ✓
- postgres.md ✓
- disk-issue.md ✓

Invalid examples:
- WebService.md ✗ (not kebab-case)
- web-service-api-gateway.md ✗ (more than 3 words)
- web-service-2025.md ✗ (contains timestamp)
- web-service-v2.md ✗ (contains version)

Usage:
    python3 validate_filenames.py <file_path>

Exit codes:
    0: Filename is valid
    1: Filename is invalid
"""

import sys
import re
from pathlib import Path


def validate_filename(filename: str) -> tuple[bool, list[str]]:
    """
    Validate filename against naming conventions.
    
    Returns:
        Tuple of (is_valid, list_of_errors)
    """
    errors = []
    
    # Remove .md extension for validation
    if not filename.endswith('.md'):
        errors.append("Filename must end with .md extension")
        return False, errors
    
    name_without_ext = filename[:-3]  # Remove .md
    
    # Rule 1: Must be kebab-case (lowercase with hyphens, no other characters)
    if not re.match(r'^[a-z0-9]+(-[a-z0-9]+)*$', name_without_ext):
        errors.append(
            "Filename must be in kebab-case format (lowercase letters, numbers, and hyphens only). "
            f"Got: '{filename}'"
        )
    
    # Rule 2: Maximum 3 words (2 hyphens)
    parts = name_without_ext.split('-')
    if len(parts) > 3:
        errors.append(
            f"Filename must have maximum 3 words (2 hyphens). "
            f"Got {len(parts)} words: '{filename}'"
        )
    
    # Rule 3: No timestamps (YYYY, MM, DD patterns)
    # Check for 4-digit years (1900-2099)
    if re.search(r'(19|20)\d{2}', name_without_ext):
        errors.append(
            f"Filename must not contain timestamps (year pattern detected). "
            f"Got: '{filename}'"
        )
    
    # Check for month/day patterns (01-12, 01-31)
    if re.search(r'-(0[1-9]|1[0-2])(-|$)', name_without_ext):
        errors.append(
            f"Filename must not contain timestamps (month pattern detected). "
            f"Got: '{filename}'"
        )
    
    if re.search(r'-(0[1-9]|[12][0-9]|3[01])(-|$)', name_without_ext):
        errors.append(
            f"Filename must not contain timestamps (day pattern detected). "
            f"Got: '{filename}'"
        )
    
    # Rule 4: No version numbers (v1, v2, version1, etc.)
    if re.search(r'v\d+', name_without_ext, re.IGNORECASE):
        errors.append(
            f"Filename must not contain version numbers (v1, v2, etc.). "
            f"Got: '{filename}'"
        )
    
    if re.search(r'version', name_without_ext, re.IGNORECASE):
        errors.append(
            f"Filename must not contain the word 'version'. "
            f"Got: '{filename}'"
        )
    
    # Additional check: No uppercase letters
    if any(c.isupper() for c in name_without_ext):
        errors.append(
            f"Filename must be lowercase only. "
            f"Got: '{filename}'"
        )
    
    # Additional check: No underscores (common mistake)
    if '_' in name_without_ext:
        errors.append(
            f"Filename must use hyphens (-), not underscores (_). "
            f"Got: '{filename}'"
        )
    
    # Additional check: No spaces
    if ' ' in name_without_ext:
        errors.append(
            f"Filename must not contain spaces. Use hyphens instead. "
            f"Got: '{filename}'"
        )
    
    is_valid = len(errors) == 0
    return is_valid, errors


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 validate_filenames.py <file_path>", file=sys.stderr)
        sys.exit(1)
    
    file_path = Path(sys.argv[1])
    filename = file_path.name
    
    # Validate filename
    is_valid, errors = validate_filename(filename)
    
    if not is_valid:
        print(f"Filename validation failed for '{filename}':", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        print("\nValid filename examples:", file=sys.stderr)
        print("  - web-service.md", file=sys.stderr)
        print("  - postgres.md", file=sys.stderr)
        print("  - disk-issue.md", file=sys.stderr)
        sys.exit(1)
    
    print(f"✓ Filename validation passed for '{filename}'")
    sys.exit(0)


if __name__ == "__main__":
    main()

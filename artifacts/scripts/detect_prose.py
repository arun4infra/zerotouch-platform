#!/usr/bin/env python3
"""
Detect prose paragraphs in documentation (No-Fluff Policy enforcement).

This script enforces the No-Fluff policy by detecting prose paragraphs
in sections where only tables, lists, and code blocks are allowed.

Allowed sections for prose:
- Overview
- Purpose
- Introduction

Forbidden sections for prose (must use tables/lists only):
- Configuration Parameters
- Managed Resources
- Dependencies
- Version History
- Symptoms
- Diagnosis
- Solution
- Prevention

Usage:
    python3 detect_prose.py <file_path>

Exit codes:
    0: No prose violations found
    1: Prose violations detected
"""

import sys
import re
from pathlib import Path
from typing import List, Tuple

# Sections where prose is ALLOWED
ALLOWED_PROSE_SECTIONS = {
    "overview",
    "purpose",
    "introduction",
    "description"
}

# Sections where prose is FORBIDDEN (must use tables/lists/code only)
FORBIDDEN_PROSE_SECTIONS = {
    "configuration parameters",
    "managed resources",
    "dependencies",
    "version history",
    "symptoms",
    "diagnosis",
    "solution",
    "prevention",
    "related incidents",
    "example usage",
    "automated fix",
    "manual steps"
}


def extract_sections(content: str) -> List[Tuple[str, str, int]]:
    """
    Extract sections from markdown content.
    
    Returns:
        List of tuples: (section_name, section_content, line_number)
    """
    sections = []
    
    # Split by ## headers (level 2)
    pattern = r'^## (.+?)$'
    matches = list(re.finditer(pattern, content, re.MULTILINE))
    
    for i, match in enumerate(matches):
        section_name = match.group(1).strip().lower()
        start_pos = match.end()
        
        # Find end of section (next ## or end of file)
        if i + 1 < len(matches):
            end_pos = matches[i + 1].start()
        else:
            end_pos = len(content)
        
        section_content = content[start_pos:end_pos].strip()
        
        # Calculate line number
        line_number = content[:match.start()].count('\n') + 1
        
        sections.append((section_name, section_content, line_number))
    
    return sections


def is_prose_paragraph(text: str) -> bool:
    """
    Detect if text contains prose paragraphs.
    
    Prose is defined as:
    - Multiple sentences in a paragraph (not in a list or table)
    - Narrative text that's not structured data
    
    NOT prose:
    - Tables (| ... |)
    - Bullet lists (- or *)
    - Numbered lists (1. 2. 3.)
    - Code blocks (``` or indented)
    - Single-line statements
    """
    lines = text.split('\n')
    
    for line in lines:
        line = line.strip()
        
        # Skip empty lines
        if not line:
            continue
        
        # Skip tables
        if line.startswith('|') or '|' in line:
            continue
        
        # Skip lists
        if re.match(r'^[-*+]\s', line):  # Bullet list
            continue
        if re.match(r'^\d+\.\s', line):  # Numbered list
            continue
        
        # Skip code blocks
        if line.startswith('```') or line.startswith('    '):
            continue
        
        # Skip YAML/code content
        if line.startswith('---') or ':' in line and not line.endswith(':'):
            continue
        
        # Check if line looks like prose
        # Prose characteristics:
        # - Contains multiple words (> 5)
        # - Contains sentence-ending punctuation
        # - Not a header or special formatting
        
        words = line.split()
        if len(words) > 5:
            # Check if it's a sentence (ends with . ! ?)
            if re.search(r'[.!?]$', line):
                return True
            
            # Check if it's a long descriptive text (likely prose)
            # Even without ending punctuation
            if len(words) > 10 and not line.endswith(':'):
                return True
    
    return False


def detect_prose_violations(content: str) -> List[Tuple[str, int]]:
    """
    Detect prose violations in forbidden sections.
    
    Returns:
        List of tuples: (section_name, line_number)
    """
    violations = []
    
    # Skip frontmatter
    content_without_frontmatter = re.sub(r'^---\s*\n.*?\n---\s*\n', '', content, flags=re.DOTALL)
    
    sections = extract_sections(content_without_frontmatter)
    
    for section_name, section_content, line_number in sections:
        # Check if section is in forbidden list
        if section_name in FORBIDDEN_PROSE_SECTIONS:
            if is_prose_paragraph(section_content):
                violations.append((section_name, line_number))
    
    return violations


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 detect_prose.py <file_path>", file=sys.stderr)
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
    
    # Detect prose violations
    violations = detect_prose_violations(content)
    
    if violations:
        print(f"Prose violations detected in {file_path}:", file=sys.stderr)
        print("\nThe No-Fluff Policy requires tables, lists, or code blocks in these sections:", file=sys.stderr)
        for section_name, line_number in violations:
            print(f"  - Line {line_number}: Section '{section_name.title()}' contains prose paragraphs", file=sys.stderr)
        print("\nPlease rewrite prose as:", file=sys.stderr)
        print("  - Tables (for structured data)", file=sys.stderr)
        print("  - Bullet lists (for items)", file=sys.stderr)
        print("  - Code blocks (for examples)", file=sys.stderr)
        sys.exit(1)
    
    print(f"✓ No prose violations found in {file_path}")
    sys.exit(0)


if __name__ == "__main__":
    main()

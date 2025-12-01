# Design Document: Validator Agent

## Overview

The Validator Agent is a fast gate that validates Spec vs Code alignment in PRs. It uses the OpenAI Agents SDK with GitHub MCP server to fetch PR data, extract contract boundaries, and compare against business specifications.

**Execution Time:** < 30 seconds per PR  
**Location:** `.github/actions/validator/`

---

## Architecture

### High-Level Flow

```
PR Event
   ↓
┌──────────────────────────────────────────────────────────┐
│  Validator Agent Container                                │
│                                                           │
│  1. Parse Inputs                                         │
│     - PR number, GitHub token, OpenAI key                │
│                                                           │
│  2. Check Override (Direct GitHub API)                   │
│     - Fetch PR comments via requests library             │
│     - Scan for @librarian override                       │
│     - If found: post acknowledgment, exit(0)             │
│     - Execution time: < 5 seconds                        │
│                                                           │
│  3. Start GitHub MCP Server (if no override)             │
│     - Launch via MCPServerStdio                          │
│                                                           │
│  4. Create Agent (if no override)                        │
│     - Load prompt from repo                              │
│     - Connect to GitHub MCP server                       │
│                                                           │
│  5. Run Validation Task                                  │
│     - Fetch PR diff and spec                             │
│     - Extract contract boundary                          │
│     - Compare Intent vs Reality                          │
│     - Post gatekeeper comment if mismatch                │
│                                                           │
│  6. Exit with Code                                       │
│     - 0 = pass, 1 = block                                │
└──────────────────────────────────────────────────────────┘
```

---

## Components and Interfaces

### 1. Override Checker (`override_checker.py`)

**Purpose:** Fast check for override comment using direct GitHub API (NOT Agent/LLM)

**Why Direct API:** To keep execution time < 5 seconds and avoid wasting tokens on a simple string search.

**Interface:**
```python
import requests
from typing import Optional, Tuple

def check_for_override(
    owner: str,
    repo: str,
    pr_number: int,
    github_token: str
) -> Tuple[bool, Optional[str]]:
    """
    Check if PR has @librarian override comment.
    
    Uses direct GitHub API call (NOT Agent/MCP) for speed.
    
    Args:
        owner: Repository owner
        repo: Repository name
        pr_number: PR number
        github_token: GitHub token
        
    Returns:
        Tuple of (override_found, author_username)
        
    Execution time: < 5 seconds
    """
    url = f"https://api.github.com/repos/{owner}/{repo}/issues/{pr_number}/comments"
    headers = {
        "Authorization": f"Bearer {github_token}",
        "Accept": "application/vnd.github+json"
    }
    
    response = requests.get(url, headers=headers, timeout=5)
    response.raise_for_status()
    
    comments = response.json()
    for comment in comments:
        if "@librarian override" in comment["body"].lower():
            return True, comment["user"]["login"]
    
    return False, None

def post_override_acknowledgment(
    owner: str,
    repo: str,
    pr_number: int,
    github_token: str,
    author: str
) -> None:
    """
    Post acknowledgment comment for override.
    
    Args:
        owner: Repository owner
        repo: Repository name
        pr_number: PR number
        github_token: GitHub token
        author: Override comment author
    """
    url = f"https://api.github.com/repos/{owner}/{repo}/issues/{pr_number}/comments"
    headers = {
        "Authorization": f"Bearer {github_token}",
        "Accept": "application/vnd.github+json"
    }
    body = f"✅ Override detected. Validation skipped by @{author}"
    
    response = requests.post(url, headers=headers, json={"body": body}, timeout=5)
    response.raise_for_status()
```

**Implementation Notes:**
- Uses `requests` library for direct HTTP calls
- No Agent or MCP server needed for this check
- Timeout set to 5 seconds
- Case-insensitive search for "@librarian override"
- Returns author for audit logging

---

### 2. Main Validator Script (`validator.py`)

**Purpose:** Orchestrate validation workflow with early override exit

**Interface:**
```python
import os
import sys
from agents import Agent, Runner
from agents.mcp import MCPServerStdio
from shared.agent_runner import create_agent_with_mcp, load_prompt_from_file
from override_checker import check_for_override, post_override_acknowledgment

async def main():
    """Main entry point for Validator Agent."""
    # 1. Parse inputs
    pr_number = int(os.environ["PR_NUMBER"])
    github_token = os.environ["GITHUB_TOKEN"]
    openai_key = os.environ["OPENAI_API_KEY"]
    owner, repo = os.environ["GITHUB_REPOSITORY"].split("/")
    
    # 2. Check for override FIRST (before starting MCP/Agent)
    override_found, author = check_for_override(owner, repo, pr_number, github_token)
    
    if override_found:
        # Post acknowledgment and exit immediately
        post_override_acknowledgment(owner, repo, pr_number, github_token, author)
        print(f"Override detected by {author}. Validation skipped.")
        sys.exit(0)
    
    # 3. Start GitHub MCP server (only if no override)
    async with MCPServerStdio(
        name="GitHub",
        params={
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-github"]
        },
        env={"GITHUB_PERSONAL_ACCESS_TOKEN": github_token}
    ) as github_server:
        
        # 4. Create agent
        instructions = load_prompt_from_file(
            "platform/03-intelligence/agents/validator/prompt.md"
        )
        
        agent = await create_agent_with_mcp(
            name="Validator",
            instructions=instructions,
            mcp_servers=[github_server]
        )
        
        # 5. Run validation task
        task = f"""
        Validate PR #{pr_number}:
        1. Fetch PR diff and spec
        2. Extract contract boundary from changed files
        3. Compare Intent (from spec) vs Reality (from code)
        4. If mismatch: post gatekeeper comment with Interpreted Intent
        5. If aligned: confirm validation passed
        """
        
        result = await Runner.run(agent, task)
        
        # 6. Exit with appropriate code
        if "mismatch" in result.final_output.lower():
            sys.exit(1)  # Block PR
        else:
            sys.exit(0)  # Pass

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
```

---

## Dependencies

```txt
# requirements.txt
openai-agents==0.6.1
requests>=2.31.0       # For override checker (direct GitHub API)
pyyaml>=6.0.0
pydantic>=2.0.0
```

**Note:** Requires Python 3.10+ for MCP support.

---

## Performance Considerations

### Override Check Performance
- **Target:** < 5 seconds
- **Method:** Direct GitHub API call (not Agent/LLM)
- **Benefit:** Saves ~25 seconds and avoids wasting tokens

### Full Validation Performance
- **Target:** < 30 seconds total
- **Breakdown:**
  - Override check: < 5s
  - MCP server startup: ~2s
  - Agent initialization: ~1s
  - Validation task: ~20s
  - Post comment: ~2s

---

## Testing Strategy

### Override Checker Tests
```python
# tests/test_override_checker.py
import pytest
from unittest.mock import patch, Mock

def test_check_for_override_found():
    """Test detection of override comment."""
    with patch('requests.get') as mock_get:
        mock_get.return_value.json.return_value = [
            {"body": "@librarian override", "user": {"login": "alice"}}
        ]
        found, author = check_for_override("owner", "repo", 123, "token")
        assert found is True
        assert author == "alice"

def test_check_for_override_not_found():
    """Test when no override comment exists."""
    with patch('requests.get') as mock_get:
        mock_get.return_value.json.return_value = [
            {"body": "Regular comment", "user": {"login": "bob"}}
        ]
        found, author = check_for_override("owner", "repo", 123, "token")
        assert found is False
        assert author is None

def test_check_for_override_case_insensitive():
    """Test case-insensitive matching."""
    with patch('requests.get') as mock_get:
        mock_get.return_value.json.return_value = [
            {"body": "@LIBRARIAN OVERRIDE", "user": {"login": "charlie"}}
        ]
        found, author = check_for_override("owner", "repo", 123, "token")
        assert found is True

def test_check_for_override_timeout():
    """Test timeout handling."""
    with patch('requests.get', side_effect=requests.Timeout):
        with pytest.raises(requests.Timeout):
            check_for_override("owner", "repo", 123, "token")
```

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-02  
**Status:** Ready for Implementation  
**Key Changes:** 
- Override checker uses direct GitHub API (not Agent/MCP)
- Execution flow optimized for early exit on override
- SDK version pinned to openai-agents==0.6.1
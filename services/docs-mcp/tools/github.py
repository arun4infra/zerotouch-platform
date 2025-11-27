import os
import logging
import requests
import base64
from typing import Dict, Any, List, Optional
from mcp.server.fastmcp import FastMCP

logger = logging.getLogger("docs-mcp.github")

def register_github_tools(mcp: FastMCP):
    """Register GitHub integration tools."""

    @mcp.tool()
    async def fetch_from_git(file_path: str, branch: str = "main") -> str:
        """
        Fetch file content from GitHub.
        
        Args:
            file_path: Path to file in repo
            branch: Branch to fetch from
            
        Returns:
            File content as string
        """
        token = os.environ.get("GITHUB_TOKEN")
        repo = os.environ.get("GITHUB_REPO", "bizmatters/infra-platform") # Default or env
        
        if not token:
            return "Error: GITHUB_TOKEN not set"
            
        url = f"https://api.github.com/repos/{repo}/contents/{file_path}?ref={branch}"
        headers = {
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github.v3+json"
        }
        
        try:
            response = requests.get(url, headers=headers)
            response.raise_for_status()
            data = response.json()
            
            if "content" in data:
                content = base64.b64decode(data["content"]).decode('utf-8')
                return content
            else:
                return f"Error: No content found in response for {file_path}"
                
        except Exception as e:
            logger.error(f"GitHub fetch error: {e}")
            return f"Error fetching file: {str(e)}"

    @mcp.tool()
    async def commit_to_pr(pr_number: int, file_path: str, content: str, message: str) -> str:
        """
        Commit a file change to a PR branch.
        
        Args:
            pr_number: PR number to commit to
            file_path: Path of file to create/update
            content: New file content
            message: Commit message
            
        Returns:
            Commit SHA or error message
        """
        token = os.environ.get("GITHUB_TOKEN")
        repo = os.environ.get("GITHUB_REPO", "bizmatters/infra-platform")
        
        if not token:
            return "Error: GITHUB_TOKEN not set"
            
        headers = {
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github.v3+json"
        }
        
        try:
            # 1. Get PR info to find branch
            pr_url = f"https://api.github.com/repos/{repo}/pulls/{pr_number}"
            pr_resp = requests.get(pr_url, headers=headers)
            pr_resp.raise_for_status()
            pr_data = pr_resp.json()
            branch = pr_data["head"]["ref"]
            
            # 2. Get current file SHA (if it exists) to update
            file_url = f"https://api.github.com/repos/{repo}/contents/{file_path}?ref={branch}"
            file_resp = requests.get(file_url, headers=headers)
            
            sha = None
            if file_resp.status_code == 200:
                sha = file_resp.json().get("sha")
            
            # 3. Create/Update file
            payload = {
                "message": message,
                "content": base64.b64encode(content.encode('utf-8')).decode('utf-8'),
                "branch": branch
            }
            if sha:
                payload["sha"] = sha
                
            put_url = f"https://api.github.com/repos/{repo}/contents/{file_path}"
            put_resp = requests.put(put_url, headers=headers, json=payload)
            put_resp.raise_for_status()
            
            commit_sha = put_resp.json()["commit"]["sha"]
            return f"Successfully committed {file_path} to PR #{pr_number}. Commit: {commit_sha}"
            
        except Exception as e:
            logger.error(f"GitHub commit error: {e}")
            return f"Error committing to PR: {str(e)}"

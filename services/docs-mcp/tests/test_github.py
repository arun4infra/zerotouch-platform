import unittest
from unittest.mock import patch, MagicMock
import sys
import os
import base64
import json

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

sys.modules['mcp'] = MagicMock()
sys.modules['mcp.server'] = MagicMock()
sys.modules['mcp.server.fastmcp'] = MagicMock()
sys.modules['qdrant_client'] = MagicMock()
sys.modules['qdrant_client.http'] = MagicMock()
sys.modules['qdrant_client.http.models'] = MagicMock()

from tools.github import register_github_tools

class TestGitHubTools(unittest.IsolatedAsyncioTestCase):
    
    def setUp(self):
        self.mock_mcp = MagicMock()
        self.tools = {}
        
        def capture_tool():
            def decorator(func):
                self.tools[func.__name__] = func
                return func
            return decorator
        
        self.mock_mcp.tool = capture_tool
        register_github_tools(self.mock_mcp)
        
        self.env_patcher = patch.dict(os.environ, {"GITHUB_TOKEN": "fake-token"})
        self.env_patcher.start()
        
    def tearDown(self):
        self.env_patcher.stop()

    @patch('requests.get')
    async def test_fetch_from_git(self, mock_get):
        # Setup mock response
        content = "Hello World"
        b64_content = base64.b64encode(content.encode()).decode()
        
        mock_response = MagicMock()
        mock_response.json.return_value = {"content": b64_content}
        mock_response.raise_for_status.return_value = None
        mock_get.return_value = mock_response
        
        fetch_tool = self.tools['fetch_from_git']
        result = await fetch_tool("README.md")
        
        self.assertEqual(result, "Hello World")
        
    @patch('requests.put')
    @patch('requests.get')
    async def test_commit_to_pr(self, mock_get, mock_put):
        # Mock PR info
        mock_pr_resp = MagicMock()
        mock_pr_resp.json.return_value = {"head": {"ref": "feature-branch"}}
        
        # Mock file check (exists)
        mock_file_resp = MagicMock()
        mock_file_resp.status_code = 200
        mock_file_resp.json.return_value = {"sha": "old-sha"}
        
        mock_get.side_effect = [mock_pr_resp, mock_file_resp]
        
        # Mock put response
        mock_put_resp = MagicMock()
        mock_put_resp.json.return_value = {"commit": {"sha": "new-sha"}}
        mock_put.return_value = mock_put_resp
        
        commit_tool = self.tools['commit_to_pr']
        result = await commit_tool(123, "test.md", "new content", "update")
        
        self.assertIn("Successfully committed", result)
        self.assertIn("new-sha", result)

if __name__ == '__main__':
    unittest.main()

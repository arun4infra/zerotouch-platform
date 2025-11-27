import unittest
from unittest.mock import patch, MagicMock
import sys
import os
import json

# Add parent dir to path to import tools
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Mock mcp.server.fastmcp since it might not be installed
sys.modules['mcp'] = MagicMock()
sys.modules['mcp.server'] = MagicMock()
sys.modules['mcp.server.fastmcp'] = MagicMock()
sys.modules['qdrant_client'] = MagicMock()
sys.modules['qdrant_client.http'] = MagicMock()
sys.modules['qdrant_client.http.models'] = MagicMock()

from tools.validation import register_validation_tools

class TestValidationTools(unittest.IsolatedAsyncioTestCase):
    
    def setUp(self):
        self.mock_mcp = MagicMock()
        # Capture the decorator
        self.mock_mcp.tool = MagicMock(return_value=lambda x: x)
        
    @patch('tools.validation._find_script')
    @patch('subprocess.run')
    async def test_validate_doc_success(self, mock_run, mock_find):
        # Setup
        mock_find.return_value = "/path/to/script.py"
        mock_run.return_value = MagicMock(returncode=0, stdout="", stderr="")
        
        # Register and get the tool function
        # Since register_validation_tools defines the function inside, we need to extract it
        # or modify the code to be testable. 
        # For now, we'll patch FastMCP to capture the registered function.
        
        captured_tool = None
        def capture_tool():
            def decorator(func):
                nonlocal captured_tool
                captured_tool = func
                return func
            return decorator
        
        self.mock_mcp.tool = capture_tool
        
        register_validation_tools(self.mock_mcp)
        
        # Run tool
        result = await captured_tool("test.md")
        data = json.loads(result)
        
        self.assertTrue(data["valid"])
        self.assertEqual(len(data["errors"]), 0)
        
    @patch('tools.validation._find_script')
    @patch('subprocess.run')
    async def test_validate_doc_failure(self, mock_run, mock_find):
        # Setup
        mock_find.return_value = "/path/to/script.py"
        # Fail filename validation
        mock_run.side_effect = [
            MagicMock(returncode=1, stdout="Bad filename", stderr=""), # filename
            MagicMock(returncode=0, stdout="", stderr=""), # schema
            MagicMock(returncode=0, stdout="", stderr="")  # prose
        ]
        
        captured_tool = None
        def capture_tool():
            def decorator(func):
                nonlocal captured_tool
                captured_tool = func
                return func
            return decorator
        
        self.mock_mcp.tool = capture_tool
        register_validation_tools(self.mock_mcp)
        
        result = await captured_tool("test.md")
        data = json.loads(result)
        
        self.assertFalse(data["valid"])
        self.assertIn("Filename validation failed", data["errors"][0])

if __name__ == '__main__':
    unittest.main()

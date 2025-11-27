import unittest
from unittest.mock import patch, MagicMock, mock_open
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

sys.modules['mcp'] = MagicMock()
sys.modules['mcp.server'] = MagicMock()
sys.modules['mcp.server.fastmcp'] = MagicMock()
sys.modules['qdrant_client'] = MagicMock()
sys.modules['qdrant_client.http'] = MagicMock()
sys.modules['qdrant_client.http.models'] = MagicMock()

from tools.creation import register_creation_tools

class TestCreationTools(unittest.IsolatedAsyncioTestCase):
    
    def setUp(self):
        self.mock_mcp = MagicMock()
        self.tools = {}
        
        def capture_tool():
            def decorator(func):
                self.tools[func.__name__] = func
                return func
            return decorator
        
        self.mock_mcp.tool = capture_tool
        register_creation_tools(self.mock_mcp)

    @patch('tools.creation._find_template')
    @patch('os.makedirs')
    @patch('builtins.open', new_callable=mock_open, read_data="title: {title}\n\n# Content")
    async def test_create_doc(self, mock_file, mock_makedirs, mock_find):
        mock_find.return_value = "/path/to/template.md"
        
        create_doc = self.tools['create_doc']
        
        metadata = {"title": "Test Doc"}
        content = {}
        
        path = await create_doc("spec", "test-resource", metadata, content)
        
        self.assertIn("artifacts/specs/test-resource.md", path)
        mock_file.assert_called()
        
    @patch('os.path.exists')
    @patch('builtins.open', new_callable=mock_open, read_data="## Configuration Parameters\n\nOld Table\n\n## Next Section")
    async def test_update_doc(self, mock_file, mock_exists):
        mock_exists.return_value = True
        
        update_doc = self.tools['update_doc']
        
        success = await update_doc("test.md", "Configuration Parameters", "New Table")
        
        self.assertTrue(success)
        
        # Verify write
        handle = mock_file()
        handle.write.assert_called_once()
        written_content = handle.write.call_args[0][0]
        self.assertIn("New Table", written_content)
        self.assertIn("## Next Section", written_content)

if __name__ == '__main__':
    unittest.main()

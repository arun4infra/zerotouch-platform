import unittest
from unittest.mock import patch, MagicMock
import sys
import os
import json

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

sys.modules['mcp'] = MagicMock()
sys.modules['mcp.server'] = MagicMock()
sys.modules['mcp.server.fastmcp'] = MagicMock()
sys.modules['qdrant_client'] = MagicMock()
sys.modules['qdrant_client.http'] = MagicMock()
sys.modules['qdrant_client.http.models'] = MagicMock()

from tools.qdrant import register_qdrant_tools

class TestQdrantTools(unittest.IsolatedAsyncioTestCase):
    
    def setUp(self):
        self.mock_mcp = MagicMock()
        self.tools = {}
        
        def capture_tool():
            def decorator(func):
                self.tools[func.__name__] = func
                return func
            return decorator
        
        self.mock_mcp.tool = capture_tool
        
        # Mock QdrantClient in the module
        with patch('tools.qdrant.QdrantClient') as mock_client_cls:
            self.mock_client = MagicMock()
            mock_client_cls.return_value = self.mock_client
            register_qdrant_tools(self.mock_mcp)

    @patch('tools.qdrant._get_embedding')
    async def test_search_qdrant(self, mock_embed):
        mock_embed.return_value = [0.1, 0.2]
        
        # Mock search results
        mock_hit = MagicMock()
        mock_hit.score = 0.9
        mock_hit.payload = {"file_path": "test.md"}
        self.mock_client.search.return_value = [mock_hit]
        
        search_tool = self.tools['search_qdrant']
        result = await search_tool("query", category="spec")
        
        self.assertIn("'score': 0.9", result)
        self.assertIn("test.md", result)
        self.mock_client.search.assert_called_once()

    @patch('tools.qdrant._get_embedding')
    async def test_sync_to_qdrant(self, mock_embed):
        mock_embed.return_value = [0.1, 0.2]
        
        # Mock collection check
        mock_collections = MagicMock()
        mock_collections.collections = []
        self.mock_client.get_collections.return_value = mock_collections
        
        sync_tool = self.tools['sync_to_qdrant']
        result = await sync_tool("test.md", "content", {"title": "Test"})
        
        self.assertIn("Successfully indexed", result)
        self.mock_client.create_collection.assert_called_once()
        self.mock_client.upsert.assert_called_once()

if __name__ == '__main__':
    unittest.main()

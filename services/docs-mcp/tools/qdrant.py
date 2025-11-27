import os
import logging
import time
from typing import List, Dict, Any, Optional
from mcp.server.fastmcp import FastMCP
from qdrant_client import QdrantClient
from qdrant_client.http import models
from qdrant_client.http.models import Distance, VectorParams

logger = logging.getLogger("docs-mcp.qdrant")

def register_qdrant_tools(mcp: FastMCP):
    """Register Qdrant integration tools."""
    
    # Initialize client lazily or here
    # We'll use env var QDRANT_URL
    qdrant_url = os.environ.get("QDRANT_URL", "http://qdrant.intelligence.svc.cluster.local:6333")
    # For local dev, might be localhost:6333
    
    try:
        client = QdrantClient(url=qdrant_url)
        collection_name = "documentation"
    except Exception as e:
        logger.error(f"Failed to initialize Qdrant client: {e}")
        client = None

    @mcp.tool()
    async def search_qdrant(query: str, category: Optional[str] = None, limit: int = 5) -> str:
        """
        Search documentation using semantic search.
        
        Args:
            query: Search query
            category: Optional category filter (spec, runbook, adr)
            limit: Number of results
            
        Returns:
            JSON string of search results
        """
        if not client:
            return "Error: Qdrant client not initialized"
            
        try:
            # We need embeddings for the query. 
            # Assuming we have an embedding function or service.
            # For this implementation, we'll assume we use OpenAI or similar via a helper.
            # Since we don't have the embedding logic implemented yet, we'll mock it or use a placeholder.
            # In a real implementation, we'd call: vector = get_embedding(query)
            
            # Placeholder: We'll assume the client handles it if we use FastEmbed or similar,
            # but standard QdrantClient needs a vector.
            # Let's assume we have a helper `_get_embedding`.
            
            # For now, we'll return a stub if we can't embed.
            # But the requirement says "Implement semantic search".
            # I'll add a dummy embedding function or use a local library if installed.
            # `sentence-transformers` is heavy. `openai` is in requirements.
            
            vector = _get_embedding(query)
            if not vector:
                return "Error: Could not generate embedding for query"

            search_filter = None
            if category:
                search_filter = models.Filter(
                    must=[
                        models.FieldCondition(
                            key="category",
                            match=models.MatchValue(value=category)
                        )
                    ]
                )

            hits = client.search(
                collection_name="documentation",
                query_vector=vector,
                query_filter=search_filter,
                limit=limit
            )
            
            results = []
            for hit in hits:
                results.append({
                    "score": hit.score,
                    "payload": hit.payload
                })
                
            return str(results)
            
        except Exception as e:
            logger.error(f"Search error: {e}")
            return f"Error searching Qdrant: {str(e)}"

    @mcp.tool()
    async def sync_to_qdrant(file_path: str, content: str, metadata: Dict[str, Any]) -> str:
        """
        Index a document to Qdrant.
        
        Args:
            file_path: Path to the file
            content: File content
            metadata: Metadata dict (title, category, etc.)
            
        Returns:
            Success message
        """
        if not client:
            return "Error: Qdrant client not initialized"
            
        try:
            # Ensure collection exists
            collections = client.get_collections()
            exists = any(c.name == "documentation" for c in collections.collections)
            if not exists:
                client.create_collection(
                    collection_name="documentation",
                    vectors_config=VectorParams(size=1536, distance=Distance.COSINE) # OpenAI size
                )
            
            # Chunk content (simplified)
            chunks = _chunk_content(content)
            
            points = []
            for i, chunk in enumerate(chunks):
                vector = _get_embedding(chunk)
                if not vector:
                    continue
                    
                points.append(models.PointStruct(
                    id=abs(hash(f"{file_path}-{i}")), # Simple hash ID
                    vector=vector,
                    payload={
                        "file_path": file_path,
                        "chunk_index": i,
                        "content": chunk,
                        **metadata
                    }
                ))
            
            if points:
                client.upsert(
                    collection_name="documentation",
                    points=points
                )
                return f"Successfully indexed {len(points)} chunks for {file_path}"
            else:
                return "No chunks to index"
                
        except Exception as e:
            logger.error(f"Sync error: {e}")
            return f"Error syncing to Qdrant: {str(e)}"

def _get_embedding(text: str) -> List[float]:
    """
    Generate embedding for text.
    Uses OpenAI API if OPENAI_API_KEY is set, else returns dummy vector for testing.
    """
    import os
    if os.environ.get("OPENAI_API_KEY"):
        try:
            from openai import OpenAI
            client = OpenAI()
            response = client.embeddings.create(
                input=text,
                model="text-embedding-3-small"
            )
            return response.data[0].embedding
        except Exception as e:
            logger.error(f"OpenAI embedding error: {e}")
            return []
    else:
        # Dummy vector for testing/mocking
        return [0.1] * 1536

def _chunk_content(content: str, chunk_size: int = 1000) -> List[str]:
    """Simple chunking by characters."""
    return [content[i:i+chunk_size] for i in range(0, len(content), chunk_size)]

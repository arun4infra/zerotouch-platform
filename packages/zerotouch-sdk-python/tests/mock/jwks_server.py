"""Mock JWKS server for testing JWT validation."""
import json
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread
from pathlib import Path


class JWKSHandler(BaseHTTPRequestHandler):
    """HTTP handler for JWKS endpoints."""
    
    def do_GET(self):
        """Handle GET requests."""
        if self.path == "/.well-known/jwks.json":
            # Load JWKS data from testdata
            testdata_path = Path(__file__).parent.parent / "testdata" / "jwks.json"
            with open(testdata_path, 'r') as f:
                jwks_data = f.read()
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(jwks_data.encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        """Suppress log messages."""
        pass


class MockJWKSServer:
    """Mock JWKS server for testing.
    
    Usage:
        server = MockJWKSServer()
        server.start()
        # Use server.jwks_url in tests
        server.stop()
        
        # Or use as context manager:
        with MockJWKSServer() as server:
            # Use server.jwks_url
            pass
    """
    
    def __init__(self, port=0):
        """Initialize mock server.
        
        Args:
            port: Port to bind to (0 for random available port)
        """
        self.server = HTTPServer(('localhost', port), JWKSHandler)
        self.port = self.server.server_address[1]
        self.jwks_url = f"http://localhost:{self.port}/.well-known/jwks.json"
        self.url = self.jwks_url  # Backward compatibility
        self.thread = None
    
    def start(self):
        """Start the mock server in background thread."""
        self.thread = Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
    
    def stop(self):
        """Stop the mock server."""
        if self.server:
            self.server.shutdown()
            self.server.server_close()
        if self.thread:
            self.thread.join(timeout=1)
    
    def __enter__(self):
        """Context manager entry."""
        self.start()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.stop()
        return False

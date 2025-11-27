import os
import subprocess
import json
import logging
from typing import List, Dict, Any, Optional
from mcp.server.fastmcp import FastMCP

logger = logging.getLogger("docs-mcp.validation")

def register_validation_tools(mcp: FastMCP):
    """Register validation tools with the MCP server."""

    @mcp.tool()
    async def validate_doc(file_path: str) -> str:
        """
        Validate a documentation file against standards (schema, prose, filename).
        
        Args:
            file_path: Relative path to the file to validate (e.g., 'artifacts/specs/webservice.md')
            
        Returns:
            JSON string containing validation results (valid: bool, errors: List[str])
        """
        logger.info(f"Validating document: {file_path}")
        
        results = {
            "valid": True,
            "errors": []
        }
        
        # 1. Validate Filename
        try:
            # We assume the script is available in the container at /app/artifacts/scripts/
            # or locally at ../../artifacts/scripts/
            # We'll try to locate the script
            script_path = _find_script("validate_filenames.py")
            if script_path:
                cmd = ["python3", script_path, file_path]
                proc = subprocess.run(cmd, capture_output=True, text=True)
                if proc.returncode != 0:
                    results["valid"] = False
                    results["errors"].append(f"Filename validation failed: {proc.stdout.strip()} {proc.stderr.strip()}")
            else:
                results["errors"].append("Could not find validate_filenames.py script")
        except Exception as e:
            results["valid"] = False
            results["errors"].append(f"Error running filename validation: {str(e)}")

        # 2. Validate Schema (Frontmatter)
        try:
            script_path = _find_script("validate_doc_schemas.py")
            if script_path:
                cmd = ["python3", script_path, file_path]
                proc = subprocess.run(cmd, capture_output=True, text=True)
                if proc.returncode != 0:
                    results["valid"] = False
                    results["errors"].append(f"Schema validation failed: {proc.stdout.strip()} {proc.stderr.strip()}")
            else:
                results["errors"].append("Could not find validate_doc_schemas.py script")
        except Exception as e:
            results["valid"] = False
            results["errors"].append(f"Error running schema validation: {str(e)}")

        # 3. Detect Prose (No-Fluff Policy)
        try:
            script_path = _find_script("detect_prose.py")
            if script_path:
                cmd = ["python3", script_path, file_path]
                proc = subprocess.run(cmd, capture_output=True, text=True)
                if proc.returncode != 0:
                    results["valid"] = False
                    results["errors"].append(f"Prose detection failed: {proc.stdout.strip()}")
            else:
                results["errors"].append("Could not find detect_prose.py script")
        except Exception as e:
            results["valid"] = False
            results["errors"].append(f"Error running prose detection: {str(e)}")

        return json.dumps(results, indent=2)

def _find_script(script_name: str) -> Optional[str]:
    """Locate validation script in expected locations."""
    possible_paths = [
        f"artifacts/scripts/{script_name}",           # Local dev relative to root
        f"../../artifacts/scripts/{script_name}",     # Local dev relative to tools dir
        f"/app/artifacts/scripts/{script_name}",      # Docker container
        f"./scripts/{script_name}"                    # Fallback
    ]
    
    for path in possible_paths:
        if os.path.exists(path):
            return path
            
    return None

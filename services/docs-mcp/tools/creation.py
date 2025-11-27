import os
import logging
import shutil
import datetime
import re
from typing import Dict, Any, Optional
from mcp.server.fastmcp import FastMCP

logger = logging.getLogger("docs-mcp.creation")

def register_creation_tools(mcp: FastMCP):
    """Register document creation tools."""

    @mcp.tool()
    async def create_doc(category: str, resource: str, metadata: Dict[str, Any], content: Dict[str, Any]) -> str:
        """
        Create a new document from a template.
        
        Args:
            category: 'spec', 'runbook', or 'adr'
            resource: Name of the resource (e.g., 'webservice', 'postgres')
            metadata: Dictionary of frontmatter fields (title, etc.)
            content: Dictionary of content sections to populate
            
        Returns:
            Path to the created file
        """
        logger.info(f"Creating doc: category={category}, resource={resource}")
        
        # 1. Determine template and target path
        template_name = f"{category}-template.md"
        template_path = _find_template(template_name)
        
        if not template_path:
            raise FileNotFoundError(f"Template {template_name} not found")
            
        # Generate filename
        if category == 'adr':
            # Auto-increment logic would go here, simplified for now
            filename = f"000-{resource}.md"
            target_dir = "artifacts/architecture"
        elif category == 'runbook':
            filename = f"{resource}.md"
            target_dir = f"artifacts/runbooks/{metadata.get('service', 'general')}"
        else: # spec
            filename = f"{resource}.md"
            target_dir = "artifacts/specs"
            
        target_path = os.path.join(target_dir, filename)
        
        # Ensure directory exists
        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        
        # 2. Read template
        with open(template_path, 'r') as f:
            template_content = f.read()
            
        # 3. Replace placeholders
        # This is a simple replacement. Jinja2 would be better but keeping dependencies low.
        final_content = template_content
        
        # Update frontmatter
        today = datetime.datetime.now().strftime("%Y-%m-%d")
        metadata['created_at'] = metadata.get('created_at', today)
        metadata['last_updated'] = today
        metadata['resource'] = resource
        metadata['category'] = category
        
        # We need to parse and replace frontmatter. 
        # For this implementation, we'll assume the template has specific placeholders
        # or we just regex replace common fields.
        
        for key, value in metadata.items():
            # Replace {key} or specific patterns
            # Simple approach: Replace lines starting with "key:"
            pattern = re.compile(f"^{key}:.*$", re.MULTILINE)
            if pattern.search(final_content):
                final_content = pattern.sub(f"{key}: {value}", final_content)
        
        # 4. Write file
        with open(target_path, 'w') as f:
            f.write(final_content)
            
        logger.info(f"Created file at {target_path}")
        return target_path

    @mcp.tool()
    async def update_doc(file_path: str, section: str, new_content: str) -> bool:
        """
        Update a specific section in a document.
        
        Args:
            file_path: Path to the file
            section: Header name of the section to update (e.g., "Configuration Parameters")
            new_content: New content for that section (table/list)
            
        Returns:
            True if successful
        """
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"File {file_path} not found")
            
        with open(file_path, 'r') as f:
            content = f.read()
            
        # Regex to find section
        # Matches ## Section Name ... until next ## or end of file
        pattern = re.compile(f"(## {re.escape(section)}).*?(?=\n## |\Z)", re.DOTALL)
        
        if not pattern.search(content):
            # Try appending if not found? Or error?
            # For now, append if it's a standard section, else error
            raise ValueError(f"Section '{section}' not found in {file_path}")
            
        replacement = f"## {section}\n\n{new_content}\n"
        new_file_content = pattern.sub(replacement, content)
        
        with open(file_path, 'w') as f:
            f.write(new_file_content)
            
        return True

def _find_template(template_name: str) -> Optional[str]:
    """Locate template file."""
    possible_paths = [
        f"artifacts/templates/{template_name}",
        f"../../artifacts/templates/{template_name}",
        f"/app/artifacts/templates/{template_name}"
    ]
    
    for path in possible_paths:
        if os.path.exists(path):
            return path
    return None

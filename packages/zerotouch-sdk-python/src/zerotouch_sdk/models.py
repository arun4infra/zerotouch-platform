"""Data models for authentication context."""
from dataclasses import dataclass
from typing import List


@dataclass(frozen=True)
class AuthContext:
    """Immutable container for authenticated user context.
    
    Attributes:
        user_id: UUID from 'sub' claim
        org_id: UUID from 'org' claim
        role: Role string (not validated against enum)
        membership_version: Integer from 'ver' claim
        raw_token: Original JWT for database authentication
    """
    user_id: str
    org_id: str
    role: str
    membership_version: int
    raw_token: str
    
    def has_role(self, allowed_roles: List[str]) -> bool:
        """Check if user's role is in allowed list.
        
        Prevents brittle string comparisons in service code.
        Handles forward compatibility when Identity Service adds new roles.
        
        Args:
            allowed_roles: List of role strings to check against
            
        Returns:
            True if user's role matches any allowed role
        """
        return self.role in allowed_roles

"""
Credentials management for the MindX system.

This module provides utilities for loading credentials from various sources,
with fallbacks to ensure the application can run in different environments.
"""

import os
import json
from pathlib import Path
from typing import Dict, Any, Optional

def load_google_credentials(credential_type: str = "service_account") -> Dict[str, Any]:
    """
    Load Google credentials from environment or file system.
    
    Args:
        credential_type: Type of credentials to load ("service_account" or "authorized_user")
        
    Returns:
        Dictionary containing the credentials
        
    Raises:
        FileNotFoundError: If credentials file cannot be found
        ValueError: If environment variable is not set and file doesn't exist
    """
    # First try environment variable
    if credential_type == "service_account":
        env_var = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS_JSON")
        file_path = Path("backend/google-credentials.json")
    else:  # authorized_user
        env_var = os.environ.get("GOOGLE_OAUTH_CREDENTIALS_JSON")
        file_path = Path("google-credentials.json")
    
    # If environment variable is set, parse it
    if env_var:
        try:
            return json.loads(env_var)
        except json.JSONDecodeError:
            print(f"Warning: Could not parse {credential_type} credentials from environment variable")
    
    # Otherwise try to load from file
    if file_path.exists():
        try:
            with open(file_path, "r") as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            raise ValueError(f"Failed to load {credential_type} credentials from {file_path}: {str(e)}")
    
    # Final fallback - check for template and warn
    if Path(f"{file_path}.template").exists():
        raise ValueError(
            f"Credentials file {file_path} not found. Please copy {file_path}.template "
            f"to {file_path} and fill in the placeholders with your actual credentials."
        )
    
    raise FileNotFoundError(
        f"Could not locate {credential_type} credentials file. "
        f"Please set GOOGLE_APPLICATION_CREDENTIALS_JSON environment variable or "
        f"create a {file_path} file."
    )

def get_google_service_account_credentials() -> Dict[str, Any]:
    """Get service account credentials for backend services."""
    return load_google_credentials("service_account")

def get_google_oauth_credentials() -> Dict[str, Any]:
    """Get OAuth credentials for user authentication."""
    return load_google_credentials("authorized_user") 
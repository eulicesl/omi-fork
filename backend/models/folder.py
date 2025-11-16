from datetime import datetime, timezone
from typing import Optional, List
from pydantic import BaseModel, Field


class Folder(BaseModel):
    id: str = Field(description="Unique identifier for the folder")
    uid: str = Field(description="User ID who owns this folder")
    name: str = Field(description="Name of the folder")
    color: Optional[str] = Field(default=None, description="Hex color code for the folder (e.g., #FF5733)")
    icon: Optional[str] = Field(default=None, description="Icon name or emoji for the folder")
    position: int = Field(default=0, description="Display position/order of the folder")
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class CreateFolder(BaseModel):
    name: str = Field(description="Name of the folder")
    color: Optional[str] = Field(default=None, description="Hex color code for the folder")
    icon: Optional[str] = Field(default=None, description="Icon name or emoji for the folder")
    position: int = Field(default=0, description="Display position/order of the folder")


class UpdateFolder(BaseModel):
    name: Optional[str] = None
    color: Optional[str] = None
    icon: Optional[str] = None
    position: Optional[int] = None


class ReorderFolders(BaseModel):
    folder_ids: List[str] = Field(description="Ordered list of folder IDs")

from datetime import datetime, timezone
from typing import Optional
from pydantic import BaseModel, Field

from database._client import document_id_from_seed


class Folder(BaseModel):
    """Model for organizing memories into folders"""
    name: str = Field(description="The name of the folder")
    color: Optional[str] = Field(description="Color hex code for the folder (e.g., #FF5733)", default=None)
    icon: Optional[str] = Field(description="Icon identifier for the folder", default=None)
    position: int = Field(description="Position/order of the folder for display", default=0)


class FolderDB(Folder):
    """Database model for folders with additional metadata"""
    id: str
    uid: str
    created_at: datetime
    updated_at: datetime

    @staticmethod
    def from_folder(folder: Folder, uid: str) -> 'FolderDB':
        """Create a FolderDB instance from a Folder"""
        return FolderDB(
            id=document_id_from_seed(f"{uid}_{folder.name}_{datetime.now(timezone.utc).timestamp()}"),
            uid=uid,
            name=folder.name,
            color=folder.color,
            icon=folder.icon,
            position=folder.position,
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
        )


class FolderUpdate(BaseModel):
    """Model for updating folder properties"""
    name: Optional[str] = None
    color: Optional[str] = None
    icon: Optional[str] = None
    position: Optional[int] = None

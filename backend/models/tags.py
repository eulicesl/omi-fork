from datetime import datetime, timezone
from typing import Optional
from pydantic import BaseModel, Field

from database._client import document_id_from_seed


class Tag(BaseModel):
    """Model for tagging memories"""
    name: str = Field(description="The name of the tag")
    color: Optional[str] = Field(description="Color hex code for the tag (e.g., #FF5733)", default=None)


class TagDB(Tag):
    """Database model for tags with additional metadata"""
    id: str
    uid: str
    created_at: datetime
    updated_at: datetime

    @staticmethod
    def from_tag(tag: Tag, uid: str) -> 'TagDB':
        """Create a TagDB instance from a Tag"""
        return TagDB(
            id=document_id_from_seed(f"{uid}_{tag.name}"),
            uid=uid,
            name=tag.name,
            color=tag.color,
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
        )


class TagUpdate(BaseModel):
    """Model for updating tag properties"""
    name: Optional[str] = None
    color: Optional[str] = None

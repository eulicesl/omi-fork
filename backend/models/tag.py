from datetime import datetime, timezone
from typing import Optional
from pydantic import BaseModel, Field


class Tag(BaseModel):
    id: str = Field(description="Unique identifier for the tag")
    uid: str = Field(description="User ID who owns this tag")
    name: str = Field(description="Name of the tag")
    color: Optional[str] = Field(default=None, description="Hex color code for the tag (e.g., #FF5733)")
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class CreateTag(BaseModel):
    name: str = Field(description="Name of the tag")
    color: Optional[str] = Field(default=None, description="Hex color code for the tag")


class UpdateTag(BaseModel):
    name: Optional[str] = None
    color: Optional[str] = None

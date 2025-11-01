from typing import List

from fastapi import APIRouter, Depends, HTTPException

import database.tags as tags_db
import database.memories as memories_db
from models.tags import Tag, TagDB, TagUpdate
from utils.other import endpoints as auth

router = APIRouter()


@router.post('/v3/tags', tags=['tags'], response_model=TagDB)
def create_tag(tag: Tag, uid: str = Depends(auth.get_current_user_uid)):
    """Create a new tag for organizing memories"""
    # Check if tag with this name already exists
    existing_tag = tags_db.get_tag_by_name(uid, tag.name)
    if existing_tag:
        # Return existing tag instead of creating a duplicate
        return existing_tag

    tag_db = TagDB.from_tag(tag, uid)
    tags_db.create_tag(uid, tag_db.dict())
    return tag_db


@router.get('/v3/tags', tags=['tags'], response_model=List[TagDB])
def get_tags(limit: int = 100, offset: int = 0, uid: str = Depends(auth.get_current_user_uid)):
    """Get all tags for the current user"""
    tags = tags_db.get_tags(uid, limit, offset)
    return tags


@router.get('/v3/tags/{tag_id}', tags=['tags'], response_model=TagDB)
def get_tag(tag_id: str, uid: str = Depends(auth.get_current_user_uid)):
    """Get a specific tag by ID"""
    tag = tags_db.get_tag(uid, tag_id)
    if tag is None:
        raise HTTPException(status_code=404, detail="Tag not found")
    return tag


@router.patch('/v3/tags/{tag_id}', tags=['tags'], response_model=TagDB)
def update_tag(tag_id: str, updates: TagUpdate, uid: str = Depends(auth.get_current_user_uid)):
    """Update a tag's properties"""
    # Verify tag exists
    tag = tags_db.get_tag(uid, tag_id)
    if tag is None:
        raise HTTPException(status_code=404, detail="Tag not found")

    # Only include non-None values in the update
    update_dict = {k: v for k, v in updates.dict().items() if v is not None}

    if not update_dict:
        raise HTTPException(status_code=400, detail="No valid fields to update")

    # If renaming, check for duplicates
    if 'name' in update_dict:
        existing_tag = tags_db.get_tag_by_name(uid, update_dict['name'])
        if existing_tag and existing_tag['id'] != tag_id:
            raise HTTPException(status_code=400, detail="A tag with this name already exists")

    tags_db.update_tag(uid, tag_id, update_dict)

    # Return updated tag
    updated_tag = tags_db.get_tag(uid, tag_id)
    return updated_tag


@router.delete('/v3/tags/{tag_id}', tags=['tags'])
def delete_tag(tag_id: str, uid: str = Depends(auth.get_current_user_uid)):
    """Delete a tag and remove it from all memories"""
    # Verify tag exists
    tag = tags_db.get_tag(uid, tag_id)
    if tag is None:
        raise HTTPException(status_code=404, detail="Tag not found")

    # Remove tag from all memories that contain it
    memories_updated = memories_db.remove_tag_from_all_memories(uid, tag_id)

    # Delete the tag
    tags_db.delete_tag(uid, tag_id)

    return {'status': 'ok', 'memories_updated': memories_updated}

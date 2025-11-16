from fastapi import APIRouter, Depends, HTTPException
from typing import List
import uuid

import database.tags as tags_db
from models.tag import Tag, CreateTag, UpdateTag
from utils.other import endpoints as auth

router = APIRouter()


@router.post("/v3/tags", response_model=Tag, tags=['tags'])
def create_tag(
    tag_data: CreateTag,
    uid: str = Depends(auth.get_current_user_uid)
):
    """Create a new tag"""
    tag_dict = tag_data.dict()
    tag_dict['id'] = str(uuid.uuid4())
    tag_dict['uid'] = uid

    created_tag = tags_db.create_tag(uid, tag_dict)
    return Tag(**created_tag)


@router.get("/v3/tags", response_model=List[Tag], tags=['tags'])
def get_tags(
    limit: int = 100,
    offset: int = 0,
    uid: str = Depends(auth.get_current_user_uid)
):
    """Get all tags for the current user"""
    tags = tags_db.get_tags(uid, limit, offset)
    return [Tag(**tag) for tag in tags]


@router.get("/v3/tags/{tag_id}", response_model=Tag, tags=['tags'])
def get_tag(
    tag_id: str,
    uid: str = Depends(auth.get_current_user_uid)
):
    """Get a specific tag by ID"""
    tag = tags_db.get_tag(uid, tag_id)
    if tag is None:
        raise HTTPException(status_code=404, detail="Tag not found")
    return Tag(**tag)


@router.patch("/v3/tags/{tag_id}", response_model=Tag, tags=['tags'])
def update_tag(
    tag_id: str,
    update_data: UpdateTag,
    uid: str = Depends(auth.get_current_user_uid)
):
    """Update a tag"""
    tag = tags_db.get_tag(uid, tag_id)
    if tag is None:
        raise HTTPException(status_code=404, detail="Tag not found")

    update_dict = {k: v for k, v in update_data.dict().items() if v is not None}
    if update_dict:
        tags_db.update_tag(uid, tag_id, update_dict)

    updated_tag = tags_db.get_tag(uid, tag_id)
    return Tag(**updated_tag)


@router.delete("/v3/tags/{tag_id}", tags=['tags'])
def delete_tag(
    tag_id: str,
    uid: str = Depends(auth.get_current_user_uid)
):
    """Delete a tag"""
    tag = tags_db.get_tag(uid, tag_id)
    if tag is None:
        raise HTTPException(status_code=404, detail="Tag not found")

    # Clean up tag references in conversations
    import database.conversations as conversations_db
    from models.conversation import Conversation
    offset = 0
    limit = 1000
    while True:
        conversations = conversations_db.get_conversations(uid, limit=limit, offset=offset)
        if not conversations:
            break
        for conv in conversations:
            conversation_obj = Conversation(**conv)
            if tag_id in conversation_obj.tag_ids:
                updated_tags = [tid for tid in conversation_obj.tag_ids if tid != tag_id]
                conversations_db.update_conversation(uid, conv['id'], {'tag_ids': updated_tags})
        offset += limit

    tags_db.delete_tag(uid, tag_id)
    return {"message": "Tag deleted successfully"}

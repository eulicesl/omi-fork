from datetime import datetime, timezone
from typing import List, Optional
from ._client import db


def create_tag(uid: str, tag_data: dict) -> dict:
    """Create a new tag for a user"""
    tag_id = tag_data['id']
    tag_ref = db.collection('users').document(uid).collection('tags').document(tag_id)
    tag_ref.set(tag_data)
    return tag_data


def get_tags(uid: str, limit: int = 100, offset: int = 0) -> List[dict]:
    """Get all tags for a user"""
    query = (
        db.collection('users')
        .document(uid)
        .collection('tags')
        .order_by('name')
        .limit(limit)
        .offset(offset)
    )
    tags = [doc.to_dict() for doc in query.stream()]
    return tags


def get_tag(uid: str, tag_id: str) -> Optional[dict]:
    """Get a specific tag by ID"""
    tag_ref = db.collection('users').document(uid).collection('tags').document(tag_id)
    tag = tag_ref.get()
    if tag.exists:
        return tag.to_dict()
    return None


def update_tag(uid: str, tag_id: str, update_data: dict) -> bool:
    """Update a tag"""
    tag_ref = db.collection('users').document(uid).collection('tags').document(tag_id)
    update_data['updated_at'] = datetime.now(timezone.utc)
    tag_ref.update(update_data)
    return True


def delete_tag(uid: str, tag_id: str) -> bool:
    """Delete a tag"""
    tag_ref = db.collection('users').document(uid).collection('tags').document(tag_id)
    tag_ref.delete()
    return True

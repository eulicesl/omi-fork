from datetime import datetime, timezone
from typing import List, Optional, Dict, Any

from google.cloud import firestore
from google.cloud.firestore_v1 import FieldFilter

from ._client import db

users_collection = 'users'
tags_collection = 'tags'


# *****************************
# ********** CRUD *************
# *****************************


def get_tags(uid: str, limit: int = 100, offset: int = 0) -> List[Dict[str, Any]]:
    """Get all tags for a user, ordered by creation date"""
    tags_ref = db.collection(users_collection).document(uid).collection(tags_collection)
    tags_ref = tags_ref.order_by('created_at', direction=firestore.Query.DESCENDING)

    if limit:
        tags_ref = tags_ref.limit(limit)
    if offset:
        tags_ref = tags_ref.offset(offset)

    tags = [doc.to_dict() for doc in tags_ref.stream()]
    return tags


def get_tag(uid: str, tag_id: str) -> Optional[Dict[str, Any]]:
    """Get a specific tag by ID"""
    tag_ref = db.collection(users_collection).document(uid).collection(tags_collection).document(tag_id)
    tag_snapshot = tag_ref.get()

    if not tag_snapshot.exists:
        return None

    return tag_snapshot.to_dict()


def get_tag_by_name(uid: str, name: str) -> Optional[Dict[str, Any]]:
    """Get a tag by its name (case-insensitive)"""
    tags_ref = db.collection(users_collection).document(uid).collection(tags_collection)
    query = tags_ref.where(filter=FieldFilter('name', '==', name)).limit(1)

    results = [doc.to_dict() for doc in query.stream()]
    return results[0] if results else None


def create_tag(uid: str, data: dict) -> None:
    """Create a new tag"""
    user_ref = db.collection(users_collection).document(uid)
    tags_ref = user_ref.collection(tags_collection)
    tag_ref = tags_ref.document(data['id'])
    tag_ref.set(data)


def update_tag(uid: str, tag_id: str, updates: dict) -> None:
    """Update an existing tag"""
    tag_ref = db.collection(users_collection).document(uid).collection(tags_collection).document(tag_id)

    # Add updated_at timestamp
    updates['updated_at'] = datetime.now(timezone.utc)

    tag_ref.update(updates)


def delete_tag(uid: str, tag_id: str) -> None:
    """Delete a tag"""
    tag_ref = db.collection(users_collection).document(uid).collection(tags_collection).document(tag_id)
    tag_ref.delete()


def delete_all_tags(uid: str) -> None:
    """Delete all tags for a user"""
    batch = db.batch()
    user_ref = db.collection(users_collection).document(uid)
    tags_ref = user_ref.collection(tags_collection)

    for doc in tags_ref.stream():
        batch.delete(doc.reference)

    batch.commit()


def get_tag_count(uid: str) -> int:
    """Get the total number of tags for a user"""
    tags_ref = db.collection(users_collection).document(uid).collection(tags_collection)
    # Use a count aggregation query for efficiency
    count_query = tags_ref.count()
    result = count_query.get()
    return result[0][0].value if result else 0

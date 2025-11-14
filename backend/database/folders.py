from datetime import datetime, timezone
from typing import List, Optional, Dict, Any

from ._client import db

users_collection = 'users'
folders_collection = 'folders'


# *****************************
# ********** CRUD *************
# *****************************


def get_folders(uid: str, limit: int = 100, offset: int = 0) -> List[Dict[str, Any]]:
    """Get all folders for a user, ordered by position"""
    folders_ref = db.collection(users_collection).document(uid).collection(folders_collection)
    folders_ref = folders_ref.order_by('position').order_by('created_at')

    if limit:
        folders_ref = folders_ref.limit(limit)
    if offset:
        folders_ref = folders_ref.offset(offset)

    folders = [doc.to_dict() for doc in folders_ref.stream()]
    return folders


def get_folder(uid: str, folder_id: str) -> Optional[Dict[str, Any]]:
    """Get a specific folder by ID"""
    folder_ref = db.collection(users_collection).document(uid).collection(folders_collection).document(folder_id)
    folder_snapshot = folder_ref.get()

    if not folder_snapshot.exists:
        return None

    return folder_snapshot.to_dict()


def create_folder(uid: str, data: dict) -> None:
    """Create a new folder"""
    user_ref = db.collection(users_collection).document(uid)
    folders_ref = user_ref.collection(folders_collection)
    folder_ref = folders_ref.document(data['id'])
    folder_ref.set(data)


def update_folder(uid: str, folder_id: str, updates: dict) -> None:
    """Update an existing folder"""
    folder_ref = db.collection(users_collection).document(uid).collection(folders_collection).document(folder_id)

    # Add updated_at timestamp
    updates['updated_at'] = datetime.now(timezone.utc)

    folder_ref.update(updates)


def delete_folder(uid: str, folder_id: str) -> None:
    """Delete a folder"""
    folder_ref = db.collection(users_collection).document(uid).collection(folders_collection).document(folder_id)
    folder_ref.delete()


def delete_all_folders(uid: str) -> None:
    """Delete all folders for a user"""
    batch = db.batch()
    user_ref = db.collection(users_collection).document(uid)
    folders_ref = user_ref.collection(folders_collection)

    for doc in folders_ref.stream():
        batch.delete(doc.reference)

    batch.commit()


def reorder_folders(uid: str, folder_positions: List[Dict[str, int]]) -> None:
    """
    Update the position of multiple folders

    Args:
        uid: User ID
        folder_positions: List of dicts with 'id' and 'position' keys
    """
    batch = db.batch()
    folders_ref = db.collection(users_collection).document(uid).collection(folders_collection)

    for item in folder_positions:
        folder_ref = folders_ref.document(item['id'])
        batch.update(folder_ref, {
            'position': item['position'],
            'updated_at': datetime.now(timezone.utc)
        })

    batch.commit()


def get_folder_count(uid: str) -> int:
    """Get the total number of folders for a user"""
    folders_ref = db.collection(users_collection).document(uid).collection(folders_collection)
    # Use a count aggregation query for efficiency
    count_query = folders_ref.count()
    result = count_query.get()
    return result[0][0].value if result else 0

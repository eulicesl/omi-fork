from datetime import datetime, timezone
from typing import List, Optional
from google.cloud.firestore_v1 import FieldFilter
from ._client import db


def create_folder(uid: str, folder_data: dict) -> dict:
    """Create a new folder for a user"""
    folder_id = folder_data['id']
    folder_ref = db.collection('users').document(uid).collection('folders').document(folder_id)
    folder_ref.set(folder_data)
    return folder_data


def get_folders(uid: str, limit: int = 100, offset: int = 0) -> List[dict]:
    """Get all folders for a user"""
    query = (
        db.collection('users')
        .document(uid)
        .collection('folders')
        .order_by('position')
        .limit(limit)
        .offset(offset)
    )
    folders = [doc.to_dict() for doc in query.stream()]
    return folders


def get_folder(uid: str, folder_id: str) -> Optional[dict]:
    """Get a specific folder by ID"""
    folder_ref = db.collection('users').document(uid).collection('folders').document(folder_id)
    folder = folder_ref.get()
    if folder.exists:
        return folder.to_dict()
    return None


def update_folder(uid: str, folder_id: str, update_data: dict) -> bool:
    """Update a folder"""
    folder_ref = db.collection('users').document(uid).collection('folders').document(folder_id)
    update_data['updated_at'] = datetime.now(timezone.utc)
    folder_ref.update(update_data)
    return True


def delete_folder(uid: str, folder_id: str) -> bool:
    """Delete a folder"""
    folder_ref = db.collection('users').document(uid).collection('folders').document(folder_id)
    folder_ref.delete()
    return True


def reorder_folders(uid: str, folder_ids: List[str]) -> bool:
    """Reorder folders by updating their position"""
    batch = db.batch()
    for position, folder_id in enumerate(folder_ids):
        folder_ref = db.collection('users').document(uid).collection('folders').document(folder_id)
        batch.update(folder_ref, {
            'position': position,
            'updated_at': datetime.now(timezone.utc)
        })
    batch.commit()
    return True

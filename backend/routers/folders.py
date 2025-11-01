from typing import List

from fastapi import APIRouter, Depends, HTTPException

import database.folders as folders_db
import database.memories as memories_db
from models.folders import Folder, FolderDB, FolderUpdate
from utils.other import endpoints as auth

router = APIRouter()


@router.post('/v3/folders', tags=['folders'], response_model=FolderDB)
def create_folder(folder: Folder, uid: str = Depends(auth.get_current_user_uid)):
    """Create a new folder for organizing memories"""
    folder_db = FolderDB.from_folder(folder, uid)
    folders_db.create_folder(uid, folder_db.dict())
    return folder_db


@router.get('/v3/folders', tags=['folders'], response_model=List[FolderDB])
def get_folders(limit: int = 100, offset: int = 0, uid: str = Depends(auth.get_current_user_uid)):
    """Get all folders for the current user"""
    folders = folders_db.get_folders(uid, limit, offset)
    return folders


@router.get('/v3/folders/{folder_id}', tags=['folders'], response_model=FolderDB)
def get_folder(folder_id: str, uid: str = Depends(auth.get_current_user_uid)):
    """Get a specific folder by ID"""
    folder = folders_db.get_folder(uid, folder_id)
    if folder is None:
        raise HTTPException(status_code=404, detail="Folder not found")
    return folder


@router.patch('/v3/folders/{folder_id}', tags=['folders'], response_model=FolderDB)
def update_folder(folder_id: str, updates: FolderUpdate, uid: str = Depends(auth.get_current_user_uid)):
    """Update a folder's properties"""
    # Verify folder exists
    folder = folders_db.get_folder(uid, folder_id)
    if folder is None:
        raise HTTPException(status_code=404, detail="Folder not found")

    # Only include non-None values in the update
    update_dict = {k: v for k, v in updates.dict().items() if v is not None}

    if not update_dict:
        raise HTTPException(status_code=400, detail="No valid fields to update")

    folders_db.update_folder(uid, folder_id, update_dict)

    # Return updated folder
    updated_folder = folders_db.get_folder(uid, folder_id)
    return updated_folder


@router.delete('/v3/folders/{folder_id}', tags=['folders'])
def delete_folder(folder_id: str, uid: str = Depends(auth.get_current_user_uid)):
    """Delete a folder and remove it from all memories"""
    # Verify folder exists
    folder = folders_db.get_folder(uid, folder_id)
    if folder is None:
        raise HTTPException(status_code=404, detail="Folder not found")

    # Remove folder from all memories that contain it
    memories_updated = memories_db.remove_folder_from_all_memories(uid, folder_id)

    # Delete the folder
    folders_db.delete_folder(uid, folder_id)

    return {'status': 'ok', 'memories_updated': memories_updated}


@router.post('/v3/folders/reorder', tags=['folders'])
def reorder_folders(positions: List[dict], uid: str = Depends(auth.get_current_user_uid)):
    """
    Reorder folders by updating their positions.
    Expects a list of objects with 'id' and 'position' fields.
    """
    if not positions:
        raise HTTPException(status_code=400, detail="No positions provided")

    # Validate that all items have required fields
    for item in positions:
        if 'id' not in item or 'position' not in item:
            raise HTTPException(status_code=400, detail="Each item must have 'id' and 'position' fields")

    folders_db.reorder_folders(uid, positions)
    return {'status': 'ok', 'updated_count': len(positions)}

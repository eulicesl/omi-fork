from fastapi import APIRouter, Depends, HTTPException
from typing import List
import uuid

import database.folders as folders_db
from models.folder import Folder, CreateFolder, UpdateFolder, ReorderFolders
from utils.other import endpoints as auth

router = APIRouter()


@router.post("/v3/folders", response_model=Folder, tags=['folders'])
def create_folder(
    folder_data: CreateFolder,
    uid: str = Depends(auth.get_current_user_uid)
):
    """Create a new folder"""
    folder_dict = folder_data.dict()
    folder_dict['id'] = str(uuid.uuid4())
    folder_dict['uid'] = uid

    created_folder = folders_db.create_folder(uid, folder_dict)
    return Folder(**created_folder)


@router.get("/v3/folders", response_model=List[Folder], tags=['folders'])
def get_folders(
    limit: int = 100,
    offset: int = 0,
    uid: str = Depends(auth.get_current_user_uid)
):
    """Get all folders for the current user"""
    folders = folders_db.get_folders(uid, limit, offset)
    return [Folder(**folder) for folder in folders]


@router.get("/v3/folders/{folder_id}", response_model=Folder, tags=['folders'])
def get_folder(
    folder_id: str,
    uid: str = Depends(auth.get_current_user_uid)
):
    """Get a specific folder by ID"""
    folder = folders_db.get_folder(uid, folder_id)
    if folder is None:
        raise HTTPException(status_code=404, detail="Folder not found")
    return Folder(**folder)


@router.patch("/v3/folders/{folder_id}", response_model=Folder, tags=['folders'])
def update_folder(
    folder_id: str,
    update_data: UpdateFolder,
    uid: str = Depends(auth.get_current_user_uid)
):
    """Update a folder"""
    folder = folders_db.get_folder(uid, folder_id)
    if folder is None:
        raise HTTPException(status_code=404, detail="Folder not found")

    update_dict = {k: v for k, v in update_data.dict().items() if v is not None}
    if update_dict:
        folders_db.update_folder(uid, folder_id, update_dict)

    updated_folder = folders_db.get_folder(uid, folder_id)
    return Folder(**updated_folder)


@router.delete("/v3/folders/{folder_id}", tags=['folders'])
def delete_folder(
    folder_id: str,
    uid: str = Depends(auth.get_current_user_uid)
):
    """Delete a folder"""
    folder = folders_db.get_folder(uid, folder_id)
    if folder is None:
        raise HTTPException(status_code=404, detail="Folder not found")

    # Clean up folder references in conversations
    import database.conversations as conversations_db
    offset = 0
    limit = 1000
    while True:
        conversations = conversations_db.get_conversations(uid, limit=limit, offset=offset)
        if not conversations:
            break
        updated = False
        for conv in conversations:
            if conv.get('folder_id') == folder_id:
                conversations_db.update_conversation(uid, conv['id'], {'folder_id': None})
                updated = True
        if updated:
            offset = 0  # Reset to check from beginning since we updated items
        else:
            offset += limit  # No updates in this batch, move to next batch

    folders_db.delete_folder(uid, folder_id)
    return {"message": "Folder deleted successfully"}


@router.post("/v3/folders/reorder", tags=['folders'])
def reorder_folders(
    reorder_data: ReorderFolders,
    uid: str = Depends(auth.get_current_user_uid)
):
    """Reorder folders"""
    # Validate that all folders exist and belong to the user
    for folder_id in reorder_data.folder_ids:
        folder = folders_db.get_folder(uid, folder_id)
        if folder is None:
            raise HTTPException(status_code=404, detail=f"Folder {folder_id} not found")

    folders_db.reorder_folders(uid, reorder_data.folder_ids)
    return {"message": "Folders reordered successfully"}

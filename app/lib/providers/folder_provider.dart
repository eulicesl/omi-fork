import 'package:flutter/foundation.dart';
import 'package:omi/backend/http/api/folders.dart';
import 'package:omi/backend/schema/folder.dart';

class FolderProvider extends ChangeNotifier {
  List<Folder> _folders = [];
  bool _loading = false;
  String? _selectedFolderId;

  List<Folder> get folders => _folders;
  bool get loading => _loading;
  String? get selectedFolderId => _selectedFolderId;

  Folder? get selectedFolder {
    if (_selectedFolderId == null) return null;
    try {
      return _folders.firstWhere((f) => f.id == _selectedFolderId);
    } catch (e) {
      return null;
    }
  }

  Future<void> init() async {
    await loadFolders();
  }

  Future<void> loadFolders() async {
    _loading = true;
    notifyListeners();

    _folders = await getFolders();
    _folders.sort((a, b) => a.position.compareTo(b.position));

    _loading = false;
    notifyListeners();
  }

  Future<void> createFolder(String name, {String? color, String? icon}) async {
    // Get next position
    int nextPosition = _folders.isEmpty ? 0 : _folders.map((f) => f.position).reduce((a, b) => a > b ? a : b) + 1;

    bool success = await createFolderServer(
      name,
      color: color,
      icon: icon,
      position: nextPosition,
    );

    if (success) {
      // Reload folders to get the new folder with server-generated ID
      await loadFolders();
    }
  }

  Future<void> updateFolder(String folderId, {String? name, String? color, String? icon}) async {
    bool success = await updateFolderServer(
      folderId,
      name: name,
      color: color,
      icon: icon,
    );

    if (success) {
      // Update local state
      final index = _folders.indexWhere((f) => f.id == folderId);
      if (index != -1) {
        final folder = _folders[index];
        _folders[index] = folder.copyWith(
          name: name ?? folder.name,
          color: color ?? folder.color,
          icon: icon ?? folder.icon,
        );
        notifyListeners();
      }
    }
  }

  Future<void> deleteFolder(String folderId) async {
    bool success = await deleteFolderServer(folderId);

    if (success) {
      _folders.removeWhere((f) => f.id == folderId);

      // Clear selection if deleted folder was selected
      if (_selectedFolderId == folderId) {
        _selectedFolderId = null;
      }

      notifyListeners();
    }
  }

  Future<void> reorderFolders(List<Folder> reorderedFolders) async {
    // Update positions
    List<Map<String, dynamic>> positions = [];
    for (int i = 0; i < reorderedFolders.length; i++) {
      positions.add({'id': reorderedFolders[i].id, 'position': i});
    }

    bool success = await reorderFoldersServer(positions);

    if (success) {
      _folders = reorderedFolders;
      notifyListeners();
    }
  }

  void selectFolder(String? folderId) {
    _selectedFolderId = folderId;
    notifyListeners();
  }

  void clearSelection() {
    _selectedFolderId = null;
    notifyListeners();
  }

  Folder? getFolderById(String folderId) {
    try {
      return _folders.firstWhere((f) => f.id == folderId);
    } catch (e) {
      return null;
    }
  }

  List<Folder> getFoldersForMemory(List<String> folderIds) {
    return _folders.where((f) => folderIds.contains(f.id)).toList();
  }
}

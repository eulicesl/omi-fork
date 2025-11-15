import 'package:flutter/material.dart';
import 'package:omi/backend/http/api/folders.dart' as api;
import 'package:omi/backend/schema/folder.dart';

class FolderProvider extends ChangeNotifier {
  List<Folder> _folders = [];
  bool _isLoading = false;
  String? _selectedFolderId;

  List<Folder> get folders => _folders;
  bool get isLoading => _isLoading;
  String? get selectedFolderId => _selectedFolderId;

  Future<void> loadFolders() async {
    _isLoading = true;
    notifyListeners();

    try {
      _folders = await api.getFolders();
      _folders.sort((a, b) => a.position.compareTo(b.position));
    } catch (e) {
      debugPrint('Error loading folders: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Folder?> createFolder({
    required String name,
    String? color,
    String? icon,
  }) async {
    try {
      final folder = await api.createFolder(
        name: name,
        color: color,
        icon: icon,
        position: _folders.length,
      );
      if (folder != null) {
        _folders.add(folder);
        notifyListeners();
      }
      return folder;
    } catch (e) {
      debugPrint('Error creating folder: $e');
      return null;
    }
  }

  Future<bool> updateFolder({
    required String folderId,
    String? name,
    String? color,
    String? icon,
  }) async {
    try {
      final updated = await api.updateFolder(
        folderId,
        name: name,
        color: color,
        icon: icon,
      );
      if (updated != null) {
        final index = _folders.indexWhere((f) => f.id == folderId);
        if (index != -1) {
          _folders[index] = updated;
          notifyListeners();
        }
        return true;
      }
    } catch (e) {
      debugPrint('Error updating folder: $e');
    }
    return false;
  }

  Future<bool> deleteFolder(String folderId) async {
    try {
      final success = await api.deleteFolder(folderId);
      if (success) {
        _folders.removeWhere((f) => f.id == folderId);
        if (_selectedFolderId == folderId) {
          _selectedFolderId = null;
        }
        notifyListeners();
      }
      return success;
    } catch (e) {
      debugPrint('Error deleting folder: $e');
      return false;
    }
  }

  void selectFolder(String? folderId) {
    _selectedFolderId = folderId;
    notifyListeners();
  }

  Folder? getFolder(String folderId) {
    try {
      return _folders.firstWhere((f) => f.id == folderId);
    } catch (e) {
      return null;
    }
  }
}

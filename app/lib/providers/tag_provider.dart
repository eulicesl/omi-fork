import 'package:flutter/material.dart';
import 'package:omi/backend/http/api/tags.dart' as api;
import 'package:omi/backend/schema/tag.dart';

class TagProvider extends ChangeNotifier {
  List<Tag> _tags = [];
  bool _isLoading = false;
  Set<String> _selectedTagIds = {};

  List<Tag> get tags => _tags;
  bool get isLoading => _isLoading;
  Set<String> get selectedTagIds => _selectedTagIds;

  Future<void> loadTags() async {
    _isLoading = true;
    notifyListeners();

    try {
      _tags = await api.getTags();
      _tags.sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      debugPrint('Error loading tags: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Tag?> createTag({
    required String name,
    String? color,
  }) async {
    try {
      final tag = await api.createTag(name: name, color: color);
      if (tag != null) {
        _tags.add(tag);
        _tags.sort((a, b) => a.name.compareTo(b.name));
        notifyListeners();
      }
      return tag;
    } catch (e) {
      debugPrint('Error creating tag: $e');
      return null;
    }
  }

  Future<bool> updateTag({
    required String tagId,
    String? name,
    String? color,
  }) async {
    try {
      final updated = await api.updateTag(tagId, name: name, color: color);
      if (updated != null) {
        final index = _tags.indexWhere((t) => t.id == tagId);
        if (index != -1) {
          _tags[index] = updated;
          _tags.sort((a, b) => a.name.compareTo(b.name));
          notifyListeners();
        }
        return true;
      }
    } catch (e) {
      debugPrint('Error updating tag: $e');
    }
    return false;
  }

  Future<bool> deleteTag(String tagId) async {
    try {
      final success = await api.deleteTag(tagId);
      if (success) {
        _tags.removeWhere((t) => t.id == tagId);
        _selectedTagIds.remove(tagId);
        notifyListeners();
      }
      return success;
    } catch (e) {
      debugPrint('Error deleting tag: $e');
      return false;
    }
  }

  void toggleTagSelection(String tagId) {
    if (_selectedTagIds.contains(tagId)) {
      _selectedTagIds.remove(tagId);
    } else {
      _selectedTagIds.add(tagId);
    }
    notifyListeners();
  }

  void setSelectedTags(Set<String> tagIds) {
    _selectedTagIds = Set.from(tagIds);
    notifyListeners();
  }

  void clearSelection() {
    _selectedTagIds.clear();
    notifyListeners();
  }

  List<Tag> getTagsForConversation(List<String> tagIds) {
    return _tags.where((tag) => tagIds.contains(tag.id)).toList();
  }

  bool tagExists(String name) {
    return _tags.any((tag) => tag.name.toLowerCase() == name.toLowerCase());
  }
}

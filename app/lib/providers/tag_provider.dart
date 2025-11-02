import 'package:flutter/foundation.dart';
import 'package:omi/backend/http/api/tags.dart';
import 'package:omi/backend/schema/tag.dart';

class TagProvider extends ChangeNotifier {
  List<Tag> _tags = [];
  bool _loading = false;
  List<String> _selectedTagIds = [];

  List<Tag> get tags => _tags;
  bool get loading => _loading;
  List<String> get selectedTagIds => _selectedTagIds;

  List<Tag> get selectedTags {
    return _tags.where((t) => _selectedTagIds.contains(t.id)).toList();
  }

  Future<void> init() async {
    await loadTags();
  }

  Future<void> loadTags() async {
    _loading = true;
    notifyListeners();

    _tags = await getTags();
    // Sort by creation date (most recent first)
    _tags.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _loading = false;
    notifyListeners();
  }

  Future<void> createTag(String name, {String? color}) async {
    bool success = await createTagServer(name, color: color);

    if (success) {
      // Reload tags to get the new tag with server-generated ID
      await loadTags();
    }
  }

  Future<void> updateTag(String tagId, {String? name, String? color}) async {
    bool success = await updateTagServer(tagId, name: name, color: color);

    if (success) {
      // Update local state
      final index = _tags.indexWhere((t) => t.id == tagId);
      if (index != -1) {
        final tag = _tags[index];
        _tags[index] = tag.copyWith(
          name: name ?? tag.name,
          color: color ?? tag.color,
        );
        notifyListeners();
      }
    }
  }

  Future<void> deleteTag(String tagId) async {
    bool success = await deleteTagServer(tagId);

    if (success) {
      _tags.removeWhere((t) => t.id == tagId);

      // Remove from selection if it was selected
      _selectedTagIds.remove(tagId);

      notifyListeners();
    }
  }

  void selectTag(String tagId) {
    if (!_selectedTagIds.contains(tagId)) {
      _selectedTagIds.add(tagId);
      notifyListeners();
    }
  }

  void deselectTag(String tagId) {
    _selectedTagIds.remove(tagId);
    notifyListeners();
  }

  void toggleTagSelection(String tagId) {
    if (_selectedTagIds.contains(tagId)) {
      _selectedTagIds.remove(tagId);
    } else {
      _selectedTagIds.add(tagId);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedTagIds.clear();
    notifyListeners();
  }

  void setSelectedTags(List<String> tagIds) {
    _selectedTagIds = List.from(tagIds);
    notifyListeners();
  }

  Tag? getTagById(String tagId) {
    try {
      return _tags.firstWhere((t) => t.id == tagId);
    } catch (e) {
      return null;
    }
  }

  List<Tag> getTagsForMemory(List<String> tagIds) {
    return _tags.where((t) => tagIds.contains(t.id)).toList();
  }

  Tag? getTagByName(String name) {
    try {
      return _tags.firstWhere(
        (t) => t.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }

  bool tagExists(String name) {
    return _tags.any((t) => t.name.toLowerCase() == name.toLowerCase());
  }
}

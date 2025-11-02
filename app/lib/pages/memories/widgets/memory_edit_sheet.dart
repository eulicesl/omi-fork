import 'package:flutter/material.dart';
import 'package:omi/backend/schema/memory.dart';
import 'package:omi/providers/folder_provider.dart';
import 'package:omi/providers/memories_provider.dart';
import 'package:omi/providers/tag_provider.dart';
import 'package:omi/widgets/extensions/string.dart';
import 'package:provider/provider.dart';

import 'delete_confirmation.dart';

class MemoryEditSheet extends StatefulWidget {
  final Memory memory;
  final MemoriesProvider provider;
  final Function(BuildContext, Memory, MemoriesProvider)? onDelete;

  const MemoryEditSheet({
    super.key,
    required this.memory,
    required this.provider,
    this.onDelete,
  });

  @override
  State<MemoryEditSheet> createState() => _MemoryEditSheetState();
}

class _MemoryEditSheetState extends State<MemoryEditSheet> {
  late TextEditingController contentController;
  Set<String> selectedFolderIds = {};
  Set<String> selectedTagIds = {};

  @override
  void initState() {
    super.initState();
    contentController = TextEditingController(text: widget.memory.content.decodeString);
    contentController.selection = TextSelection.fromPosition(
      TextPosition(offset: contentController.text.length),
    );
    selectedFolderIds = Set.from(widget.memory.folderIds);
    selectedTagIds = Set.from(widget.memory.tagIds);

    // Load folders and tags
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FolderProvider>().loadFolders();
      context.read<TagProvider>().loadTags();
    });
  }

  @override
  void dispose() {
    contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F25),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.label_outline, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        widget.memory.category.toString().split('.').last,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _showDeleteConfirmation(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentController,
              autofocus: true,
              maxLines: null,
              textInputAction: TextInputAction.done,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.4,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onSubmitted: (value) {
                _saveChanges();
              },
            ),
            const SizedBox(height: 12),
            // Folder and tag selection buttons
            Row(
              children: [
                _buildSelectorButton(
                  icon: Icons.folder,
                  label: 'Folders',
                  count: selectedFolderIds.length,
                  onTap: () => _showFolderSelector(),
                ),
                const SizedBox(width: 8),
                _buildSelectorButton(
                  icon: Icons.label,
                  label: 'Tags',
                  count: selectedTagIds.length,
                  onTap: () => _showTagSelector(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.keyboard_return,
                        size: 13,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Press done to save',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${contentController.text.length}/200',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectorButton({
    required IconData icon,
    required String label,
    required int count,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: count > 0 ? Colors.deepPurpleAccent : Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              count > 0 ? '$label ($count)' : label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFolderSelector() async {
    final folderProvider = context.read<FolderProvider>();
    await folderProvider.loadFolders();

    if (!mounted) return;

    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _FolderSelectorDialog(
        folders: folderProvider.folders,
        selectedIds: selectedFolderIds,
      ),
    );

    if (selected != null) {
      setState(() {
        selectedFolderIds = selected;
      });
    }
  }

  void _showTagSelector() async {
    final tagProvider = context.read<TagProvider>();
    await tagProvider.loadTags();

    if (!mounted) return;

    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _TagSelectorDialog(
        tags: tagProvider.tags,
        selectedIds: selectedTagIds,
        onCreateTag: (name) async {
          await tagProvider.createTag(name);
          await tagProvider.loadTags();
        },
      ),
    );

    if (selected != null) {
      setState(() {
        selectedTagIds = selected;
      });
    }
  }

  void _saveChanges() async {
    if (contentController.text.trim().isNotEmpty) {
      widget.provider.editMemory(widget.memory, contentController.text, widget.memory.category);
    }

    // Update folders
    await widget.provider.setMemoryFolders(widget.memory, selectedFolderIds.toList());

    // Update tags
    await widget.provider.setMemoryTags(widget.memory, selectedTagIds.toList());

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _showDeleteConfirmation(BuildContext context) async {
    final shouldDelete = await DeleteConfirmation.show(context);
    if (shouldDelete) {
      widget.provider.deleteMemory(widget.memory);
      Navigator.pop(context); // Close edit sheet
      if (widget.onDelete != null) {
        widget.onDelete!(context, widget.memory, widget.provider);
      }
    }
  }
}

// Simple folder selector dialog
class _FolderSelectorDialog extends StatefulWidget {
  final List folders;
  final Set<String> selectedIds;

  const _FolderSelectorDialog({
    required this.folders,
    required this.selectedIds,
  });

  @override
  State<_FolderSelectorDialog> createState() => _FolderSelectorDialogState();
}

class _FolderSelectorDialogState extends State<_FolderSelectorDialog> {
  late Set<String> selected;

  @override
  void initState() {
    super.initState();
    selected = Set.from(widget.selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1F1F25),
      title: const Text('Select Folders', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: widget.folders.map<Widget>((folder) {
            final isSelected = selected.contains(folder.id);
            return CheckboxListTile(
              title: Text(folder.name, style: const TextStyle(color: Colors.white)),
              value: isSelected,
              activeColor: Colors.deepPurpleAccent,
              checkColor: Colors.white,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    selected.add(folder.id);
                  } else {
                    selected.remove(folder.id);
                  }
                });
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, selected),
          child: const Text('Done', style: TextStyle(color: Colors.deepPurpleAccent)),
        ),
      ],
    );
  }
}

// Simple tag selector dialog
class _TagSelectorDialog extends StatefulWidget {
  final List tags;
  final Set<String> selectedIds;
  final Function(String) onCreateTag;

  const _TagSelectorDialog({
    required this.tags,
    required this.selectedIds,
    required this.onCreateTag,
  });

  @override
  State<_TagSelectorDialog> createState() => _TagSelectorDialogState();
}

class _TagSelectorDialogState extends State<_TagSelectorDialog> {
  late Set<String> selected;
  final _newTagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    selected = Set.from(widget.selectedIds);
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1F1F25),
      title: const Text('Select Tags', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // New tag input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTagController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'New tag name',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.deepPurpleAccent),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, color: Colors.deepPurpleAccent),
                  onPressed: () async {
                    if (_newTagController.text.trim().isNotEmpty) {
                      await widget.onCreateTag(_newTagController.text.trim());
                      _newTagController.clear();
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Existing tags
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: widget.tags.map<Widget>((tag) {
                  final isSelected = selected.contains(tag.id);
                  return CheckboxListTile(
                    title: Text(tag.name, style: const TextStyle(color: Colors.white)),
                    value: isSelected,
                    activeColor: Colors.deepPurpleAccent,
                    checkColor: Colors.white,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selected.add(tag.id);
                        } else {
                          selected.remove(tag.id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, selected),
          child: const Text('Done', style: TextStyle(color: Colors.deepPurpleAccent)),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:omi/backend/http/api/conversations.dart' as api;
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/schema/tag.dart';
import 'package:omi/providers/folder_provider.dart';
import 'package:omi/providers/tag_provider.dart';
import 'package:provider/provider.dart';

class FolderTagSheet extends StatefulWidget {
  final ServerConversation conversation;
  final Function(ServerConversation) onUpdate;

  const FolderTagSheet({
    super.key,
    required this.conversation,
    required this.onUpdate,
  });

  @override
  State<FolderTagSheet> createState() => _FolderTagSheetState();
}

class _FolderTagSheetState extends State<FolderTagSheet> {
  String? _selectedFolderId;
  Set<String> _selectedTagIds = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedFolderId = widget.conversation.folderId;
    _selectedTagIds = Set.from(widget.conversation.tagIds);

    // Load folders and tags
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FolderProvider>().loadFolders();
      context.read<TagProvider>().loadTags();
    });
  }

  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);

    try {
      // Update folder if changed
      if (_selectedFolderId != widget.conversation.folderId) {
        final updated = await api.setConversationFolder(widget.conversation.id, _selectedFolderId);
        if (updated != null) {
          widget.onUpdate(updated);
        }
      }

      // Update tags if changed
      final currentTags = Set.from(widget.conversation.tagIds);
      final addedTags = _selectedTagIds.difference(currentTags);
      final removedTags = currentTags.difference(_selectedTagIds);

      for (final tagId in addedTags) {
        final updated = await api.addConversationTag(widget.conversation.id, tagId);
        if (updated != null) {
          widget.onUpdate(updated);
        }
      }

      for (final tagId in removedTags) {
        final updated = await api.removeConversationTag(widget.conversation.id, tagId);
        if (updated != null) {
          widget.onUpdate(updated);
        }
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error saving folder/tags: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1F1F25),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Organize Conversation',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Folder Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Folder', style: TextStyle(color: Colors.white70, fontSize: 14)),
              TextButton.icon(
                onPressed: () => _showCreateFolderDialog(),
                icon: const Icon(Icons.add, size: 16, color: Colors.blue),
                label: const Text('New Folder', style: TextStyle(color: Colors.blue, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Consumer<FolderProvider>(
            builder: (context, folderProvider, _) {
              if (folderProvider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // No folder option
                  _buildFolderChip(null, 'No Folder', folderProvider.folders.isEmpty || _selectedFolderId == null),
                  // Existing folders
                  ...folderProvider.folders.map((folder) => _buildFolderChip(folder.id, folder.name, _selectedFolderId == folder.id)),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // Tags Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tags', style: TextStyle(color: Colors.white70, fontSize: 14)),
              TextButton.icon(
                onPressed: () => _showCreateTagDialog(),
                icon: const Icon(Icons.add, size: 16, color: Colors.blue),
                label: const Text('New Tag', style: TextStyle(color: Colors.blue, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Consumer<TagProvider>(
            builder: (context, tagProvider, _) {
              if (tagProvider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (tagProvider.tags.isEmpty) {
                return const Text(
                  'No tags yet. Create one to organize your conversations.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                );
              }

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: tagProvider.tags.map((tag) => _buildTagChip(tag, _selectedTagIds.contains(tag.id))).toList(),
              );
            },
          ),
          const SizedBox(height: 24),

          // Save Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveChanges,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Save', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderChip(String? folderId, String name, bool isSelected) {
    return FilterChip(
      label: Text(name),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFolderId = selected ? folderId : null;
        });
      },
      selectedColor: Colors.blue.withOpacity(0.3),
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70),
      backgroundColor: Colors.white.withOpacity(0.1),
    );
  }

  Widget _buildTagChip(Tag tag, bool isSelected) {
    return FilterChip(
      label: Text(tag.name),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          if (selected) {
            _selectedTagIds.add(tag.id);
          } else {
            _selectedTagIds.remove(tag.id);
          }
        });
      },
      selectedColor: tag.color != null ? Color(int.parse(tag.color!.replaceFirst('#', '0xFF'))) : Colors.purple.withOpacity(0.3),
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 12),
      backgroundColor: Colors.white.withOpacity(0.1),
    );
  }

  Future<void> _showCreateTagDialog() async {
    final controller = TextEditingController();
    bool isCreating = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1F1F25),
          title: const Text('Create Tag', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            enabled: !isCreating,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Tag name',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isCreating ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isCreating ? null : () async {
                if (controller.text.trim().isEmpty) return;

                setState(() => isCreating = true);
                try {
                  final tag = await context.read<TagProvider>().createTag(name: controller.text.trim());
                  if (tag != null && mounted) {
                    Navigator.pop(context);
                    this.setState(() => _selectedTagIds.add(tag.id));
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to create tag. Please check your connection.')),
                    );
                    setState(() => isCreating = false);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                    setState(() => isCreating = false);
                  }
                }
              },
              child: isCreating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    bool isCreating = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1F1F25),
          title: const Text('Create Folder', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            enabled: !isCreating,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Folder name',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isCreating ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isCreating ? null : () async {
                if (controller.text.trim().isEmpty) return;

                setState(() => isCreating = true);
                try {
                  final folder = await context.read<FolderProvider>().createFolder(name: controller.text.trim());
                  if (folder != null && mounted) {
                    Navigator.pop(context);
                    this.setState(() => _selectedFolderId = folder.id);
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to create folder. Please check your connection.')),
                    );
                    setState(() => isCreating = false);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                    setState(() => isCreating = false);
                  }
                }
              },
              child: isCreating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

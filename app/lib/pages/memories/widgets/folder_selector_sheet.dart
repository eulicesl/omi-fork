import 'package:flutter/material.dart';
import 'package:omi/backend/schema/folder.dart';
import 'package:omi/providers/folder_provider.dart';
import 'package:omi/providers/memories_provider.dart';
import 'package:omi/utils/ui_guidelines.dart';
import 'package:provider/provider.dart';

class FolderSelectorSheet extends StatefulWidget {
  const FolderSelectorSheet({super.key});

  @override
  State<FolderSelectorSheet> createState() => _FolderSelectorSheetState();
}

class _FolderSelectorSheetState extends State<FolderSelectorSheet> {
  @override
  void initState() {
    super.initState();
    // Load folders when sheet opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FolderProvider>().loadFolders();
    });
  }

  void _createFolder() async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppStyles.backgroundSecondary,
        title: const Text('Create Folder', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.deepPurpleAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Create', style: TextStyle(color: Colors.deepPurpleAccent)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      await context.read<FolderProvider>().createFolder(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppStyles.backgroundPrimary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Folders',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, color: Colors.deepPurpleAccent),
                  onPressed: _createFolder,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          // Folder list
          Flexible(
            child: Consumer2<FolderProvider, MemoriesProvider>(
              builder: (context, folderProvider, memoriesProvider, _) {
                if (folderProvider.loading) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(color: Colors.deepPurpleAccent),
                    ),
                  );
                }

                return ListView(
                  shrinkWrap: true,
                  children: [
                    // All Memories
                    _buildFolderTile(
                      title: 'All Memories',
                      icon: Icons.folder_open,
                      count: memoriesProvider.memories.length,
                      isSelected: memoriesProvider.folderFilter == null,
                      onTap: () {
                        memoriesProvider.setFolderFilter(null);
                        Navigator.pop(context);
                      },
                    ),
                    // Unorganized
                    _buildFolderTile(
                      title: 'Unorganized',
                      icon: Icons.folder_off_outlined,
                      count: memoriesProvider.getUnorganizedMemories().length,
                      isSelected: memoriesProvider.folderFilter == 'unorganized',
                      onTap: () {
                        memoriesProvider.setFolderFilter('unorganized');
                        Navigator.pop(context);
                      },
                    ),
                    const Divider(height: 1, color: Colors.white12, indent: 16, endIndent: 16),
                    // User folders
                    ...folderProvider.folders.map((folder) => _buildFolderTile(
                          title: folder.name,
                          icon: Icons.folder,
                          count: memoriesProvider.getMemoriesInFolder(folder.id).length,
                          isSelected: memoriesProvider.folderFilter == folder.id,
                          color: folder.color != null ? Color(int.parse(folder.color!.replaceFirst('#', '0xFF'))) : null,
                          onTap: () {
                            memoriesProvider.setFolderFilter(folder.id);
                            Navigator.pop(context);
                          },
                          onLongPress: () => _showFolderOptions(folder),
                        )),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderTile({
    required String title,
    required IconData icon,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
    Color? color,
    VoidCallback? onLongPress,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: color ?? (isSelected ? Colors.deepPurpleAccent : Colors.white70),
        size: 20,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: Text(
        count.toString(),
        style: TextStyle(
          color: isSelected ? Colors.deepPurpleAccent : Colors.white38,
          fontSize: 13,
        ),
      ),
      selected: isSelected,
      selectedTileColor: Colors.deepPurple.withOpacity(0.1),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  void _showFolderOptions(Folder folder) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppStyles.backgroundSecondary,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.white70),
              title: const Text('Rename', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == 'rename' && mounted) {
      _renameFolder(folder);
    } else if (action == 'delete' && mounted) {
      _deleteFolder(folder);
    }
  }

  void _renameFolder(Folder folder) async {
    final nameController = TextEditingController(text: folder.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppStyles.backgroundSecondary,
        title: const Text('Rename Folder', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.deepPurpleAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Save', style: TextStyle(color: Colors.deepPurpleAccent)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      await context.read<FolderProvider>().updateFolder(folder.id, name: result);
    }
  }

  void _deleteFolder(Folder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppStyles.backgroundSecondary,
        title: const Text('Delete Folder?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Memories in this folder will not be deleted, only unorganized.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<FolderProvider>().deleteFolder(folder.id);
      // Clear folder filter if deleted folder was selected
      if (context.read<MemoriesProvider>().folderFilter == folder.id) {
        context.read<MemoriesProvider>().setFolderFilter(null);
      }
    }
  }
}

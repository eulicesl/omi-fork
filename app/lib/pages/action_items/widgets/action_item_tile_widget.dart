import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:omi/backend/schema/schema.dart';
import 'package:omi/gen/assets.gen.dart';
import 'package:omi/services/apple_reminders_service.dart';
import 'package:omi/services/apple_calendar_service.dart';
import 'package:omi/services/apple_notes_service.dart';
import 'package:omi/models/action_item_integration.dart';
import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/preferences_export_extension.dart';
import 'package:omi/utils/platform/platform_service.dart';
import 'package:omi/utils/analytics/mixpanel.dart';
import 'action_item_form_sheet.dart';

/// A tile widget representing a single action item with export capabilities.
/// This version extends the upstream implementation by supporting multiple
/// export destinations (Apple Reminders, Apple Notes and Apple Calendar) with
/// a configurable dropdown to select the desired integration. The current
/// selection is persisted via [SharedPreferencesUtil.taskExportDestination].
class ActionItemTileWidget extends StatefulWidget {
  final ActionItemWithMetadata actionItem;
  final Function(bool) onToggle;
  final Set<String>? exportedToAppleReminders;
  final VoidCallback? onExportedToAppleReminders;

  const ActionItemTileWidget({
    super.key,
    required this.actionItem,
    required this.onToggle,
    this.exportedToAppleReminders,
    this.onExportedToAppleReminders,
  });

  @override
  State<ActionItemTileWidget> createState() => _ActionItemTileWidgetState();
}

class _ActionItemTileWidgetState extends State<ActionItemTileWidget> {
  // Track which integration is currently selected for export. This defaults
  // to Apple Reminders but is loaded from saved preferences on init.
  ActionItemIntegration _selectedIntegration =
      ActionItemIntegration.appleReminders;

  // Keep track of which descriptions have been exported to each destination.
  // This prevents duplicate exports during a session.
  final Map<String, Set<String>> _exportedItems = {
    'reminders': <String>{},
    'notes': <String>{},
    'calendar': <String>{},
  };

  // Track in-flight export operations keyed by "integration:description"
  final Set<String> _pendingExports = <String>{};

  bool get _isPendingForCurrent {
    final key =
        '${_selectedIntegration.name}:${widget.actionItem.description}';
    return _pendingExports.contains(key);
  }

  // Determine if this item has already been exported to Apple Reminders. We rely
  // on the parent to pass down exported descriptions for Reminders.
  bool get _isExportedToAppleReminders =>
      widget.exportedToAppleReminders?.contains(widget.actionItem.description) ??
      false;

  // Determine if the current integration has already exported this item.
  bool get _isExportedToCurrent {
    if (_selectedIntegration == ActionItemIntegration.appleReminders) {
      return _isExportedToAppleReminders;
    } else if (_selectedIntegration == ActionItemIntegration.appleNotes) {
      return _exportedItems['notes']?.contains(widget.actionItem.description) ??
          false;
    } else if (_selectedIntegration == ActionItemIntegration.appleCalendar) {
      return _exportedItems['calendar']
              ?.contains(widget.actionItem.description) ??
          false;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadSavedIntegration();
  }

  /// Load the previously selected integration from shared preferences.
  Future<void> _loadSavedIntegration() async {
    try {
      final prefs = SharedPreferencesUtil();
      final savedName = prefs.taskExportDestination;
      if (savedName.isNotEmpty) {
        final integration = ActionItemIntegration.values.firstWhere(
          (e) => e.name == savedName,
          orElse: () => ActionItemIntegration.appleReminders,
        );
        if (mounted) {
          setState(() => _selectedIntegration = integration);
        }
      }
    } catch (_) {
      // ignore errors and fall back to default integration
    }
  }

  /// Persist the user's selected integration choice.
  Future<void> _saveIntegration(ActionItemIntegration integration) async {
    try {
      final prefs = SharedPreferencesUtil();
      prefs.taskExportDestination = integration.name;
    } catch (_) {
      // Non-fatal: failure to write prefs doesn't break selection retention
    }
  }

  void _showEditSheet(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ActionItemFormSheet(
        actionItem: widget.actionItem,
        exportedToAppleReminders: widget.exportedToAppleReminders,
        onExportedToAppleReminders: widget.onExportedToAppleReminders,
      ),
    );
  }

  Widget _buildDueDateChip() {
    final dueDate = widget.actionItem.dueAt;
    if (dueDate == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final isOverdue = dueDate.isBefore(now) && !widget.actionItem.completed;
    final isToday = _isSameDay(dueDate, now);
    final isTomorrow = _isSameDay(dueDate, now.add(const Duration(days: 1)));
    final isThisWeek =
        dueDate.isAfter(now) && dueDate.isBefore(now.add(const Duration(days: 7)));

    Color chipColor;
    Color textColor;
    IconData icon;
    String dueDateText;

    if (widget.actionItem.completed) {
      chipColor = Colors.grey.withOpacity(0.2);
      textColor = Colors.grey.shade500;
      icon = Icons.check_circle_outline;
      dueDateText = _formatDueDate(dueDate);
    } else if (isOverdue) {
      chipColor = Colors.red.withOpacity(0.15);
      textColor = Colors.red.shade300;
      icon = Icons.warning_amber_rounded;
      dueDateText = 'Overdue';
    } else if (isToday) {
      chipColor = Colors.orange.withOpacity(0.15);
      textColor = Colors.orange.shade300;
      icon = Icons.today;
      dueDateText = 'Today';
    } else if (isTomorrow) {
      chipColor = Colors.blue.withOpacity(0.15);
      textColor = Colors.blue.shade300;
      icon = Icons.event;
      dueDateText = 'Tomorrow';
    } else if (isThisWeek) {
      chipColor = Colors.green.withOpacity(0.15);
      textColor = Colors.green.shade300;
      icon = Icons.calendar_today;
      dueDateText = _formatDueDate(dueDate);
    } else {
      chipColor = Colors.purple.withOpacity(0.15);
      textColor = Colors.purple.shade300;
      icon = Icons.schedule;
      dueDateText = _formatDueDate(dueDate);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: textColor,
          ),
          const SizedBox(width: 4),
          Text(
            dueDateText,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  String _formatDueDate(DateTime date) {
    final now = DateTime.now();
    final difference = date.difference(now).inDays;
    if (difference == 0) {
      return 'Today';
    } else if (difference == 1) {
      return 'Tomorrow';
    } else if (difference == -1) {
      return 'Yesterday';
    } else if (difference > 1 && difference <= 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[date.weekday - 1];
    } else {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
        'Oct', 'Nov', 'Dec'
      ];
      return '${months[date.month - 1]} ${date.day}';
    }
  }

  /// Build the combined export button with status indicator and dropdown arrow.
  Widget _buildExportButton(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main export button: disabled if already exported or pending.
        GestureDetector(
          onTap: (_isExportedToCurrent || _isPendingForCurrent)
              ? null
              : () => _exportActionItem(context),
          child: Container(
            width: 32,
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: _selectedIntegration.hasAsset
                      ? (_selectedIntegration.isSvg
                          ? SvgPicture.asset(
                              _selectedIntegration.fullAssetPath!,
                              width: 24,
                              height: 24,
                            )
                          : Image.asset(
                              _selectedIntegration.fullAssetPath!,
                              width: 24,
                              height: 24,
                              fit: BoxFit.contain,
                            ))
                      : Icon(
                          _selectedIntegration.icon ?? Icons.device_hub,
                          color: Colors.white,
                        ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _isExportedToCurrent ? Colors.green : Colors.yellow,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF1F1F25),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      _isExportedToCurrent ? Icons.check : Icons.add,
                      size: 8,
                      color: _isExportedToCurrent ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Dropdown arrow to change integration.
        GestureDetector(
          onTap: () => _showIntegrationPicker(context),
          child: Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }

  /// Present a bottom sheet allowing the user to pick the destination integration.
  void _showIntegrationPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F1F25),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Export to',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...ActionItemIntegration.values.map((integration) {
              final isSelected = integration == _selectedIntegration;
              return ListTile(
                leading: integration.hasAsset
                    ? (integration.isSvg
                        ? SvgPicture.asset(
                            integration.fullAssetPath!,
                            width: 24,
                            height: 24,
                          )
                        : Image.asset(
                            integration.fullAssetPath!,
                            width: 24,
                            height: 24,
                            fit: BoxFit.contain,
                          ))
                    : Icon(
                        integration.icon ?? Icons.device_hub,
                        color: Colors.white,
                      ),
                title: Text(
                  integration.displayName,
                  style: TextStyle(
                    color: isSelected ? Colors.blue : Colors.white,
                    fontSize: 16,
                  ),
                ),
                trailing:
                    isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
                onTap: () {
                  setState(() => _selectedIntegration = integration);
                  _saveIntegration(integration);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Export the current action item to the selected integration. Handles
  /// pending state and routes to specific export functions.
  Future<void> _exportActionItem(BuildContext context) async {
    HapticFeedback.lightImpact();
    if (_isExportedToCurrent || _isPendingForCurrent) {
      return;
    }
    final key =
        '${_selectedIntegration.name}:${widget.actionItem.description}';
    setState(() {
      _pendingExports.add(key);
    });
    try {
      if (_selectedIntegration == ActionItemIntegration.appleReminders) {
        await _exportToAppleReminders(context);
      } else if (_selectedIntegration == ActionItemIntegration.appleNotes) {
        await _exportToAppleNotes(context);
      } else if (_selectedIntegration == ActionItemIntegration.appleCalendar) {
        await _exportToAppleCalendar(context);
      }
    } finally {
      if (mounted) {
        setState(() {
          _pendingExports.remove(key);
        });
      }
    }
  }

  Future<void> _exportToAppleReminders(BuildContext context) async {
    // Trigger the existing Apple Reminders export flow from the upstream code.
    // We reuse the parent provided callback for updating exported lists.
    // We call the upstream export logic by simulating a tap on the original
    // reminders icon handler.
    await _handleAppleRemindersExport(context);
  }

  Future<void> _exportToAppleNotes(BuildContext context) async {
    final service = AppleNotesService();
    final result =
        await service.shareActionItem(widget.actionItem.description);

    if (!mounted) return;

    if (result.isSuccess) {
      (_exportedItems['notes'] ??= <String>{})
          .add(widget.actionItem.description);
      setState(() {});
      // Show success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.message,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.grey[900],
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
      // Track analytics
      MixpanelManager().track('Action Item Exported to Apple Notes', properties: {
        'conversationId': widget.actionItem.conversationId,
        'success': true,
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.message,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.grey[900],
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }

  Future<void> _exportToAppleCalendar(BuildContext context) async {
    final service = AppleCalendarService();
    final result =
        await service.createEvent(widget.actionItem.description);

    if (!mounted) return;

    if (result.isSuccess) {
      (_exportedItems['calendar'] ??= <String>{})
          .add(widget.actionItem.description);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.message,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.grey[900],
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
      MixpanelManager().track('Action Item Exported to Apple Calendar',
          properties: {
            'conversationId': widget.actionItem.conversationId,
            'success': true,
          });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.message,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.grey[900],
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }

  // Upstream handler for Apple Reminders export. We keep this method unchanged
  // except that it relies on widget.onExportedToAppleReminders to update parent.
  Future<void> _handleAppleRemindersExport(BuildContext context) async {
    if (!PlatformService.isApple) return;
    HapticFeedback.mediumImpact();
    final service = AppleRemindersService();
    final isAlreadyExported = _isExportedToAppleReminders;
    if (isAlreadyExported) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Already added to Apple Reminders'),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    bool hasPermission = await service.hasPermission();
    if (!hasPermission) {
      hasPermission = await service.requestPermission();
      if (!hasPermission) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text('Permission denied for Apple Reminders'),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Adding to Apple Reminders...'),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 3),
        ),
      );
    }
    final success = await service.addReminder(
      title: widget.actionItem.description,
      notes: 'From Omi',
      listName: 'Reminders',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(success
                  ? 'Added to Apple Reminders'
                  : 'Failed to add to Reminders'),
            ],
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      if (success) {
        widget.onExportedToAppleReminders?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: const Color(0xFF1F1F25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: widget.actionItem.completed
              ? Colors.grey.withOpacity(0.2)
              : Colors.transparent,
          width: 1,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showEditSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Custom checkbox with better styling
              GestureDetector(
                onTap: () => widget.onToggle(!widget.actionItem.completed),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.actionItem.completed
                          ? Colors.deepPurpleAccent
                          : Colors.grey.shade600,
                      width: 2,
                    ),
                    color: widget.actionItem.completed
                        ? Colors.deepPurpleAccent
                        : Colors.transparent,
                  ),
                  child: widget.actionItem.completed
                      ? const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              // Action item text and due date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.actionItem.description,
                      style: TextStyle(
                        color: widget.actionItem.completed
                            ? Colors.grey.shade400
                            : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        decoration: widget.actionItem.completed
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: Colors.grey.shade400,
                      ),
                    ),
                    if (widget.actionItem.dueAt != null) ...[
                      const SizedBox(height: 6),
                      _buildDueDateChip(),
                    ],
                  ],
                ),
              ),
              // Export button (only on Apple platforms)
              if (PlatformService.isApple) ...[
                const SizedBox(width: 12),
                _buildExportButton(context),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
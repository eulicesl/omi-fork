import 'package:omi/backend/preferences.dart';

/// An extension on [SharedPreferencesUtil] adding support for storing the
/// selected export destination for action items.
///
/// This extends the existing preferences API without modifying the upstream
/// file, which allows our widget to persist the last chosen integration
/// (e.g. Apple Reminders, Notes or Calendar) across sessions.
extension TaskExportDestinationExtension on SharedPreferencesUtil {
  /// Persist the user's selected destination for exporting action items.
  ///
  /// The value stored corresponds to the [ActionItemIntegration.name] of
  /// the chosen integration. If an empty string is provided, no value is
  /// stored and the default integration will be used.
  set taskExportDestination(String value) =>
      saveString('taskExportDestination', value);

  /// Retrieve the previously selected export destination for action items.
  ///
  /// If no value has been stored, an empty string is returned. Consumers
  /// should interpret the empty string as meaning that the default
  /// integration (Apple Reminders) should be used.
  String get taskExportDestination =>
      getString('taskExportDestination') ?? '';
}
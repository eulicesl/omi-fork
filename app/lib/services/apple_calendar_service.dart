import 'package:flutter/services.dart';

/// A Flutter service wrapper for integrating with Apple Calendar on iOS.
///
/// This class provides a Dart API over a platform channel implemented in
/// Swift (see `AppleCalendarService.swift` in the iOS Runner target). It
/// exposes methods to create calendar events and check availability. The
/// native implementation handles permission requests and event creation.
class AppleCalendarService {
  static const MethodChannel _channel = MethodChannel('com.omi.apple_calendar');

  /// Creates an event in Apple Calendar from the given [description].
  ///
  /// Returns a tuple containing `isSuccess` and a human‑readable `message`.
  /// The native implementation formats the event and returns a structured
  /// response via the platform channel. In case of unexpected errors,
  /// `isSuccess` will be `false` and `message` will describe the issue.
  Future<({bool isSuccess, String message})> createEvent(String description) async {
    try {
      final formattedContent = '''
Action Item: $description

Created: ${DateTime.now().toLocal()}
Source: OMI App
''';
      final result = await _channel.invokeMethod('createEvent', {
        'title': description,
        'notes': formattedContent,
      });
      if (result is Map) {
        return (
          isSuccess: result['success'] as bool? ?? false,
          message: result['message'] as String? ?? 'Unknown response',
        );
      }
      return (isSuccess: false, message: 'Invalid response format');
    } on PlatformException catch (e) {
      return (isSuccess: false, message: e.message ?? 'Failed to create calendar event');
    } catch (e) {
      return (isSuccess: false, message: 'Unexpected error: $e');
    }
  }

  /// Checks whether Apple Calendar is available on the current device.
  ///
  /// The native implementation always returns `true` on iOS, but this
  /// method exists for completeness and potential future platform support.
  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod('checkAvailability');
      return result as bool? ?? false;
    } catch (e) {
      return false;
    }
  }
}
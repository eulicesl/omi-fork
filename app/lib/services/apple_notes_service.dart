import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';

/// A Flutter service wrapper for integrating with the Apple Notes app on iOS.
///
/// This class uses a platform channel (defined in `AppleNotesService.swift` on
/// iOS) to present the native share sheet for creating a new note from an
/// action item. It returns a tuple indicating success or failure along with
/// a user‑facing message.
class AppleNotesService {
  static const MethodChannel _channel = MethodChannel('com.omi.apple_notes');

  /// Determines whether the Notes integration is available (iOS only).
  bool get isAvailable => Platform.isIOS;

  /// Shares an action item description to Apple Notes via the share sheet.
  ///
  /// The note is formatted with a header and timestamp. On success, the
  /// returned tuple contains `isSuccess: true` and a message indicating that
  /// the share sheet has been opened. If Notes is not available or the
  /// platform is not iOS, `isSuccess` will be `false` with an appropriate
  /// message.
  Future<({bool isSuccess, String message})> shareActionItem(String description) async {
    if (!isAvailable) {
      return (
        isSuccess: false,
        message: 'Apple Notes is only available on iOS',
      );
    }
    try {
      final formattedContent = '''
Action Item from Omi
━━━━━━━━━━━━━━━━━
$description

Added: ${DateTime.now().toString().split('.')[0]}
''';
      final result = await _channel.invokeMethod('shareToNotes', {
        'content': formattedContent,
      });
      return result == true
          ? (isSuccess: true, message: 'Opening share sheet...')
          : (isSuccess: false, message: 'Could not open share sheet');
    } on PlatformException catch (e) {
      return (
        isSuccess: false,
        message: 'Error: ${e.message ?? 'Unknown error'}',
      );
    } catch (e) {
      return (
        isSuccess: false,
        message: 'Unexpected error: $e',
      );
    }
  }

  /// Checks whether the Apple Notes app is installed on the device.
  ///
  /// Returns `true` if the Notes app is available, `false` otherwise.
  Future<bool> isNotesAppAvailable() async {
    if (!isAvailable) return false;
    try {
      final result = await _channel.invokeMethod('isNotesAppAvailable');
      return result == true;
    } catch (e) {
      developer.log('Error checking Notes availability: $e', name: 'AppleNotesService');
      return false;
    }
  }
}
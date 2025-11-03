import 'package:flutter/foundation.dart';

/// Types of audio errors that can occur during playback
enum AudioErrorType {
  fileNotFound,
  corruptedFile,
  unsupportedFormat,
  decodingFailed,
  playbackFailed,
  insufficientStorage,
  permissionDenied,
  networkError,
  unknown,
}

/// Represents an audio-related error with user-friendly messaging
class AudioError {
  final AudioErrorType type;
  final String message;
  final String? technicalDetails;
  final StackTrace? stackTrace;

  AudioError({
    required this.type,
    required this.message,
    this.technicalDetails,
    this.stackTrace,
  });

  /// Get a user-friendly message based on error type
  String get userFriendlyMessage {
    switch (type) {
      case AudioErrorType.fileNotFound:
        return "Audio file not found. It may have been deleted or moved.";
      case AudioErrorType.corruptedFile:
        return "This audio file appears to be corrupted and cannot be played. Try recording again.";
      case AudioErrorType.unsupportedFormat:
        return "This audio format is not supported. Please contact support.";
      case AudioErrorType.decodingFailed:
        return "Failed to decode audio file. The file may be incomplete or corrupted.";
      case AudioErrorType.playbackFailed:
        return "Unable to play this audio. Please try again or restart the app.";
      case AudioErrorType.insufficientStorage:
        return "Not enough storage space to process this audio file.";
      case AudioErrorType.permissionDenied:
        return "Permission denied. Please check app permissions in Settings.";
      case AudioErrorType.networkError:
        return "Network error occurred. Check your internet connection.";
      case AudioErrorType.unknown:
        return "An unexpected error occurred. Please try again.";
    }
  }

  /// Get suggested action for the user
  String get suggestedAction {
    switch (type) {
      case AudioErrorType.fileNotFound:
        return "The recording may have been removed. Try checking your storage settings.";
      case AudioErrorType.corruptedFile:
        return "This recording cannot be recovered. Consider making a new recording.";
      case AudioErrorType.unsupportedFormat:
        return "Update your app to the latest version or contact support.";
      case AudioErrorType.decodingFailed:
        return "Try playing a different recording or restart the app.";
      case AudioErrorType.playbackFailed:
        return "Close and reopen the app, or try restarting your device.";
      case AudioErrorType.insufficientStorage:
        return "Free up space on your device and try again.";
      case AudioErrorType.permissionDenied:
        return "Go to Settings > Apps > Omi > Permissions and enable required permissions.";
      case AudioErrorType.networkError:
        return "Check your internet connection and try again.";
      case AudioErrorType.unknown:
        return "If the problem persists, please report it to support.";
    }
  }

  /// Whether this error can be retried
  bool get canRetry {
    return type == AudioErrorType.playbackFailed ||
        type == AudioErrorType.networkError ||
        type == AudioErrorType.unknown;
  }

  /// Whether this error indicates a permanent failure
  bool get isPermanent {
    return type == AudioErrorType.corruptedFile ||
        type == AudioErrorType.unsupportedFormat ||
        type == AudioErrorType.fileNotFound;
  }

  /// Create an AudioError from an Exception
  factory AudioError.fromException(Exception exception, {StackTrace? stackTrace}) {
    final message = exception.toString();
    AudioErrorType type = AudioErrorType.unknown;

    if (message.contains('file not found') || message.contains('FileSystemException')) {
      type = AudioErrorType.fileNotFound;
    } else if (message.contains('corrupt') || message.contains('invalid')) {
      type = AudioErrorType.corruptedFile;
    } else if (message.contains('unsupported') || message.contains('format')) {
      type = AudioErrorType.unsupportedFormat;
    } else if (message.contains('decode') || message.contains('decoding')) {
      type = AudioErrorType.decodingFailed;
    } else if (message.contains('playback') || message.contains('player')) {
      type = AudioErrorType.playbackFailed;
    } else if (message.contains('storage') || message.contains('space')) {
      type = AudioErrorType.insufficientStorage;
    } else if (message.contains('permission') || message.contains('denied')) {
      type = AudioErrorType.permissionDenied;
    } else if (message.contains('network') || message.contains('connection')) {
      type = AudioErrorType.networkError;
    }

    return AudioError(
      type: type,
      message: message,
      technicalDetails: exception.toString(),
      stackTrace: stackTrace,
    );
  }

  /// Log this error for debugging
  void log() {
    debugPrint('AudioError [${type.name}]: $message');
    if (technicalDetails != null) {
      debugPrint('Technical details: $technicalDetails');
    }
    if (stackTrace != null) {
      debugPrint('Stack trace: $stackTrace');
    }
  }

  @override
  String toString() {
    return 'AudioError(type: $type, message: $message)';
  }
}

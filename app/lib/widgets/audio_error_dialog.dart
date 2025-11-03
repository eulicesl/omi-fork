import 'package:flutter/material.dart';
import 'package:omi/utils/audio/audio_error.dart';

/// Dialog to display audio errors with user-friendly messages and actions
class AudioErrorDialog extends StatelessWidget {
  final AudioError error;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  const AudioErrorDialog({
    super.key,
    required this.error,
    this.onRetry,
    this.onDismiss,
  });

  static Future<bool?> show(
    BuildContext context, {
    required AudioError error,
    VoidCallback? onRetry,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AudioErrorDialog(
        error: error,
        onRetry: onRetry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            _getErrorIcon(),
            color: _getErrorColor(),
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _getErrorTitle(),
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error.userFriendlyMessage,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.grey.withOpacity(0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: Colors.amber.shade300,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error.suggestedAction,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (error.canRetry && onRetry != null)
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop(true);
              onRetry?.call();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.secondary,
            ),
          ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false);
            onDismiss?.call();
          },
          child: Text(
            error.canRetry ? 'Cancel' : 'OK',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ],
    );
  }

  IconData _getErrorIcon() {
    switch (error.type) {
      case AudioErrorType.fileNotFound:
        return Icons.search_off;
      case AudioErrorType.corruptedFile:
        return Icons.broken_image_outlined;
      case AudioErrorType.unsupportedFormat:
        return Icons.audio_file_outlined;
      case AudioErrorType.decodingFailed:
        return Icons.error_outline;
      case AudioErrorType.playbackFailed:
        return Icons.play_disabled;
      case AudioErrorType.insufficientStorage:
        return Icons.sd_storage;
      case AudioErrorType.permissionDenied:
        return Icons.block;
      case AudioErrorType.networkError:
        return Icons.wifi_off;
      case AudioErrorType.unknown:
        return Icons.help_outline;
    }
  }

  Color _getErrorColor() {
    if (error.isPermanent) {
      return Colors.red.shade400;
    } else if (error.canRetry) {
      return Colors.orange.shade400;
    }
    return Colors.grey.shade400;
  }

  String _getErrorTitle() {
    switch (error.type) {
      case AudioErrorType.fileNotFound:
        return 'File Not Found';
      case AudioErrorType.corruptedFile:
        return 'Corrupted File';
      case AudioErrorType.unsupportedFormat:
        return 'Unsupported Format';
      case AudioErrorType.decodingFailed:
        return 'Decoding Failed';
      case AudioErrorType.playbackFailed:
        return 'Playback Error';
      case AudioErrorType.insufficientStorage:
        return 'Storage Full';
      case AudioErrorType.permissionDenied:
        return 'Permission Required';
      case AudioErrorType.networkError:
        return 'Network Error';
      case AudioErrorType.unknown:
        return 'Error Occurred';
    }
  }
}

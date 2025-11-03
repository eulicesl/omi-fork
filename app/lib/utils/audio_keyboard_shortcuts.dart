import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omi/utils/audio_player_utils.dart';
import 'package:omi/services/wals.dart';

/// Keyboard shortcuts for audio player
class AudioPlayerKeyboardShortcuts extends StatefulWidget {
  final Widget child;
  final AudioPlayerUtils? audioPlayerUtils;
  final Wal? currentWal;
  final VoidCallback? onPlayPause;
  final VoidCallback? onSkipForward;
  final VoidCallback? onSkipBackward;
  final VoidCallback? onToggleLoop;
  final VoidCallback? onShowInfo;

  const AudioPlayerKeyboardShortcuts({
    super.key,
    required this.child,
    this.audioPlayerUtils,
    this.currentWal,
    this.onPlayPause,
    this.onSkipForward,
    this.onSkipBackward,
    this.onToggleLoop,
    this.onShowInfo,
  });

  @override
  State<AudioPlayerKeyboardShortcuts> createState() => _AudioPlayerKeyboardShortcutsState();
}

class _AudioPlayerKeyboardShortcutsState extends State<AudioPlayerKeyboardShortcuts> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: _focusNode,
      autofocus: true,
      shortcuts: _buildShortcuts(),
      actions: _buildActions(),
      child: widget.child,
    );
  }

  Map<ShortcutActivator, Intent> _buildShortcuts() {
    return {
      // Play/Pause
      const SingleActivator(LogicalKeyboardKey.space): const PlayPauseIntent(),
      const SingleActivator(LogicalKeyboardKey.keyK): const PlayPauseIntent(),

      // Skip forward
      const SingleActivator(LogicalKeyboardKey.arrowRight): const SkipForwardIntent(Duration(seconds: 5)),
      const SingleActivator(LogicalKeyboardKey.keyL): const SkipForwardIntent(Duration(seconds: 5)),
      const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): const SkipForwardIntent(Duration(seconds: 10)),

      // Skip backward
      const SingleActivator(LogicalKeyboardKey.arrowLeft): const SkipBackwardIntent(Duration(seconds: 5)),
      const SingleActivator(LogicalKeyboardKey.keyJ): const SkipBackwardIntent(Duration(seconds: 5)),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): const SkipBackwardIntent(Duration(seconds: 10)),

      // Speed control
      const SingleActivator(LogicalKeyboardKey.bracketLeft): const DecreaseSpeedIntent(),
      const SingleActivator(LogicalKeyboardKey.bracketRight): const IncreaseSpeedIntent(),
      const SingleActivator(LogicalKeyboardKey.digit0): const ResetSpeedIntent(),

      // Loop control
      const SingleActivator(LogicalKeyboardKey.keyL, control: true): const ToggleLoopIntent(),

      // Volume (if implemented later)
      const SingleActivator(LogicalKeyboardKey.arrowUp): const VolumeUpIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowDown): const VolumeDownIntent(),
      const SingleActivator(LogicalKeyboardKey.keyM): const MuteIntent(),

      // Seek to positions
      const SingleActivator(LogicalKeyboardKey.home): const SeekToStartIntent(),
      const SingleActivator(LogicalKeyboardKey.end): const SeekToEndIntent(),

      // Info
      const SingleActivator(LogicalKeyboardKey.keyI): const ShowInfoIntent(),
    };
  }

  Map<Type, Action<Intent>> _buildActions() {
    return {
      PlayPauseIntent: CallbackAction<PlayPauseIntent>(
        onInvoke: (intent) {
          widget.onPlayPause?.call();
          return null;
        },
      ),
      SkipForwardIntent: CallbackAction<SkipForwardIntent>(
        onInvoke: (intent) {
          if (widget.audioPlayerUtils != null) {
            widget.audioPlayerUtils!.skipForward(duration: intent.duration);
          } else {
            widget.onSkipForward?.call();
          }
          return null;
        },
      ),
      SkipBackwardIntent: CallbackAction<SkipBackwardIntent>(
        onInvoke: (intent) {
          if (widget.audioPlayerUtils != null) {
            widget.audioPlayerUtils!.skipBackward(duration: intent.duration);
          } else {
            widget.onSkipBackward?.call();
          }
          return null;
        },
      ),
      DecreaseSpeedIntent: CallbackAction<DecreaseSpeedIntent>(
        onInvoke: (intent) {
          if (widget.audioPlayerUtils != null) {
            final currentSpeed = widget.audioPlayerUtils!.playbackSpeed;
            final newSpeed = (currentSpeed - 0.25).clamp(0.5, 2.0);
            widget.audioPlayerUtils!.setPlaybackSpeed(newSpeed);
            _showSpeedToast(newSpeed);
          }
          return null;
        },
      ),
      IncreaseSpeedIntent: CallbackAction<IncreaseSpeedIntent>(
        onInvoke: (intent) {
          if (widget.audioPlayerUtils != null) {
            final currentSpeed = widget.audioPlayerUtils!.playbackSpeed;
            final newSpeed = (currentSpeed + 0.25).clamp(0.5, 2.0);
            widget.audioPlayerUtils!.setPlaybackSpeed(newSpeed);
            _showSpeedToast(newSpeed);
          }
          return null;
        },
      ),
      ResetSpeedIntent: CallbackAction<ResetSpeedIntent>(
        onInvoke: (intent) {
          if (widget.audioPlayerUtils != null) {
            widget.audioPlayerUtils!.setPlaybackSpeed(1.0);
            _showSpeedToast(1.0);
          }
          return null;
        },
      ),
      ToggleLoopIntent: CallbackAction<ToggleLoopIntent>(
        onInvoke: (intent) {
          if (widget.audioPlayerUtils != null) {
            widget.audioPlayerUtils!.toggleLoop();
            _showLoopToast(widget.audioPlayerUtils!.isLooping);
          } else {
            widget.onToggleLoop?.call();
          }
          return null;
        },
      ),
      SeekToStartIntent: CallbackAction<SeekToStartIntent>(
        onInvoke: (intent) {
          if (widget.audioPlayerUtils != null) {
            widget.audioPlayerUtils!.seekToPosition(Duration.zero);
          }
          return null;
        },
      ),
      SeekToEndIntent: CallbackAction<SeekToEndIntent>(
        onInvoke: (intent) {
          if (widget.audioPlayerUtils != null) {
            final duration = widget.audioPlayerUtils!.totalDuration;
            widget.audioPlayerUtils!.seekToPosition(duration);
          }
          return null;
        },
      ),
      ShowInfoIntent: CallbackAction<ShowInfoIntent>(
        onInvoke: (intent) {
          widget.onShowInfo?.call();
          return null;
        },
      ),
      // Placeholder actions for future implementation
      VolumeUpIntent: CallbackAction<VolumeUpIntent>(onInvoke: (intent) => null),
      VolumeDownIntent: CallbackAction<VolumeDownIntent>(onInvoke: (intent) => null),
      MuteIntent: CallbackAction<MuteIntent>(onInvoke: (intent) => null),
    };
  }

  void _showSpeedToast(double speed) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playback speed: ${speed.toStringAsFixed(2)}x'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showLoopToast(bool isLooping) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isLooping ? 'Loop enabled' : 'Loop disabled'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// Intent classes
class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}

class SkipForwardIntent extends Intent {
  final Duration duration;
  const SkipForwardIntent(this.duration);
}

class SkipBackwardIntent extends Intent {
  final Duration duration;
  const SkipBackwardIntent(this.duration);
}

class DecreaseSpeedIntent extends Intent {
  const DecreaseSpeedIntent();
}

class IncreaseSpeedIntent extends Intent {
  const IncreaseSpeedIntent();
}

class ResetSpeedIntent extends Intent {
  const ResetSpeedIntent();
}

class ToggleLoopIntent extends Intent {
  const ToggleLoopIntent();
}

class VolumeUpIntent extends Intent {
  const VolumeUpIntent();
}

class VolumeDownIntent extends Intent {
  const VolumeDownIntent();
}

class MuteIntent extends Intent {
  const MuteIntent();
}

class SeekToStartIntent extends Intent {
  const SeekToStartIntent();
}

class SeekToEndIntent extends Intent {
  const SeekToEndIntent();
}

class ShowInfoIntent extends Intent {
  const ShowInfoIntent();
}

/// Widget to display keyboard shortcuts help
class KeyboardShortcutsHelp extends StatelessWidget {
  const KeyboardShortcutsHelp({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const KeyboardShortcutsHelp(),
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
            Icons.keyboard,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(width: 12),
          const Text('Keyboard Shortcuts'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildShortcutSection(
              context,
              'Playback',
              [
                _ShortcutItem('Space / K', 'Play/Pause'),
                _ShortcutItem('? / J', 'Skip backward 5s'),
                _ShortcutItem('? / L', 'Skip forward 5s'),
                _ShortcutItem('Shift + ?', 'Skip backward 10s'),
                _ShortcutItem('Shift + ?', 'Skip forward 10s'),
                _ShortcutItem('Home', 'Jump to start'),
                _ShortcutItem('End', 'Jump to end'),
              ],
            ),
            const SizedBox(height: 16),
            _buildShortcutSection(
              context,
              'Speed Control',
              [
                _ShortcutItem('[', 'Decrease speed'),
                _ShortcutItem(']', 'Increase speed'),
                _ShortcutItem('0', 'Reset to 1.0x'),
              ],
            ),
            const SizedBox(height: 16),
            _buildShortcutSection(
              context,
              'Other',
              [
                _ShortcutItem('Ctrl + L', 'Toggle loop'),
                _ShortcutItem('I', 'Show audio info'),
                _ShortcutItem('M', 'Mute/Unmute'),
                _ShortcutItem('? / ?', 'Volume up/down'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildShortcutSection(BuildContext context, String title, List<_ShortcutItem> shortcuts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        ...shortcuts.map((shortcut) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    ),
                    child: Text(
                      shortcut.keys,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      shortcut.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                          ),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}

class _ShortcutItem {
  final String keys;
  final String description;

  _ShortcutItem(this.keys, this.description);
}

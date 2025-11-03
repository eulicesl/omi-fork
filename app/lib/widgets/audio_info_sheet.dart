import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/services/wals.dart';
import 'package:omi/utils/other/time_utils.dart';
import 'package:omi/utils/device.dart';

/// Bottom sheet displaying detailed audio information
class AudioInfoSheet extends StatelessWidget {
  final Wal wal;
  final String? audioFilePath;

  const AudioInfoSheet({
    super.key,
    required this.wal,
    this.audioFilePath,
  });

  static Future<void> show(BuildContext context, {required Wal wal, String? audioFilePath}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AudioInfoSheet(wal: wal, audioFilePath: audioFilePath),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recordingDate = DateTime.fromMillisecondsSinceEpoch(wal.timerStart * 1000);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F25),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade600,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.secondary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Recording Information',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // Device Image
              if (wal.deviceModel != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Image.asset(
                      DeviceUtils.getDeviceImagePathByModel(wal.deviceModel),
                      height: 80,
                    ),
                  ),
                ),

              // Info sections
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _buildSection(
                      context,
                      title: 'General',
                      items: [
                        _InfoItem(
                          label: 'Recording ID',
                          value: wal.id,
                          copyable: true,
                        ),
                        _InfoItem(
                          label: 'Date & Time',
                          value: dateTimeFormat('MMM dd, yyyy', recordingDate),
                        ),
                        _InfoItem(
                          label: 'Time',
                          value: dateTimeFormat('h:mm:ss a', recordingDate),
                        ),
                        _InfoItem(
                          label: 'Duration',
                          value: secondsToHumanReadable(wal.seconds),
                        ),
                        _InfoItem(
                          label: 'Status',
                          value: _getStatusText(),
                          valueColor: _getStatusColor(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'Audio Format',
                      items: [
                        _InfoItem(
                          label: 'Codec',
                          value: wal.codec.toFormattedString(),
                        ),
                        _InfoItem(
                          label: 'Sample Rate',
                          value: '${wal.sampleRate} Hz',
                        ),
                        _InfoItem(
                          label: 'Channels',
                          value: wal.channel == 1 ? 'Mono' : 'Stereo (${wal.channel})',
                        ),
                        _InfoItem(
                          label: 'Bit Depth',
                          value: _getBitDepth(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'Storage',
                      items: [
                        _InfoItem(
                          label: 'Location',
                          value: wal.storage == WalStorage.sdcard ? 'SD Card' : 'Phone Memory',
                        ),
                        _InfoItem(
                          label: 'Estimated Size',
                          value: _estimateFileSize(),
                        ),
                        if (audioFilePath != null)
                          _InfoItem(
                            label: 'File Path',
                            value: audioFilePath!,
                            copyable: true,
                          ),
                        if (wal.filePath != null)
                          _InfoItem(
                            label: 'Internal Path',
                            value: wal.filePath!,
                            copyable: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'Device',
                      items: [
                        _InfoItem(
                          label: 'Device Model',
                          value: wal.deviceModel ?? 'Unknown',
                        ),
                        if (wal.device.isNotEmpty && wal.device != "phone")
                          _InfoItem(
                            label: 'Device ID',
                            value: wal.device,
                            copyable: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, {required String title, required List<_InfoItem> items}) {
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
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey.withOpacity(0.2),
            ),
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == items.length - 1;

              return _buildInfoRow(
                context,
                item: item,
                showDivider: !isLast,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, {required _InfoItem item, required bool showDivider}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  item.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade500,
                      ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        item.value,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: item.valueColor ?? Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                    if (item.copyable) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _copyToClipboard(context, item.value),
                        child: Icon(
                          Icons.copy,
                          size: 16,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            color: Colors.grey.withOpacity(0.2),
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _getStatusText() {
    switch (wal.status) {
      case WalStatus.synced:
        return 'Processed';
      case WalStatus.inProgress:
        return 'In Progress';
      case WalStatus.miss:
        return 'Missing';
      case WalStatus.corrupted:
        return 'Corrupted';
    }
  }

  Color _getStatusColor() {
    switch (wal.status) {
      case WalStatus.synced:
        return Colors.green.shade400;
      case WalStatus.inProgress:
        return Colors.blue.shade400;
      case WalStatus.miss:
        return Colors.orange.shade400;
      case WalStatus.corrupted:
        return Colors.red.shade400;
    }
  }

  String _getBitDepth() {
    switch (wal.codec) {
      case BleAudioCodec.pcm16:
        return '16-bit';
      case BleAudioCodec.pcm8:
      case BleAudioCodec.mulaw8:
      case BleAudioCodec.mulaw16:
        return '8-bit';
      case BleAudioCodec.opus:
      case BleAudioCodec.opusFS320:
        return 'Variable (Opus)';
      default:
        return 'Unknown';
    }
  }

  String _estimateFileSize() {
    int bytesPerSecond;
    switch (wal.codec) {
      case BleAudioCodec.opus:
      case BleAudioCodec.opusFS320:
        bytesPerSecond = wal.codec == BleAudioCodec.opusFS320 ? 40000 : 8000;
        break;
      case BleAudioCodec.pcm16:
        bytesPerSecond = wal.sampleRate * 2 * wal.channel;
        break;
      case BleAudioCodec.pcm8:
        bytesPerSecond = wal.sampleRate * 1 * wal.channel;
        break;
      case BleAudioCodec.mulaw16:
      case BleAudioCodec.mulaw8:
        bytesPerSecond = wal.sampleRate * 1 * wal.channel;
        break;
      default:
        bytesPerSecond = 8000;
    }

    final totalBytes = bytesPerSecond * wal.seconds;
    return _formatBytes(totalBytes);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _InfoItem {
  final String label;
  final String value;
  final bool copyable;
  final Color? valueColor;

  _InfoItem({
    required this.label,
    required this.value,
    this.copyable = false,
    this.valueColor,
  });
}

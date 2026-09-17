import 'package:flutter/material.dart';

enum SaveStatus { saved, unsaved, saving, failed }

class SaveStatusIndicator extends StatelessWidget {
  const SaveStatusIndicator({
    required this.status,
    this.savedAt,
    this.onRetry,
    this.compact = false,
    super.key,
  });

  final SaveStatus status;
  final DateTime? savedAt;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (status) {
      SaveStatus.saved => (
          Icons.cloud_done_outlined,
          savedAt == null ? '저장됨' : '저장됨 ${_time(savedAt!)}',
          colorScheme.onSurfaceVariant,
        ),
      SaveStatus.unsaved => (
          Icons.edit_note_outlined,
          '저장되지 않은 변경',
          colorScheme.tertiary,
        ),
      SaveStatus.saving => (Icons.sync, '저장 중…', colorScheme.primary),
      SaveStatus.failed => (Icons.error_outline, '저장 실패', colorScheme.error),
    };

    final content = Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Icon(icon, size: compact ? 14 : 20, color: color),
        const SizedBox(width: 6),
        if (compact)
          Text(
            label,
            key: const ValueKey('save-status-label'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          )
        else
          Expanded(
            child: Text(
              label,
              key: const ValueKey('save-status-label'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        if (!compact && status == SaveStatus.failed && onRetry != null)
          TextButton.icon(
            key: const ValueKey('retry-save-button'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('다시 시도'),
          ),
      ],
    );
    if (compact) return content;
    return Material(
      key: const ValueKey('save-status-banner'),
      color: status == SaveStatus.failed
          ? colorScheme.errorContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: content,
      ),
    );
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}

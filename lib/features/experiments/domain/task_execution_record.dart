enum TaskExecutionAction { cancelStart, restart, reopen }

extension TaskExecutionActionLabel on TaskExecutionAction {
  String get label => switch (this) {
        TaskExecutionAction.cancelStart => '시작 취소',
        TaskExecutionAction.restart => '다시 시작',
        TaskExecutionAction.reopen => '완료 해제',
      };
}

/// The state before an explicit execution reset, never another history tree.
class TaskExecutionRecord {
  const TaskExecutionRecord({
    required this.action,
    required this.recordedAt,
    required this.reason,
    required this.title,
    required this.wasCompleted,
    required this.reminderEnabled,
    this.startedAt,
    this.completedAt,
    this.plannedMinutes,
  });

  final TaskExecutionAction action;
  final DateTime recordedAt;
  final String reason;
  final String title;
  final bool wasCompleted;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? plannedMinutes;
  final bool reminderEnabled;

  factory TaskExecutionRecord.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('단계 실행 이력이 올바르지 않습니다.');
    final action = TaskExecutionAction.values
        .where((a) => a.name == value['action'])
        .firstOrNull;
    final reason = value['reason'];
    final minutes = value['plannedMinutes'];
    if (action == null ||
        reason is! String ||
        reason.trim().isEmpty ||
        value['title'] is! String ||
        value['wasCompleted'] is! bool ||
        value['reminderEnabled'] is! bool ||
        (minutes != null &&
            (minutes is! int || minutes < 1 || minutes > 43200)) ||
        (value['reminderEnabled'] == true && minutes == null)) {
      throw const FormatException('단계 실행 이력의 사유·상태·예정 시간이 올바르지 않습니다.');
    }
    DateTime? date(String key) {
      final raw = value[key];
      if (raw == null && key != 'recordedAt') return null;
      if (raw is! String || DateTime.tryParse(raw) == null) {
        throw const FormatException('단계 실행 이력의 시각이 올바르지 않습니다.');
      }
      return DateTime.parse(raw).toUtc();
    }

    return TaskExecutionRecord(
      action: action,
      recordedAt: date('recordedAt')!,
      reason: reason,
      title: value['title'] as String,
      wasCompleted: value['wasCompleted'] as bool,
      reminderEnabled: value['reminderEnabled'] as bool,
      startedAt: date('startedAt'),
      completedAt: date('completedAt'),
      plannedMinutes: minutes as int?,
    );
  }

  Map<String, Object?> toJson() => {
        'action': action.name,
        'recordedAt': recordedAt.toUtc().toIso8601String(),
        'reason': reason,
        'title': title,
        'wasCompleted': wasCompleted,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'completedAt': completedAt?.toUtc().toIso8601String(),
        'plannedMinutes': plannedMinutes,
        'reminderEnabled': reminderEnabled,
      };
}

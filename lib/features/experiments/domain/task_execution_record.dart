enum TaskExecutionAction {
  cancelStart,
  restart,
  reopen,
  recordTimes,
  skip,
  unskip
}

extension TaskExecutionActionLabel on TaskExecutionAction {
  String get label => switch (this) {
        TaskExecutionAction.cancelStart => '시작 취소',
        TaskExecutionAction.restart => '다시 시작',
        TaskExecutionAction.reopen => '완료 해제',
        TaskExecutionAction.recordTimes => '실제 시각 사후 입력',
        TaskExecutionAction.skip => '단계 생략',
        TaskExecutionAction.unskip => '생략 해제',
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
    this.metadata = const TaskExecutionMetadata(),
  });

  final TaskExecutionMetadata metadata;
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

    final metadata = TaskExecutionMetadata.fromJson(value['metadata']);
    metadata.validate(
        start: date('startedAt'),
        completion: date('completedAt'),
        completed: value['wasCompleted'] as bool);
    return TaskExecutionRecord(
      metadata: metadata,
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
        'metadata': metadata.toJson(),
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

/// Provenance for the current execution, also embedded in historical snapshots.
class TaskExecutionMetadata {
  const TaskExecutionMetadata(
      {this.startRecordedAt,
      this.completionRecordedAt,
      this.skippedAt,
      this.skipReason});
  final DateTime? startRecordedAt;
  final DateTime? completionRecordedAt;
  final DateTime? skippedAt;
  final String? skipReason;

  factory TaskExecutionMetadata.fromJson(Object? value) {
    if (value == null) return const TaskExecutionMetadata();
    if (value is! Map) throw const FormatException('실행 기록 출처가 올바르지 않습니다.');
    DateTime? date(String key) {
      final raw = value[key];
      if (raw == null) return null;
      if (raw is! String ||
          DateTime.tryParse(raw) == null ||
          !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(raw)) {
        throw const FormatException('실행 기록 시각에는 시간대가 필요합니다.');
      }
      return DateTime.parse(raw).toUtc();
    }

    final skipped = date('skippedAt');
    final reason = value['skipReason'];
    if ((skipped == null && reason != null) ||
        (skipped != null && (reason is! String || reason.trim().isEmpty))) {
      throw const FormatException('생략 시각과 사유를 함께 기록해야 합니다.');
    }
    return TaskExecutionMetadata(
        startRecordedAt: date('startRecordedAt'),
        completionRecordedAt: date('completionRecordedAt'),
        skippedAt: skipped,
        skipReason: reason as String?);
  }

  void validate(
      {required DateTime? start,
      required DateTime? completion,
      required bool completed}) {
    if ((startRecordedAt != null &&
            start != null &&
            start.isAfter(startRecordedAt!)) ||
        (completionRecordedAt != null &&
            completion != null &&
            completion.isAfter(completionRecordedAt!)) ||
        ((startRecordedAt != null || completionRecordedAt != null) &&
            start != null &&
            completion != null &&
            completion.isBefore(start)) ||
        (startRecordedAt != null && start == null) ||
        (completionRecordedAt != null && (completion == null || !completed)) ||
        (skippedAt != null &&
            (completed ||
                start != null ||
                completion != null ||
                startRecordedAt != null ||
                completionRecordedAt != null))) {
      throw const FormatException('실행 상태와 사후 입력·생략 기록이 일치하지 않습니다.');
    }
  }

  Map<String, Object?> toJson() => {
        'startRecordedAt': startRecordedAt?.toUtc().toIso8601String(),
        'completionRecordedAt': completionRecordedAt?.toUtc().toIso8601String(),
        'skippedAt': skippedAt?.toUtc().toIso8601String(),
        'skipReason': skipReason,
      };
}

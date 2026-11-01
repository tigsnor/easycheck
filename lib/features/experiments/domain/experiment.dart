import '../../attachments/domain/experiment_attachment.dart';
import 'task_execution_record.dart';

export 'task_execution_record.dart';

enum ExperimentStatus {
  draft,
  planned,
  inProgress,
  completed,
  archived,
  correcting
}

enum ExperimentResourceType { reagent, equipment }

const _unset = Object();

class ExperimentTask {
  const ExperimentTask({
    required this.id,
    required this.title,
    this.isCompleted = false,
    this.startedAt,
    this.completedAt,
    this.plannedMinutes,
    this.reminderEnabled = false,
    this.executionHistory = const [],
    this.executionMetadata = const TaskExecutionMetadata(),
  });

  factory ExperimentTask.fromJson(Map<String, Object?> json) {
    final minutes = json['plannedMinutes'];
    final reminder = json['reminderEnabled'] as bool? ?? false;
    if (minutes != null &&
        (minutes is! int || minutes < 1 || minutes > 43200)) {
      throw const FormatException('단계 예정 시간은 1~43200분이어야 합니다.');
    }
    if (reminder && minutes == null) {
      throw const FormatException('종료 알림에는 예정 시간이 필요합니다.');
    }
    final history = json['executionHistory'];
    if (history != null && history is! List) {
      throw const FormatException('단계 실행 이력은 목록이어야 합니다.');
    }
    final task = ExperimentTask(
      executionMetadata:
          TaskExecutionMetadata.fromJson(json['executionMetadata']),
      executionHistory: List.unmodifiable(
          (history as List? ?? const []).map(TaskExecutionRecord.fromJson)),
      id: json['id'] as String,
      title: json['title'] as String,
      plannedMinutes: minutes as int?,
      reminderEnabled: reminder,
      isCompleted: json['isCompleted'] as bool? ?? false,
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String).toUtc(),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String).toUtc(),
    );
    task.executionMetadata.validate(
        start: task.startedAt,
        completion: task.completedAt,
        completed: task.isCompleted);
    return task;
  }

  final String id;
  final String title;
  final bool isCompleted;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? plannedMinutes;
  final bool reminderEnabled;
  final List<TaskExecutionRecord> executionHistory;
  final TaskExecutionMetadata executionMetadata;
  bool get isSkipped => executionMetadata.skippedAt != null;
  bool get isFinished => isCompleted || isSkipped;

  DateTime? get dueAt =>
      isSkipped || startedAt == null || plannedMinutes == null
          ? null
          : startedAt!.toUtc().add(Duration(minutes: plannedMinutes!));

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'isCompleted': isCompleted,
        'plannedMinutes': plannedMinutes,
        'reminderEnabled': reminderEnabled,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'completedAt': completedAt?.toUtc().toIso8601String(),
        'executionHistory': executionHistory.map((r) => r.toJson()).toList(),
        'executionMetadata': executionMetadata.toJson(),
      };

  TaskExecutionRecord archiveExecution(
          TaskExecutionAction action, String reason, DateTime now) =>
      TaskExecutionRecord(
          action: action,
          recordedAt: now.toUtc(),
          reason: reason.trim(),
          title: title,
          wasCompleted: isCompleted,
          startedAt: startedAt?.toUtc(),
          completedAt: completedAt?.toUtc(),
          plannedMinutes: plannedMinutes,
          reminderEnabled: reminderEnabled,
          metadata: executionMetadata);

  ExperimentTask resetExecution(
      TaskExecutionAction action, String reason, DateTime now) {
    final allowed = switch (action) {
      TaskExecutionAction.cancelStart => startedAt != null && !isFinished,
      TaskExecutionAction.restart =>
        !isSkipped && (startedAt != null || isCompleted),
      TaskExecutionAction.reopen => isCompleted,
      TaskExecutionAction.skip => !isFinished,
      TaskExecutionAction.unskip => isSkipped,
      TaskExecutionAction.recordTimes => false,
    };
    if (!allowed || reason.trim().isEmpty) {
      throw StateError('변경 가능한 실행 상태와 사유가 필요합니다.');
    }
    return copyWith(
        isCompleted: false,
        completedAt: null,
        startedAt: switch (action) {
          TaskExecutionAction.restart => now.toUtc(),
          TaskExecutionAction.reopen => startedAt,
          _ => null,
        },
        executionMetadata: switch (action) {
          TaskExecutionAction.reopen => TaskExecutionMetadata(
              startRecordedAt: executionMetadata.startRecordedAt),
          TaskExecutionAction.skip => TaskExecutionMetadata(
              skippedAt: now.toUtc(), skipReason: reason.trim()),
          _ => const TaskExecutionMetadata(),
        },
        executionHistory: List.unmodifiable(
            [...executionHistory, archiveExecution(action, reason, now)]));
  }

  ExperimentTask recordActualTimes(
      {required DateTime? start,
      required DateTime? completion,
      required String reason,
      required DateTime now}) {
    if (isSkipped) throw StateError('생략을 해제한 뒤 시각을 입력하세요.');
    if (start == null && completion == null) {
      throw const FormatException('실제 시작 또는 완료 시각을 입력해주세요.');
    }
    if ((startedAt != null && start == null) ||
        (completedAt != null && completion == null)) {
      throw const FormatException('기존 시각을 지우려면 시작 취소 또는 완료 해제를 사용하세요.');
    }
    if ((start?.isAfter(now) ?? false) || (completion?.isAfter(now) ?? false)) {
      throw const FormatException('미래 시각은 실제 실행 시각으로 기록할 수 없습니다.');
    }
    if (start != null && completion != null && completion.isBefore(start)) {
      throw const FormatException('완료 시각은 시작 시각보다 빠를 수 없습니다.');
    }
    bool same(DateTime? a, DateTime? b) =>
        a == null ? b == null : b != null && a.isAtSameMomentAs(b);
    final changedStart = !same(start, startedAt);
    final changedCompletion = !same(completion, completedAt);
    if (!changedStart && !changedCompletion) return this;
    if (reason.trim().isEmpty) {
      throw const FormatException('사후 입력·수정 사유를 입력해주세요.');
    }
    return copyWith(
        startedAt: start?.toUtc(),
        completedAt: completion?.toUtc(),
        isCompleted: isCompleted || completion != null,
        executionMetadata: TaskExecutionMetadata(
            startRecordedAt:
                changedStart ? now.toUtc() : executionMetadata.startRecordedAt,
            completionRecordedAt: changedCompletion
                ? now.toUtc()
                : executionMetadata.completionRecordedAt),
        executionHistory: List.unmodifiable([
          ...executionHistory,
          archiveExecution(TaskExecutionAction.recordTimes, reason, now)
        ]));
  }

  ExperimentTask copyWith({
    bool? isCompleted,
    Object? startedAt = _unset,
    Object? completedAt = _unset,
    Object? plannedMinutes = _unset,
    bool? reminderEnabled,
    List<TaskExecutionRecord>? executionHistory,
    TaskExecutionMetadata? executionMetadata,
  }) {
    return ExperimentTask(
      id: id,
      title: title,
      isCompleted: isCompleted ?? this.isCompleted,
      plannedMinutes: identical(plannedMinutes, _unset)
          ? this.plannedMinutes
          : plannedMinutes as int?,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      executionHistory: executionHistory ?? this.executionHistory,
      executionMetadata: executionMetadata ?? this.executionMetadata,
      startedAt: identical(startedAt, _unset)
          ? this.startedAt
          : startedAt as DateTime?,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
    );
  }
}

class ExperimentResource {
  const ExperimentResource({
    required this.id,
    required this.type,
    required this.name,
    this.manufacturer = '',
    this.catalogOrModel = '',
    this.lotOrSerial = '',
    this.note = '',
  });

  factory ExperimentResource.fromJson(Map<String, Object?> json) {
    return ExperimentResource(
      id: json['id'] as String,
      type: ExperimentResourceType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => ExperimentResourceType.reagent,
      ),
      name: json['name'] as String,
      manufacturer: json['manufacturer'] as String? ?? '',
      catalogOrModel: json['catalogOrModel'] as String? ?? '',
      lotOrSerial: json['lotOrSerial'] as String? ?? '',
      note: json['note'] as String? ?? '',
    );
  }

  final String id;
  final ExperimentResourceType type;
  final String name;
  final String manufacturer;
  final String catalogOrModel;
  final String lotOrSerial;
  final String note;

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'name': name,
        'manufacturer': manufacturer,
        'catalogOrModel': catalogOrModel,
        'lotOrSerial': lotOrSerial,
        'note': note,
      };
}

class ExperimentRevision {
  const ExperimentRevision({
    required this.id,
    required this.changedAt,
    required this.summary,
    this.reason = '',
    this.before,
  });

  factory ExperimentRevision.fromJson(Map<String, Object?> json) {
    return ExperimentRevision(
      id: json['id'] as String,
      changedAt: DateTime.parse(json['changedAt'] as String),
      summary: json['summary'] as String,
      reason: json['reason'] as String? ?? '',
      before: json['before'] == null
          ? null
          : Experiment.fromJson({
              ...Map<String, Object?>.from(json['before'] as Map),
              'revisions': <Object?>[]
            }),
    );
  }

  final String id;
  final DateTime changedAt;
  final String summary;
  final String reason;
  final Experiment? before;

  Map<String, Object?> toJson() => {
        'id': id,
        'changedAt': changedAt.toIso8601String(),
        'summary': summary,
        'reason': reason,
        if (before != null) 'before': before!.copyWith(revisions: []).toJson(),
      };
}

class Experiment {
  const Experiment({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.projectName,
    this.experimentType = 'Custom',
    this.researcher,
    this.status = ExperimentStatus.draft,
    this.notes = '',
    this.cellCountLabel,
    this.tags = const [],
    this.tasks = const [],
    this.resources = const [],
    this.completedAt,
    this.revisions = const [],
    this.attachments = const [],
  });

  factory Experiment.fromJson(Map<String, Object?> json) {
    final notes = json['notes'] as String? ?? '';
    return Experiment(
      id: json['id'] as String,
      title: json['title'] as String,
      projectName: json['projectName'] as String?,
      experimentType: json['experimentType'] as String? ?? 'Custom',
      researcher: json['researcher'] as String?,
      status: ExperimentStatusJson.fromName(json['status'] as String?),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      notes: notes,
      attachments: ExperimentAttachment.parseList(json['attachments']),
      cellCountLabel:
          json['cellCountLabel'] as String? ?? _cellCountLabelFromNotes(notes),
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      tasks: (json['tasks'] as List<dynamic>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(ExperimentTask.fromJson)
          .toList(),
      resources: (json['resources'] as List<dynamic>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(ExperimentResource.fromJson)
          .toList(),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
      revisions: (json['revisions'] as List<dynamic>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(ExperimentRevision.fromJson)
          .toList(),
    );
  }

  final String id;
  final String title;
  final String? projectName;
  final String experimentType;
  final String? researcher;
  final ExperimentStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String notes;
  final String? cellCountLabel;
  final List<String> tags;
  final List<ExperimentTask> tasks;
  final List<ExperimentResource> resources;
  final DateTime? completedAt;
  final List<ExperimentRevision> revisions;
  final List<ExperimentAttachment> attachments;

  bool get isReadOnly =>
      status == ExperimentStatus.completed ||
      status == ExperimentStatus.archived;

  Experiment beginCorrection(String reason, DateTime now) {
    if (status != ExperimentStatus.completed || reason.trim().isEmpty) {
      throw StateError('완료 노트의 정정 사유가 필요합니다.');
    }
    return copyWith(
        status: ExperimentStatus.correcting,
        updatedAt: now,
        revisions: [
          ...revisions,
          ExperimentRevision(
              id: 'revision-${now.microsecondsSinceEpoch}-correction',
              changedAt: now,
              summary: '완료 후 정정 시작',
              reason: reason.trim(),
              before: copyWith(revisions: []))
        ]);
  }

  String get notesWithoutCellCountLine {
    return notes
        .split('\n')
        .where((line) => !line.trim().startsWith('세포수:'))
        .join('\n')
        .trim();
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'projectName': projectName,
      'experimentType': experimentType,
      'researcher': researcher,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'notes': notes,
      'attachments': attachments.map((a) => a.toJson()).toList(),
      'cellCountLabel': cellCountLabel,
      'tags': tags,
      'tasks': tasks.map((task) => task.toJson()).toList(),
      'resources': resources.map((resource) => resource.toJson()).toList(),
      'completedAt': completedAt?.toIso8601String(),
      'revisions': revisions.map((revision) => revision.toJson()).toList(),
    };
  }

  Experiment copyWith({
    String? id,
    String? title,
    Object? projectName = _unset,
    String? experimentType,
    Object? researcher = _unset,
    ExperimentStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? notes,
    Object? cellCountLabel = _unset,
    List<String>? tags,
    List<ExperimentTask>? tasks,
    List<ExperimentResource>? resources,
    Object? completedAt = _unset,
    List<ExperimentRevision>? revisions,
    List<ExperimentAttachment>? attachments,
  }) {
    return Experiment(
      id: id ?? this.id,
      title: title ?? this.title,
      projectName: identical(projectName, _unset)
          ? this.projectName
          : projectName as String?,
      experimentType: experimentType ?? this.experimentType,
      researcher: identical(researcher, _unset)
          ? this.researcher
          : researcher as String?,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes ?? this.notes,
      cellCountLabel: identical(cellCountLabel, _unset)
          ? this.cellCountLabel
          : cellCountLabel as String?,
      tags: tags ?? this.tags,
      tasks: tasks ?? this.tasks,
      resources: resources ?? this.resources,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
      revisions: revisions ?? this.revisions,
      attachments: attachments ?? this.attachments,
    );
  }
}

String? _cellCountLabelFromNotes(String notes) {
  for (final line in notes.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('세포수:')) {
      final value = trimmed.substring('세포수:'.length).trim();
      return value.isEmpty ? null : value;
    }
  }
  return null;
}

extension ExperimentStatusJson on ExperimentStatus {
  static ExperimentStatus fromName(String? name) {
    return ExperimentStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => ExperimentStatus.draft,
    );
  }
}

import '../../attachments/domain/experiment_attachment.dart';

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
    return ExperimentTask(
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
  }

  final String id;
  final String title;
  final bool isCompleted;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? plannedMinutes;
  final bool reminderEnabled;

  DateTime? get dueAt => startedAt == null || plannedMinutes == null
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
      };

  ExperimentTask copyWith({
    bool? isCompleted,
    Object? startedAt = _unset,
    Object? completedAt = _unset,
    Object? plannedMinutes = _unset,
    bool? reminderEnabled,
  }) {
    return ExperimentTask(
      id: id,
      title: title,
      isCompleted: isCompleted ?? this.isCompleted,
      plannedMinutes: identical(plannedMinutes, _unset)
          ? this.plannedMinutes
          : plannedMinutes as int?,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
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

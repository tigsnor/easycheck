enum ExperimentStatus { draft, planned, inProgress, completed, archived }

const _unset = Object();

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
      cellCountLabel:
          json['cellCountLabel'] as String? ?? _cellCountLabelFromNotes(notes),
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .whereType<String>()
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
      'cellCountLabel': cellCountLabel,
      'tags': tags,
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

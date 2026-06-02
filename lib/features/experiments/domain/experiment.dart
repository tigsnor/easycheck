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
    this.tags = const [],
  });

  factory Experiment.fromJson(Map<String, Object?> json) {
    return Experiment(
      id: json['id'] as String,
      title: json['title'] as String,
      projectName: json['projectName'] as String?,
      experimentType: json['experimentType'] as String? ?? 'Custom',
      researcher: json['researcher'] as String?,
      status: ExperimentStatusJson.fromName(json['status'] as String?),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      notes: json['notes'] as String? ?? '',
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
  final List<String> tags;

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
      tags: tags ?? this.tags,
    );
  }
}

extension ExperimentStatusJson on ExperimentStatus {
  static ExperimentStatus fromName(String? name) {
    return ExperimentStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => ExperimentStatus.draft,
    );
  }
}

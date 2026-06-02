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

enum ExperimentStatus { draft, planned, inProgress, completed, archived }

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
    String? projectName,
    String? experimentType,
    String? researcher,
    ExperimentStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? notes,
    List<String>? tags,
  }) {
    return Experiment(
      id: id ?? this.id,
      title: title ?? this.title,
      projectName: projectName ?? this.projectName,
      experimentType: experimentType ?? this.experimentType,
      researcher: researcher ?? this.researcher,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
    );
  }
}

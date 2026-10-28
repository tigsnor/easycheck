import 'package:uuid/uuid.dart';

import '../../plates/data/plate_repository.dart';
import '../../plates/domain/plate.dart';
import '../data/experiment_repository.dart';
import '../domain/experiment.dart';

class ExperimentDuplicationException implements Exception {
  const ExperimentDuplicationException(this.cause, this.cleanupErrors);

  final Object cause;
  final List<Object> cleanupErrors;

  @override
  String toString() => cleanupErrors.isEmpty
      ? '설계 복제에 실패하여 새 복사본을 정리했습니다: $cause'
      : '설계 복제와 복사본 정리에 실패했습니다. 일부 복사본이 남아 있을 수 있으니 '
          '목록을 다시 확인해주세요: $cause / ${cleanupErrors.join('; ')}';
}

/// Copies design data into a new draft without reusing execution records.
class ExperimentDuplicationService {
  ExperimentDuplicationService({
    required this.experimentRepository,
    required this.plateRepository,
    String Function()? createId,
    DateTime Function()? now,
  })  : _createId = createId ?? const Uuid().v4,
        _now = now ?? DateTime.now;

  final ExperimentRepository experimentRepository;
  final PlateRepository plateRepository;
  final String Function() _createId;
  final DateTime Function() _now;

  Future<Experiment> duplicateDesign(String sourceId) async {
    final experiments = await experimentRepository.loadExperiments();
    final source = experiments.firstWhere((e) => e.id == sourceId,
        orElse: () => throw StateError('복제할 실험을 찾을 수 없습니다.'));
    final sourcePlate = await plateRepository.loadPlate(sourceId);
    if (sourcePlate != null && sourcePlate.experimentId != sourceId) {
      throw const FormatException('실험에 연결된 Plate가 일치하지 않습니다.');
    }
    final id = _createId();
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ||
        experiments.any((e) => e.id == id) ||
        await plateRepository.loadPlate(id) != null) {
      throw StateError('새 복사본 ID를 사용할 수 없습니다. 다시 시도해주세요.');
    }
    final timestamp = _now();
    final copy = Experiment.fromJson(source.copyWith(
      id: id,
      title: '${source.title} 설계 복사본',
      status: ExperimentStatus.draft,
      createdAt: timestamp,
      updatedAt: timestamp,
      completedAt: null,
      notes: '',
      tasks: source.tasks
          .map((task) => task.copyWith(
              isCompleted: false,
              startedAt: null,
              completedAt: null,
              reminderEnabled: false))
          .toList(),
      revisions: [],
      attachments: [],
    ).toJson());
    final plate = sourcePlate == null
        ? null
        : Plate.fromJson(Plate(
            id: 'plate-$id',
            experimentId: id,
            name: sourcePlate.name,
            rowCount: sourcePlate.rowCount,
            columnCount: sourcePlate.columnCount,
            groups: sourcePlate.groups,
            wells: sourcePlate.wells
                .map((well) => well.copyWith(
                    resultValue: null,
                    resultUnit: null,
                    excluded: false,
                    note: ''))
                .toList(),
          ).toJson());

    // Publish the experiment last so a failed Plate write never presents a
    // successful copy in the list. Cleanup handles writes that throw afterward.
    try {
      if (plate != null) await plateRepository.savePlate(plate);
      await experimentRepository.saveExperiment(copy);
    } on Object catch (error) {
      final cleanupErrors = <Object>[];
      try {
        await experimentRepository.deleteExperiment(id);
      } on Object catch (error) {
        cleanupErrors.add(error);
      }
      if (plate != null) {
        try {
          await plateRepository.deletePlate(id);
        } on Object catch (error) {
          cleanupErrors.add(error);
        }
      }
      throw ExperimentDuplicationException(error, cleanupErrors);
    }
    return copy;
  }
}

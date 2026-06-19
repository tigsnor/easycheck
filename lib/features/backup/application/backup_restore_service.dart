import '../../experiments/data/experiment_repository.dart';
import '../../experiments/domain/experiment.dart';
import '../../plates/data/plate_repository.dart';
import '../../plates/domain/plate.dart';
import '../domain/easycheck_backup_service.dart';

class BackupRestoreException implements Exception {
  const BackupRestoreException({
    required this.restoreError,
    this.rollbackErrors = const [],
  });

  final Object restoreError;
  final List<Object> rollbackErrors;

  bool get rollbackCompleted => rollbackErrors.isEmpty;

  @override
  String toString() {
    if (rollbackCompleted) {
      return '백업 복원에 실패하여 기존 데이터로 되돌렸습니다: $restoreError';
    }
    return '백업 복원과 기존 데이터 복구에 모두 실패했습니다. '
        '복원 오류: $restoreError / 복구 오류: ${rollbackErrors.join('; ')}';
  }
}

class BackupRestoreService {
  const BackupRestoreService({
    required this.experimentRepository,
    required this.plateRepository,
  });

  final ExperimentRepository experimentRepository;
  final PlateRepository plateRepository;

  Future<void> restore(EasyCheckBackup backup) async {
    _validate(backup);

    final existingExperiments = await experimentRepository.loadExperiments();
    final experimentSnapshots = <String, Experiment?>{
      for (final experiment in backup.experiments)
        experiment.id: _findExperiment(existingExperiments, experiment.id),
    };
    final plateSnapshots = <String, Plate?>{};
    for (final plate in backup.plates) {
      plateSnapshots[plate.experimentId] = await plateRepository.loadPlate(
        plate.experimentId,
      );
    }

    try {
      for (final experiment in backup.experiments) {
        await experimentRepository.saveExperiment(experiment);
      }
      for (final plate in backup.plates) {
        await plateRepository.savePlate(plate);
      }
    } on Object catch (restoreError) {
      final rollbackErrors = await _rollback(
        experimentSnapshots: experimentSnapshots,
        plateSnapshots: plateSnapshots,
      );
      throw BackupRestoreException(
        restoreError: restoreError,
        rollbackErrors: rollbackErrors,
      );
    }
  }

  Experiment? _findExperiment(List<Experiment> experiments, String id) {
    for (final experiment in experiments) {
      if (experiment.id == id) {
        return experiment;
      }
    }
    return null;
  }

  void _validate(EasyCheckBackup backup) {
    if (backup.schemaVersion < 1 ||
        backup.schemaVersion > EasyCheckBackupService.currentSchemaVersion) {
      throw FormatException(
        '지원하지 않는 백업 schemaVersion입니다: ${backup.schemaVersion}',
      );
    }

    final experimentIds = backup.experiments.map((item) => item.id).toList();
    final plateIds = backup.plates.map((item) => item.id).toList();
    final plateExperimentIds =
        backup.plates.map((item) => item.experimentId).toList();

    if (experimentIds.toSet().length != experimentIds.length) {
      throw const FormatException('중복된 실험 ID가 있습니다.');
    }
    if (plateIds.toSet().length != plateIds.length) {
      throw const FormatException('중복된 Plate ID가 있습니다.');
    }
    if (plateExperimentIds.toSet().length != plateExperimentIds.length) {
      throw const FormatException('한 실험에 Plate가 두 개 이상 포함되어 있습니다.');
    }
    final experimentIdSet = experimentIds.toSet();
    if (plateExperimentIds.any((id) => !experimentIdSet.contains(id))) {
      throw const FormatException('연결된 실험이 없는 Plate가 있습니다.');
    }
  }

  Future<List<Object>> _rollback({
    required Map<String, Experiment?> experimentSnapshots,
    required Map<String, Plate?> plateSnapshots,
  }) async {
    final errors = <Object>[];

    for (final entry in plateSnapshots.entries) {
      try {
        final snapshot = entry.value;
        if (snapshot == null) {
          await plateRepository.deletePlate(entry.key);
        } else {
          await plateRepository.savePlate(snapshot);
        }
      } on Object catch (error) {
        errors.add(error);
      }
    }

    for (final entry in experimentSnapshots.entries) {
      try {
        final snapshot = entry.value;
        if (snapshot == null) {
          await experimentRepository.deleteExperiment(entry.key);
        } else {
          await experimentRepository.saveExperiment(snapshot);
        }
      } on Object catch (error) {
        errors.add(error);
      }
    }

    return errors;
  }
}

import '../../attachments/domain/experiment_attachment.dart';
import '../../attachments/data/attachment_file_store.dart';
import '../../plates/templates/data/plate_template_repository.dart';
import '../../plates/templates/domain/plate_template.dart';
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
    this.templateRepository,
    this.attachmentFileStore,
  });

  final ExperimentRepository experimentRepository;
  final PlateRepository plateRepository;
  final PlateTemplateRepository? templateRepository;
  final AttachmentFileStore? attachmentFileStore;

  Future<void> restore(EasyCheckBackup backup) async {
    const EasyCheckBackupService().validate(backup);
    if (backup.templates.isNotEmpty && templateRepository == null) {
      throw StateError('템플릿 저장소가 필요합니다.');
    }

    if (backup.attachmentFiles.isNotEmpty && attachmentFileStore == null) {
      throw StateError('첨부파일 저장소가 필요합니다.');
    }
    final existingExperiments = await experimentRepository.loadExperiments();
    final incomingIds = backup.experiments.map((e) => e.id).toSet();
    validateAttachmentBudget([
      for (final e in existingExperiments)
        if (!incomingIds.contains(e.id)) ...e.attachments,
      for (final e in backup.experiments) ...e.attachments,
    ]);
    // Immutable blobs are committed first. A failure cannot publish missing files.
    // Unreferenced blobs are retained so rollback and deletion undo remain safe.
    for (final blob in backup.attachmentFiles.values) {
      await attachmentFileStore!.write(blob);
    }
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

    final existingTemplates = backup.templates.isEmpty
        ? <PlateTemplate>[]
        : await templateRepository!.loadTemplates();
    final templatesById = {
      for (final template in existingTemplates) template.id: template
    };
    final templateSnapshots = <String, PlateTemplate?>{
      for (final template in backup.templates)
        template.id: templatesById[template.id],
    };

    try {
      for (final experiment in backup.experiments) {
        await experimentRepository.saveExperiment(experiment);
      }
      for (final plate in backup.plates) {
        await plateRepository.savePlate(plate);
      }
      for (final template in backup.templates) {
        await templateRepository!.saveTemplate(template);
      }
    } on Object catch (restoreError) {
      final rollbackErrors = await _rollback(
        experimentSnapshots: experimentSnapshots,
        plateSnapshots: plateSnapshots,
        templateSnapshots: templateSnapshots,
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

  Future<List<Object>> _rollback({
    required Map<String, Experiment?> experimentSnapshots,
    required Map<String, Plate?> plateSnapshots,
    required Map<String, PlateTemplate?> templateSnapshots,
  }) async {
    final errors = <Object>[];
    for (final entry in templateSnapshots.entries) {
      try {
        if (entry.value == null) {
          await templateRepository!.deleteTemplate(entry.key);
        } else {
          await templateRepository!.saveTemplate(entry.value!);
        }
      } on Object catch (error) {
        errors.add(error);
      }
    }

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

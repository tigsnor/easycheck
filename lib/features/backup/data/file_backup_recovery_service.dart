import '../../attachments/data/attachment_file_store.dart';
import 'dart:io';

import '../../../shared/data/local_data_directory.dart';
import '../../../shared/data/safe_json_file_store.dart';
import '../../experiments/data/file_experiment_repository.dart';
import '../../plates/data/file_plate_repository.dart';
import '../../plates/templates/data/file_plate_template_repository.dart';
import '../domain/easycheck_backup_service.dart';

abstract interface class BackupRecoveryService {
  Future<void> recover(EasyCheckBackup backup);
}

/// Recovery replaces the active dataset, retaining the old files untouched.
/// Staging and validation finish before the active-generation pointer is written.
class FileBackupRecoveryService implements BackupRecoveryService {
  const FileBackupRecoveryService({
    this.rootDirectory,
    this.fileStore = const SafeJsonFileStore(),
  });

  final String? rootDirectory;
  final SafeJsonFileStore fileStore;

  @override
  Future<void> recover(EasyCheckBackup backup) async {
    const codec = EasyCheckBackupService();
    codec.validate(backup);
    // Detach from caller-owned lists before the first asynchronous operation.
    final frozen = codec.decode(codec.encode(
      experiments: backup.experiments,
      plates: backup.plates,
      templates: backup.templates,
      attachmentFiles: backup.attachmentFiles,
      exportedAt: backup.exportedAt,
    ));
    final includesTemplates = backup.includesTemplates;
    await LocalDataDirectory.exclusive(rootDirectory, (root) async {
      final generations =
          Directory('${root.path}/${LocalDataDirectory.generationsName}');
      await generations.create(recursive: true);
      final staged = await generations.createTemp('restore-');
      final name = staged.uri.pathSegments.where((s) => s.isNotEmpty).last;
      await fileStore.write(File('${staged.path}/experiments.json'), {
        'schemaVersion': FileExperimentRepository.schemaVersion,
        'data': frozen.experiments.map((e) => e.toJson()).toList(),
      });
      for (final plate in frozen.plates) {
        final id =
            plate.experimentId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
        await fileStore.write(File('${staged.path}/plates/$id.json'), {
          'schemaVersion': FilePlateRepository.schemaVersion,
          'data': plate.toJson(),
        });
      }
      if (includesTemplates) {
        await fileStore.write(File('${staged.path}/plate_templates.json'), {
          'schemaVersion': FilePlateTemplateRepository.schemaVersion,
          'data': frozen.templates.map((t) => t.toJson()).toList(),
        });
      } else {
        // V1 has no template payload: preserve existing template bytes, including
        // backup and recovery candidates, without decoding a possibly bad file.
        final previous = await LocalDataDirectory.active(root);
        if (await previous.exists()) {
          await for (final entry in previous.list(followLinks: false)) {
            final basename = entry.uri.pathSegments.last;
            if (entry is File &&
                (basename == 'plate_templates.json' ||
                    basename.startsWith('plate_templates.json.'))) {
              await entry.copy('${staged.path}/$basename');
            }
          }
        }
      }
      // Exercise the same on-disk readers that the app will use after restart.
      final experiments =
          await FileExperimentRepository(rootDirectory: staged.path)
              .loadExperiments();
      final plates = FilePlateRepository(rootDirectory: staged.path);
      if (experiments.length != frozen.experiments.length) {
        throw const FormatException('복구 데이터 검증에 실패했습니다.');
      }
      for (final plate in frozen.plates) {
        if (await plates.loadPlate(plate.experimentId) == null) {
          throw const FormatException('복구 Plate가 누락되었습니다.');
        }
      }
      if (includesTemplates) {
        final templates =
            await FilePlateTemplateRepository(rootDirectory: staged.path)
                .loadTemplates();
        if (templates.length != frozen.templates.length) {
          throw const FormatException('복구 템플릿이 누락되었습니다.');
        }
      }
      final attachments = FileAttachmentFileStore(rootDirectory: staged.path);
      for (final blob in frozen.attachmentFiles.values) {
        await attachments.write(blob);
      }
      for (final experiment in experiments) {
        for (final attachment in experiment.attachments) {
          await attachments.read(attachment);
        }
      }
      await fileStore.write(
          File('${staged.path}/${LocalDataDirectory.readyName}'),
          {'schemaVersion': 1});
      await LocalDataDirectory.publish(root, name, fileStore);
      // Nothing that can fail is performed after publication. Unused staging
      // folders and the previous generation remain available for recovery.
    });
  }
}

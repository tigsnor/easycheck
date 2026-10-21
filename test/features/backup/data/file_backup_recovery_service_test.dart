import 'dart:async';
import 'dart:io';

import 'package:easycheck/features/backup/data/file_backup_recovery_service.dart';
import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/experiments/data/file_experiment_repository.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/plates/data/file_plate_repository.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/templates/data/file_plate_template_repository.dart';
import 'package:easycheck/features/plates/templates/domain/plate_template.dart';
import 'package:easycheck/shared/data/local_data_directory.dart';
import 'package:easycheck/shared/data/safe_json_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() async =>
      root = await Directory.systemTemp.createTemp('platenote-recovery-'));
  tearDown(() async => root.delete(recursive: true));

  test(
      'recovers corrupt data without changing original bytes and survives restart',
      () async {
    await Directory('${root.path}/plates').create();
    final originals = <String, String>{
      'experiments.json': '{broken experiments',
      'experiments.json.bak': '{broken backup',
      'plates/e.json': '{broken plate',
      'plate_templates.json': '{broken templates',
    };
    for (final entry in originals.entries) {
      await File('${root.path}/${entry.key}').writeAsString(entry.value);
    }
    await FileBackupRecoveryService(rootDirectory: root.path).recover(backup());
    final experiments = FileExperimentRepository(rootDirectory: root.path);
    expect((await experiments.loadExperiments()).single.title, 'Restored');
    expect(
        (await FilePlateRepository(rootDirectory: root.path).loadPlate('e'))!
            .name,
        'Restored Plate');
    expect(
        (await FilePlateTemplateRepository(rootDirectory: root.path)
                .loadTemplates())
            .single
            .id,
        't');
    for (final entry in originals.entries) {
      expect(
          await File('${root.path}/${entry.key}').readAsString(), entry.value);
    }
    await experiments.saveExperiment(experiment('new'));
    expect(
        await FileExperimentRepository(rootDirectory: root.path)
            .loadExperiments(),
        hasLength(2));
  });

  test('version 1 recovery preserves existing template storage', () async {
    await FilePlateTemplateRepository(rootDirectory: root.path)
        .saveTemplate(template());
    final before =
        await File('${root.path}/plate_templates.json').readAsBytes();
    await FileBackupRecoveryService(rootDirectory: root.path)
        .recover(backup(version: 1));
    expect(
        (await FilePlateTemplateRepository(rootDirectory: root.path)
                .loadTemplates())
            .single
            .id,
        't');
    final active = await LocalDataDirectory.access(root.path, (d) async => d);
    expect(await File('${active.path}/plate_templates.json').readAsBytes(),
        before);
  });

  test(
      'failed activation never exposes staging data, even with a complete next pointer',
      () async {
    await FileExperimentRepository(rootDirectory: root.path)
        .saveExperiment(experiment('old'));
    await expectLater(
        FileBackupRecoveryService(
                rootDirectory: root.path, fileStore: _FailPublicationStore())
            .recover(backup()),
        throwsStateError);
    expect(
        (await FileExperimentRepository(rootDirectory: root.path)
                .loadExperiments())
            .single
            .id,
        'old');
    expect(
        await File('${root.path}/${LocalDataDirectory.pointerName}').exists(),
        isFalse);
    await FileBackupRecoveryService(rootDirectory: root.path).recover(backup());
    expect(
        (await FileExperimentRepository(rootDirectory: root.path)
                .loadExperiments())
            .single
            .id,
        'e');
  });

  test('concurrent writes wait for activation and target the new dataset',
      () async {
    final store = _PausedPublicationStore();
    final recovery =
        FileBackupRecoveryService(rootDirectory: root.path, fileStore: store)
            .recover(backup());
    await store.started.future;
    final pendingSave = FileExperimentRepository(rootDirectory: root.path)
        .saveExperiment(experiment('later'));
    store.resume.complete();
    await recovery;
    await pendingSave;
    expect(
        (await FileExperimentRepository(rootDirectory: root.path)
                .loadExperiments())
            .map((e) => e.id),
        containsAll(['e', 'later']));
  });

  test(
      'repeated recovery replaces the active list and retains prior generations',
      () async {
    final service = FileBackupRecoveryService(rootDirectory: root.path);
    await service.recover(backup());
    await FileExperimentRepository(rootDirectory: root.path)
        .saveExperiment(experiment('extra'));
    final previous = await LocalDataDirectory.access(root.path, (d) async => d);
    await service.recover(backup());
    expect(
        (await FileExperimentRepository(rootDirectory: root.path)
                .loadExperiments())
            .map((e) => e.id),
        ['e']);
    expect(
        await FileExperimentRepository(rootDirectory: previous.path)
            .loadExperiments(),
        hasLength(2));
  });

  test(
      'invalid backup and unsafe pointers do not turn data into an empty store',
      () async {
    final invalid = EasyCheckBackup(
        schemaVersion: 2,
        exportedAt: DateTime.now(),
        experiments: [],
        plates: [plate()]);
    await expectLater(
        FileBackupRecoveryService(rootDirectory: root.path).recover(invalid),
        throwsFormatException);
    expect(
        await File('${root.path}/${LocalDataDirectory.pointerName}').exists(),
        isFalse);
    await File('${root.path}/${LocalDataDirectory.pointerName}')
        .writeAsString('{"schemaVersion":1,"generation":"../../elsewhere"}');
    await expectLater(
        FileExperimentRepository(rootDirectory: root.path).loadExperiments(),
        throwsA(isA<JsonFileCorruptionException>()));
    // A v2 backup can repair the pointer without reading damaged old state.
    await FileBackupRecoveryService(rootDirectory: root.path).recover(backup());
    expect(
        await FileExperimentRepository(rootDirectory: root.path)
            .loadExperiments(),
        hasLength(1));
  });
}

Experiment experiment(String id) => Experiment(
    id: id,
    title: 'Restored',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026));
Plate plate() => Plate(id: 'p', experimentId: 'e', name: 'Restored Plate');
PlateTemplate template() =>
    PlateTemplate.fromPlate(id: 't', name: 'My template', plate: plate());
EasyCheckBackup backup({int version = 2}) => EasyCheckBackup(
    schemaVersion: version,
    exportedAt: DateTime.utc(2026),
    experiments: [experiment('e')],
    plates: [plate()],
    templates: version >= 2 ? [template()] : []);

class _FailPublicationStore extends SafeJsonFileStore {
  @override
  Future<void> write(File file, Object? value,
      {bool Function(Object?)? validator}) async {
    await super.write(file, value, validator: validator);
    if (file.path.endsWith('${LocalDataDirectory.pointerName}.next')) {
      throw StateError('simulated activation failure');
    }
  }
}

class _PausedPublicationStore extends SafeJsonFileStore {
  final started = Completer<void>();
  final resume = Completer<void>();
  @override
  Future<void> write(File file, Object? value,
      {bool Function(Object?)? validator}) async {
    if (file.path.endsWith('${LocalDataDirectory.pointerName}.next')) {
      started.complete();
      await resume.future;
    }
    await super.write(file, value, validator: validator);
  }
}

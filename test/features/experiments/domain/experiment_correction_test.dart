import 'dart:convert';
import 'dart:io';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/data/file_experiment_repository.dart';
import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/backup/data/file_backup_recovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Experiment original() => Experiment(
          id: 'e',
          title: 'Original',
          notes: '원래 관찰 기록',
          status: ExperimentStatus.completed,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026, 10),
          completedAt: DateTime.utc(2026, 10),
          tasks: const [
            ExperimentTask(id: 't', title: '관찰', isCompleted: true)
          ],
          resources: const [
            ExperimentResource(
                id: 'r',
                type: ExperimentResourceType.reagent,
                name: '시약',
                lotOrSerial: 'LOT123')
          ],
          revisions: [
            ExperimentRevision(
                id: 'r', changedAt: DateTime.utc(2026, 10), summary: '실험 완료')
          ]);

  test(
      'only completed notes with a reason can start correction; snapshot excludes recursive history',
      () {
    final before = original();
    expect(() => before.beginCorrection(' ', DateTime.now()), throwsStateError);
    for (final status in ExperimentStatus.values
        .where((s) => s != ExperimentStatus.completed)) {
      expect(
          () => before
              .copyWith(status: status)
              .beginCorrection('정정', DateTime.now()),
          throwsStateError);
    }
    final corrected =
        before.beginCorrection(' Lot 확인 ', DateTime.utc(2026, 11));
    expect(corrected.isReadOnly, isFalse);
    expect(before.isReadOnly, isTrue);
    expect(
        before.copyWith(status: ExperimentStatus.archived).isReadOnly, isTrue);
    expect(corrected.completedAt, before.completedAt);
    expect(corrected.revisions.first.toJson(), before.revisions.first.toJson());
    expect(corrected.revisions.last.reason, 'Lot 확인');
    expect(corrected.revisions.last.before!.toJson(),
        before.copyWith(revisions: []).toJson());
    expect(
        Experiment.fromJson(corrected.toJson()).toJson(), corrected.toJson());
  });

  test(
      'correction status, reason and original note survive restart and fresh backup recovery',
      () async {
    final root = await Directory.systemTemp.createTemp('correction-');
    final restored =
        await Directory.systemTemp.createTemp('correction-restored-');
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => restored.delete(recursive: true));
    final corrected = original()
        .beginCorrection('Lot 확인', DateTime.utc(2026, 11))
        .copyWith(notes: '정정 관찰 기록');
    await FileExperimentRepository(rootDirectory: root.path)
        .saveExperiment(corrected);
    final loaded = (await FileExperimentRepository(rootDirectory: root.path)
            .loadExperiments())
        .single;
    expect(loaded.toJson(), corrected.toJson());
    const codec = EasyCheckBackupService();
    final backup =
        codec.decode(codec.encode(experiments: [loaded], plates: []));
    expect(backup.schemaVersion, 8);
    await FileBackupRecoveryService(rootDirectory: restored.path)
        .recover(backup);
    final recovered =
        (await FileExperimentRepository(rootDirectory: restored.path)
                .loadExperiments())
            .single;
    expect(recovered.toJson(), corrected.toJson());
    expect(recovered.revisions.last.before!.notes, '원래 관찰 기록');
    expect(recovered.revisions.last.before!.resources.single.lotOrSerial,
        'LOT123');
    expect(recovered.revisions.last.before!.tasks.single.isCompleted, isTrue);
  });

  test(
      'v3 experiments and v5 backups keep old completed records without inventing correction snapshots',
      () async {
    final root = await Directory.systemTemp.createTemp('correction-legacy-');
    addTearDown(() => root.delete(recursive: true));
    final before = original();
    await File('${root.path}/experiments.json').writeAsString(jsonEncode({
      'schemaVersion': 3,
      'data': [before.toJson()]
    }));
    final repo = FileExperimentRepository(rootDirectory: root.path);
    final loaded = (await repo.loadExperiments()).single;
    expect(loaded.toJson(), before.toJson());
    expect(loaded.revisions.single.before, isNull);
    const codec = EasyCheckBackupService();
    final legacy = jsonDecode(codec.encode(experiments: [before], plates: []))
        as Map<String, dynamic>;
    legacy['schemaVersion'] = 5;
    expect(codec.decode(jsonEncode(legacy)).experiments.single.toJson(),
        before.toJson());
    await repo
        .saveExperiment(loaded.beginCorrection('정정', DateTime.utc(2026, 11)));
    final envelope =
        jsonDecode(await File('${root.path}/experiments.json').readAsString())
            as Map;
    expect(envelope['schemaVersion'], 5);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:easycheck/features/backup/data/file_backup_recovery_service.dart';
import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/experiments/data/file_experiment_repository.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/domain/protocol_editing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/protocol_fixture.dart';

void main() {
  final at = DateTime.utc(2026, 11, 3);
  Experiment source() {
    final e = protocolExperiment(status: ExperimentStatus.inProgress);
    return e.copyWith(tasks: [
      e.tasks.first
          .copyWith(startedAt: at)
          .resetExecution(TaskExecutionAction.restart, '새 시료', at),
      ...e.tasks.skip(1)
    ]);
  }

  test(
      'audited changes preserve current and archived execution; recorded steps cannot disappear',
      () {
    final e = source();
    final after = [
      e.tasks[1],
      e.tasks.first.copyWith(title: '준비 정정'),
      const ExperimentTask(id: 'new', title: '추가 관찰')
    ];
    final revision = ProtocolEditing.revision(e, after, '순서와 이름 정정', at);
    expect(revision.before!.tasks.first.toJson(), e.tasks.first.toJson());
    expect(
        revision.protocolAfterTasks![1].executionHistory.single.reason, '새 시료');
    expect(revision.protocolAfterTasks![1].startedAt, at);
    expect(revision.protocolAfterTasks![1].plannedMinutes, 10);
    expect(revision.protocolAfterTasks![1].reminderEnabled, true);
    for (final bad in [
      [e.tasks[1]],
      [
        e.tasks.first.copyWith(startedAt: at.add(const Duration(minutes: 1))),
        e.tasks[1]
      ],
      [e.tasks.first.copyWith(executionHistory: []), e.tasks[1]],
    ]) {
      expect(() => ProtocolEditing.revision(e, bad, '변경', at),
          throwsFormatException);
    }
    expect(() => ProtocolEditing.revision(e, after, '  ', at),
        throwsFormatException);
    expect(() => ProtocolEditing.revision(e, e.tasks, '변경 없음', at),
        throwsFormatException);
    final later = [after.first, after[1].copyWith(title: '다음 이름'), after.last];
    final next = ProtocolEditing.revision(
        e.copyWith(tasks: after, revisions: [revision]), later, '두 번째', at);
    expect(next.id, isNot(revision.id));
    expect(revision.protocolAfterTasks![1].title, '준비 정정');
  });

  test(
      'malformed protocol snapshots fail closed, legacy revision remains readable',
      () {
    final e = source();
    final r = ProtocolEditing.revision(e,
            [e.tasks.first.copyWith(title: '정정'), ...e.tasks.skip(1)], '사유', at)
        .toJson();
    final task = e.tasks.first.toJson();
    for (final value in [
      {...r, 'reason': ' '},
      {...r, 'before': null},
      {...r, 'protocolAfterTasks': []},
      {
        ...r,
        'protocolAfterTasks': [task, task]
      },
      {
        ...r,
        'protocolAfterTasks': ['bad']
      },
      {
        ...r,
        'before': {
          ...e.toJson(),
          'tasks': [task, 'bad']
        }
      },
    ]) {
      expect(() => ExperimentRevision.fromJson(value), throwsFormatException);
    }
    final old = {...r}..remove('protocolAfterTasks');
    expect(ExperimentRevision.fromJson(old).protocolAfterTasks, isNull);
    final empty =
        protocolExperiment(status: ExperimentStatus.inProgress, tasks: []);
    final initial =
        ProtocolEditing.revision(empty, [e.tasks.last], '계획 추가', at);
    expect(
        ExperimentRevision.fromJson(initial.toJson()).before!.tasks, isEmpty);
  });

  test(
      'file restart, fresh backup recovery and legacy formats retain protocol snapshots',
      () async {
    final root = await Directory.systemTemp.createTemp('protocol-history-');
    final recovery = await Directory.systemTemp.createTemp('protocol-recover-');
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => recovery.delete(recursive: true));
    final e = source();
    final after = [e.tasks.first.copyWith(title: '수정 단계'), ...e.tasks.skip(1)];
    final updated = e.copyWith(
        tasks: after,
        revisions: [ProtocolEditing.revision(e, after, 'SOP 확인', at)]);
    await FileExperimentRepository(rootDirectory: root.path)
        .saveExperiment(updated);
    final loaded = (await FileExperimentRepository(rootDirectory: root.path)
            .loadExperiments())
        .single;
    expect(loaded.toJson(), updated.toJson());
    expect(
        jsonDecode(await File('${root.path}/experiments.json').readAsString())[
            'schemaVersion'],
        7);
    const codec = EasyCheckBackupService();
    final backup =
        codec.decode(codec.encode(experiments: [loaded], plates: []));
    expect(backup.schemaVersion, 12);
    await FileBackupRecoveryService(rootDirectory: recovery.path)
        .recover(backup);
    expect(
        (await FileExperimentRepository(rootDirectory: recovery.path)
                .loadExperiments())
            .single
            .toJson(),
        updated.toJson());
    await File('${root.path}/legacy.json').writeAsString(jsonEncode({
      'schemaVersion': 6,
      'data': [e.toJson()]
    }));
    expect(
        (await FileExperimentRepository(
                    rootDirectory: root.path, fileName: 'legacy.json')
                .loadExperiments())
            .single
            .tasks
            .first
            .title,
        e.tasks.first.title);
    final legacy = jsonDecode(codec.encode(experiments: [e], plates: []))
        as Map<String, dynamic>;
    legacy['schemaVersion'] = 11;
    expect(
        codec.decode(jsonEncode(legacy)).experiments.single.revisions, isEmpty);
  });
}

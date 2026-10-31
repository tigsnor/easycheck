import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/data/file_experiment_repository.dart';
import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/backup/data/file_backup_recovery_service.dart';

void main() {
  final start = DateTime.utc(2026, 10, 31, 1);
  final reset = start.add(const Duration(minutes: 2));
  final running = ExperimentTask(
      id: 't',
      title: '반응',
      startedAt: start,
      plannedMinutes: 30,
      reminderEnabled: true);

  test(
      'cancel, new start, completion, restart and reopen retain each previous record',
      () {
    final cancelled =
        running.resetExecution(TaskExecutionAction.cancelStart, ' 오시작 ', reset);
    expect(cancelled.startedAt, isNull);
    expect(cancelled.dueAt, isNull);
    expect(cancelled.isCompleted, false);
    final first = cancelled.executionHistory.single;
    expect(first.startedAt, start);
    expect(first.reason, '오시작');
    expect(first.plannedMinutes, 30);
    expect(first.reminderEnabled, true);
    final done = cancelled.copyWith(
        startedAt: reset,
        isCompleted: true,
        completedAt: reset.add(const Duration(minutes: 30)));
    final repeated = done.resetExecution(TaskExecutionAction.restart, '새 시료',
        reset.add(const Duration(hours: 1)));
    expect(repeated.executionHistory.length, 2);
    expect(repeated.executionHistory.last.completedAt, done.completedAt);
    expect(repeated.executionHistory.last.wasCompleted, true);
    expect(repeated.completedAt, isNull);
    expect(repeated.isCompleted, false);
    expect(repeated.dueAt, reset.add(const Duration(minutes: 90)));
    final reopened =
        done.resetExecution(TaskExecutionAction.reopen, '완료 체크 해제', reset);
    expect(reopened.startedAt, done.startedAt);
    expect(reopened.executionHistory.last.completedAt, done.completedAt);
    expect(
        ExperimentTask.fromJson(repeated.toJson()).toJson(), repeated.toJson());
    expect(running.executionHistory, isEmpty);
  });

  test(
      'legacy completion without start stays honest; invalid transitions are rejected',
      () {
    final legacy = ExperimentTask.fromJson(
        {'id': 't', 'title': 'old', 'isCompleted': true});
    final repeated =
        legacy.resetExecution(TaskExecutionAction.restart, '재실행', reset);
    expect(repeated.executionHistory.single.startedAt, isNull);
    expect(repeated.executionHistory.single.completedAt, isNull);
    expect(repeated.startedAt, reset);
    final unstarted = const ExperimentTask(id: 't', title: 'new');
    for (final action in TaskExecutionAction.values) {
      expect(() => unstarted.resetExecution(action, 'reason', reset),
          throwsStateError);
    }
    expect(
        () => running.resetExecution(TaskExecutionAction.restart, ' ', reset),
        throwsStateError);
    expect(
        () => legacy.resetExecution(
            TaskExecutionAction.cancelStart, 'oops', reset),
        throwsStateError);
  });

  test('malformed history is rejected instead of silently dropping records',
      () {
    final task =
        running.resetExecution(TaskExecutionAction.cancelStart, '오시작', reset);
    final record = task.executionHistory.single.toJson();
    for (final value in [
      'bad',
      [null],
      [
        {...record, 'action': 'unknown'}
      ],
      [
        {...record, 'reason': ''}
      ],
      [
        {...record, 'recordedAt': 'invalid'}
      ],
      [
        {...record, 'wasCompleted': 'false'}
      ],
      [
        {...record, 'plannedMinutes': -1}
      ],
    ]) {
      expect(
          () => ExperimentTask.fromJson(
              {...task.toJson(), 'executionHistory': value}),
          throwsFormatException);
    }
  });

  test(
      'file restart and fresh backup restoration preserve history; v4 files and v7 backup remain readable',
      () async {
    final root = await Directory.systemTemp.createTemp('task-history-');
    final recoveredRoot =
        await Directory.systemTemp.createTemp('task-history-recovery-');
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => recoveredRoot.delete(recursive: true));
    final task =
        running.resetExecution(TaskExecutionAction.restart, '새 시료', reset);
    final experiment = Experiment(
        id: 'e',
        title: 'Assay',
        createdAt: start,
        updatedAt: reset,
        tasks: [task]);
    await FileExperimentRepository(rootDirectory: root.path)
        .saveExperiment(experiment);
    final loaded = (await FileExperimentRepository(rootDirectory: root.path)
            .loadExperiments())
        .single;
    expect(loaded.toJson(), experiment.toJson());
    final envelope =
        jsonDecode(await File('${root.path}/experiments.json').readAsString());
    expect(envelope['schemaVersion'], 5);
    const codec = EasyCheckBackupService();
    final encoded = codec.encode(experiments: [loaded], plates: []);
    final backup = codec.decode(encoded);
    expect(backup.schemaVersion, 8);
    await FileBackupRecoveryService(rootDirectory: recoveredRoot.path)
        .recover(backup);
    expect(
        (await FileExperimentRepository(rootDirectory: recoveredRoot.path)
                .loadExperiments())
            .single
            .toJson(),
        experiment.toJson());
    final legacy = experiment.toJson();
    legacy['tasks'] = [
      {...running.toJson()}..remove('executionHistory')
    ];
    await File('${root.path}/legacy.json').writeAsString(jsonEncode({
      'schemaVersion': 4,
      'data': [legacy]
    }));
    final old = (await FileExperimentRepository(
                rootDirectory: root.path, fileName: 'legacy.json')
            .loadExperiments())
        .single;
    expect(old.tasks.single.executionHistory, isEmpty);
    expect(old.tasks.single.startedAt, start);
    final oldBackup = jsonDecode(encoded) as Map<String, dynamic>;
    oldBackup['schemaVersion'] = 7;
    oldBackup['experiments'] = [legacy];
    expect(
        codec
            .decode(jsonEncode(oldBackup))
            .experiments
            .single
            .tasks
            .single
            .executionHistory,
        isEmpty);
    final bad = jsonDecode(encoded) as Map<String, dynamic>;
    bad['experiments'][0]['tasks'][0]['executionHistory'] = [null];
    expect(() => codec.decode(jsonEncode(bad)), throwsFormatException);
  });
}

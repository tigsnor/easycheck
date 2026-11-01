import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/domain/experiment_completion_review.dart';
import 'package:easycheck/features/experiments/data/file_experiment_repository.dart';
import 'package:easycheck/features/experiments/presentation/widgets/task_actual_times_dialog.dart';
import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/backup/data/file_backup_recovery_service.dart';
import 'package:easycheck/features/reminders/domain/task_reminder.dart';
import 'package:easycheck/features/reminders/domain/task_reminder_target.dart';

void main() {
  final now = DateTime.utc(2026, 11, 1, 12);
  final start = now.subtract(const Duration(minutes: 10));
  final end = now.subtract(const Duration(minutes: 1));
  const blank = ExperimentTask(
      id: 't', title: '반응', plannedMinutes: 30, reminderEnabled: true);
  Experiment experiment(ExperimentTask task) => Experiment(
      id: 'e', title: 'Assay', createdAt: start, updatedAt: now, tasks: [task]);

  test(
      'retrospective times keep actual and recording instants separate, no-op and legacy missing start stay honest',
      () {
    final running = blank.recordActualTimes(
        start: start, completion: null, reason: '메모 확인', now: now);
    expect(running.startedAt, start);
    expect(running.isCompleted, false);
    expect(running.executionMetadata.startRecordedAt, now);
    expect(running.executionMetadata.completionRecordedAt, isNull);
    expect(running.executionHistory.single.startedAt, isNull);
    final done = running.recordActualTimes(
        start: start, completion: end, reason: '완료 기록 누락', now: now);
    expect(done.completedAt, end);
    expect(done.isCompleted, true);
    expect(done.executionMetadata.startRecordedAt, now);
    expect(done.executionMetadata.completionRecordedAt, now);
    expect(done.executionHistory.last.metadata.startRecordedAt, now);
    expect(
        identical(
            done.recordActualTimes(
                start: start.toLocal(),
                completion: end.toLocal(),
                reason: '',
                now: now),
            done),
        true);
    final completionOnly = blank.recordActualTimes(
        start: null, completion: end, reason: '시작은 모름', now: now);
    expect(completionOnly.startedAt, isNull);
    expect(completionOnly.isCompleted, true);
    final legacy = blank.copyWith(isCompleted: true).recordActualTimes(
        start: start, completion: null, reason: '시작만 확인', now: now);
    expect(legacy.isCompleted, true);
    expect(legacy.completedAt, isNull);
    final reopened =
        done.resetExecution(TaskExecutionAction.reopen, '완료 정정', now);
    expect(reopened.executionMetadata.completionRecordedAt, isNull);
    expect(reopened.executionMetadata.startRecordedAt, now);
    final restarted =
        done.resetExecution(TaskExecutionAction.restart, '다시 실험', now);
    expect(restarted.executionMetadata.startRecordedAt, isNull);
    expect(restarted.executionHistory.last.metadata.completionRecordedAt, now);
    expect(ExperimentTask.fromJson(done.toJson()).toJson(), done.toJson());
  });

  test(
      'rejects future, reversed, absent or erased actual times and missing reasons',
      () {
    for (final pair in [
      (null, null),
      (now.add(const Duration(seconds: 1)), null),
      (start, start.subtract(const Duration(seconds: 1))),
      (null, now.add(const Duration(seconds: 1)))
    ]) {
      expect(
          () => blank.recordActualTimes(
              start: pair.$1, completion: pair.$2, reason: '사유', now: now),
          throwsFormatException);
    }
    expect(
        () => blank.recordActualTimes(
            start: start, completion: end, reason: ' ', now: now),
        throwsFormatException);
    final done = blank.recordActualTimes(
        start: start, completion: end, reason: '사유', now: now);
    expect(
        () => done.recordActualTimes(
            start: null, completion: end, reason: '삭제', now: now),
        throwsFormatException);
    expect(
        () => done.recordActualTimes(
            start: start, completion: null, reason: '삭제', now: now),
        throwsFormatException);
  });

  test(
      'skip is distinct from completion, suppresses alarms, preserves provenance and review reasons',
      () {
    final running = blank.recordActualTimes(
        start: start, completion: null, reason: '기록 누락', now: now);
    final originalAlarm = buildTaskReminders([experiment(running)], now).single;
    final skipped =
        running.resetExecution(TaskExecutionAction.skip, '시료 부족', now);
    expect(skipped.isSkipped, true);
    expect(skipped.isCompleted, false);
    expect(skipped.isFinished, true);
    expect(skipped.startedAt, isNull);
    expect(skipped.completedAt, isNull);
    expect(skipped.dueAt, isNull);
    expect(skipped.executionHistory.last.startedAt, start);
    expect(skipped.executionHistory.last.metadata.startRecordedAt, now);
    expect(buildTaskReminders([experiment(skipped)], now), isEmpty);
    expect(
        TaskReminderTarget.parse(originalAlarm.payload)!
            .message(experiment(skipped)),
        contains('생략된 단계'));
    final review = const ExperimentCompletionReviewService()
        .review(experiment(skipped), null);
    expect(review.issues.any((i) => i.title.contains('미완료 단계')), false);
    expect(review.record('확인'), contains('시료 부족'));
    expect(
        () => skipped.recordActualTimes(
            start: start, completion: end, reason: 'x', now: now),
        throwsStateError);
    final pending =
        skipped.resetExecution(TaskExecutionAction.unskip, '시료 확보', now);
    expect(pending.isFinished, false);
    expect(pending.startedAt, isNull);
    expect(pending.executionHistory.last.metadata.skipReason, '시료 부족');
    expect(buildTaskReminders([experiment(pending)], now), isEmpty);
  });

  test(
      'strict local time parser rejects normalized invalid dates and keeps subsecond originals',
      () {
    final original = DateTime.utc(2026, 11, 1, 2, 3, 4, 123, 456);
    expect(parseActualTime(actualTimeInput(original), original), original);
    expect(parseActualTime('2026-02-28 09:30', null),
        DateTime(2026, 2, 28, 9, 30));
    for (final invalid in [
      '2026-02-30 09:00',
      '2026-01-01 24:00',
      '2026-13-01 12:00',
      '2026-01-01 12:60',
      '2026-01-01 12:00:60',
      'yesterday'
    ]) {
      expect(() => parseActualTime(invalid, null), throwsFormatException);
    }
  });

  test('malformed provenance and skip states are rejected before restoring',
      () {
    final skipped = blank.resetExecution(TaskExecutionAction.skip, '부족', now);
    for (final patch in [
      {'isCompleted': true},
      {'startedAt': start.toIso8601String()},
      {
        'executionMetadata': {'skippedAt': now.toIso8601String()}
      },
      {
        'executionMetadata': {'skipReason': 'orphan'}
      },
      {
        'executionMetadata': {'startRecordedAt': now.toIso8601String()}
      },
      {
        'executionMetadata': {
          'skippedAt': '2026-11-01 12:00',
          'skipReason': 'timezone missing'
        }
      },
    ]) {
      expect(() => ExperimentTask.fromJson({...skipped.toJson(), ...patch}),
          throwsFormatException);
    }
    final retrospective = blank.recordActualTimes(
        start: start, completion: end, reason: '기록', now: now);
    expect(
        () => ExperimentTask.fromJson({
              ...retrospective.toJson(),
              'executionMetadata': {
                'startRecordedAt':
                    start.subtract(const Duration(seconds: 1)).toIso8601String()
              }
            }),
        throwsFormatException);
    final encoded = const EasyCheckBackupService()
        .encode(experiments: [experiment(skipped)], plates: []);
    final bad = jsonDecode(encoded);
    bad['experiments'][0]['tasks'][0]['executionMetadata']['skipReason'] = '';
    expect(() => const EasyCheckBackupService().decode(jsonEncode(bad)),
        throwsFormatException);
  });

  test(
      'disk and backup keep current and historical provenance; older metadata remains unknown',
      () async {
    final root = await Directory.systemTemp.createTemp('retrospective-');
    final recovered =
        await Directory.systemTemp.createTemp('retrospective-recovered-');
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => recovered.delete(recursive: true));
    final task = blank
        .recordActualTimes(
            start: start, completion: null, reason: '기록 누락', now: now)
        .resetExecution(TaskExecutionAction.skip, '시료 부족', now);
    final e = experiment(task);
    await FileExperimentRepository(rootDirectory: root.path).saveExperiment(e);
    final stored = (await FileExperimentRepository(rootDirectory: root.path)
            .loadExperiments())
        .single;
    expect(stored.toJson(), e.toJson());
    const codec = EasyCheckBackupService();
    final backup =
        codec.decode(codec.encode(experiments: [stored], plates: []));
    expect(backup.schemaVersion, 9);
    await FileBackupRecoveryService(rootDirectory: recovered.path)
        .recover(backup);
    expect(
        (await FileExperimentRepository(rootDirectory: recovered.path)
                .loadExperiments())
            .single
            .toJson(),
        e.toJson());
    final oldTask = blank.copyWith(startedAt: start).toJson()
      ..remove('executionMetadata');
    expect(ExperimentTask.fromJson(oldTask).executionMetadata.startRecordedAt,
        isNull);
    final oldRecord = blank
        .copyWith(startedAt: start)
        .resetExecution(TaskExecutionAction.restart, 'old', now)
        .executionHistory
        .single
        .toJson()
      ..remove('metadata');
    expect(TaskExecutionRecord.fromJson(oldRecord).metadata.startRecordedAt,
        isNull);
    final oldExperiment = experiment(blank).toJson();
    oldExperiment['tasks'] = [
      {
        ...oldTask,
        'executionHistory': [oldRecord]
      }
    ];
    await File('${root.path}/legacy.json').writeAsString(jsonEncode({
      'schemaVersion': 5,
      'data': [oldExperiment]
    }));
    final legacy = (await FileExperimentRepository(
                rootDirectory: root.path, fileName: 'legacy.json')
            .loadExperiments())
        .single;
    expect(legacy.tasks.single.executionHistory.single.metadata.startRecordedAt,
        isNull);
    final oldBackup =
        jsonDecode(codec.encode(experiments: [stored], plates: []));
    oldBackup['schemaVersion'] = 8;
    oldBackup['experiments'] = [oldExperiment];
    expect(
        codec
            .decode(jsonEncode(oldBackup))
            .experiments
            .single
            .tasks
            .single
            .executionMetadata
            .skippedAt,
        isNull);
  });
}

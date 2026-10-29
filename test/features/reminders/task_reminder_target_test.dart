import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/reminders/domain/task_reminder.dart';
import 'package:easycheck/features/reminders/domain/task_reminder_target.dart';
import '../../support/reminder_fixture.dart';

void main() {
  test('existing payload round trips opaque IDs and UTC deadline', () {
    final e = timedExperiment(id: '한글/"id')
        .copyWith(tasks: [timedExperiment().tasks.single.copyWith()]);
    final reminder = buildTaskReminders([e], reminderNow).single;
    final target = TaskReminderTarget.parse(reminder.payload)!;
    expect(target.experimentId, e.id);
    expect(target.taskId, e.tasks.single.id);
    expect(target.dueAt, e.tasks.single.dueAt);
    expect(target.message(e), startsWith('알림에서 연 단계'));
    expect(
        TaskReminderTarget.parse(reminder.payload)!.identity, target.identity);
  });
  test(
      'malformed, foreign, missing and oversized payloads never select a record',
      () {
    for (final payload in <String?>[
      null,
      '',
      'another-feature',
      '$taskReminderPrefix{',
      '$taskReminderPrefix[]',
      '$taskReminderPrefix${jsonEncode([1, 2, 3, 4])}',
      '$taskReminderPrefix${jsonEncode([
            '[]',
            '2026-10-29T00:00:00Z',
            '',
            ''
          ])}',
      '$taskReminderPrefix${jsonEncode([
            '["e",""]',
            '2026-10-29T00:00:00Z',
            '',
            ''
          ])}',
      '$taskReminderPrefix${jsonEncode(['["e","t"]', 'invalid', '', ''])}',
      '$taskReminderPrefix${jsonEncode([
            '["e","t"]',
            '2026-10-29T00:00:00',
            '',
            ''
          ])}',
      '$taskReminderPrefix${'x' * 32768}',
    ]) {
      expect(TaskReminderTarget.parse(payload), isNull,
          reason: payload?.substring(0, payload.length.clamp(0, 60)));
    }
  });
  test(
      'current records determine stale, completed, missing and locked messages',
      () {
    final e = timedExperiment();
    final target = TaskReminderTarget.parse(
        buildTaskReminders([e], reminderNow).single.payload)!;
    for (final changed in [
      e.copyWith(title: 'Renamed'),
      e.copyWith(tasks: [e.tasks.single.copyWith(plannedMinutes: 60)]),
      e.copyWith(tasks: [e.tasks.single.copyWith(reminderEnabled: false)]),
      e.copyWith(tasks: [e.tasks.single.copyWith(startedAt: null)])
    ]) {
      expect(target.message(changed), contains('변경되었습니다'));
    }
    expect(target.message(e.copyWith(tasks: [])), contains('단계가 현재 노트에 없습니다'));
    expect(
        target.message(
            e.copyWith(tasks: [e.tasks.single.copyWith(isCompleted: true)])),
        contains('이미 완료'));
    for (final status in [
      ExperimentStatus.completed,
      ExperimentStatus.archived
    ]) {
      expect(target.message(e.copyWith(status: status)), contains('읽기 전용'));
    }
    expect(target.message(e.copyWith(status: ExperimentStatus.correcting)),
        contains('정정 중'));
  });
}

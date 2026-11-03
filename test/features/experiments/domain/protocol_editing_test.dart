import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/domain/protocol_editing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/protocol_fixture.dart';

void main() {
  test('editable statuses allow structure changes; execution requires a reason',
      () {
    for (final status in ExperimentStatus.values) {
      expect(ProtocolEditing.canEdit(protocolExperiment(status: status)),
          !protocolExperiment(status: status).isReadOnly);
    }
    final t = protocolExperiment().tasks.first;
    final now = DateTime.utc(2026);
    for (final recorded in [
      t.copyWith(startedAt: now),
      t.copyWith(completedAt: now),
      t.copyWith(isCompleted: true),
      t.copyWith(
          startedAt: now,
          executionMetadata: TaskExecutionMetadata(startRecordedAt: now)),
      t.resetExecution(TaskExecutionAction.skip, '생략', now),
      t
          .copyWith(startedAt: now)
          .resetExecution(TaskExecutionAction.cancelStart, '오시작', now),
    ]) {
      final source = protocolExperiment(tasks: [recorded]);
      expect(ProtocolEditing.canEdit(source), true);
      expect(ProtocolEditing.requiresReason(source), true);
      expect(
          ProtocolEditing.validate(source, [recorded.copyWith(title: '변경')])
              .single
              .title,
          '변경');
      expect(
          () => ProtocolEditing.validate(
              source, [const ExperimentTask(id: 'new', title: '대체')]),
          throwsFormatException);
    }
  });

  test(
      'rename/reorder/delete keep IDs and timer settings and survive serialization',
      () {
    final source = protocolExperiment();
    final result = ProtocolEditing.validate(
        source, [source.tasks[1], source.tasks[0].copyWith(title: '시약 준비')]);
    expect(result.map((t) => t.id), ['b', 'a']);
    expect(result.last.plannedMinutes, 10);
    expect(result.last.reminderEnabled, true);
    expect(result.last.executionHistory, isEmpty);
    final restored =
        Experiment.fromJson(source.copyWith(tasks: result).toJson());
    expect(
        restored.tasks.map((t) => t.toJson()), result.map((t) => t.toJson()));
    expect(source.tasks.first.title, '시료 준비');
    final spaced =
        protocolExperiment(tasks: [source.tasks.first.copyWith(title: ' 준비 ')]);
    expect(ProtocolEditing.validate(spaced, spaced.tasks).single.title, ' 준비 ');
  });

  test(
      'empty/duplicate names or IDs and hidden timer/execution changes are rejected',
      () {
    final source = protocolExperiment();
    final task = source.tasks.first;
    for (final draft in <List<ExperimentTask>>[
      [],
      [task, task],
      [task.copyWith(title: '')],
      [task.copyWith(title: ' ')],
      [task.copyWith(title: ' 변경 ')],
      [task.copyWith(plannedMinutes: 20)],
      [task.copyWith(reminderEnabled: false)],
      [const ExperimentTask(id: 'new', title: '새 단계', isCompleted: true)],
    ]) {
      expect(
          () => ProtocolEditing.validate(source, draft), throwsFormatException);
    }
    expect(
        ProtocolEditing.validate(
            source, [task, const ExperimentTask(id: 'new', title: '새 단계')]),
        hasLength(2));
  });

  test(
      'saved name/order/deletion edits block execution while new steps and timer-only drafts preserve existing immediate saves',
      () {
    final saved = protocolExperiment().tasks;
    for (final draft in [
      saved.reversed.toList(),
      saved.skip(1).toList(),
      [saved.first.copyWith(title: '바꿈'), ...saved.skip(1)]
    ]) {
      expect(ProtocolEditing.changesSavedDefinition(saved, draft), true);
    }
    expect(
        ProtocolEditing.changesSavedDefinition(
            saved, [const ExperimentTask(id: 'new', title: '추가'), ...saved]),
        false);
    expect(
        ProtocolEditing.changesSavedDefinition(saved,
            [saved.first.copyWith(plannedMinutes: 20), ...saved.skip(1)]),
        false);
  });
}

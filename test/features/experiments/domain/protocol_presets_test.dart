import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/domain/protocol_editing.dart';
import 'package:easycheck/features/experiments/domain/protocol_presets.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/protocol_fixture.dart';

void main() {
  test(
      'MTT distinguishes dissolution; recommendations never invent time or reminders',
      () {
    final mtt = ProtocolPresets.initialTasks('MTT');
    expect(
        mtt.map((t) => t.title),
        containsAllInOrder(
            ['MTT 시약 투입', 'Formazan 생성 반응', 'Formazan 용해', 'Plate reader 측정']));
    expect(ProtocolPresets.titles('CCK-8'), isNot(contains('Formazan 용해')));
    for (final type in ['CCK-8', 'MTT', 'ELISA', 'Dose-response', 'Custom']) {
      final tasks = ProtocolPresets.initialTasks(type);
      expect(tasks.map((t) => t.id).toSet(), hasLength(tasks.length));
      expect(
          tasks.every((t) =>
              t.plannedMinutes == null &&
              !t.reminderEnabled &&
              !ProtocolEditing.hasExecution(t)),
          true);
    }
  });

  test(
      'replacement reuses matching IDs/settings, previews removal, and avoids ID collisions',
      () {
    final base = protocolExperiment();
    final e = base.copyWith(tasks: [
      base.tasks.first.copyWith(title: '세포 seeding'),
      const ExperimentTask(id: 'new-0', title: '사용자 단계'),
      const ExperimentTask(
          id: 'duplicate', title: '세포 seeding', plannedMinutes: 20)
    ]);
    final after =
        ProtocolPresets.apply(e, 'MTT', ProtocolPresetMode.replace, 'new');
    expect(after, hasLength(8));
    expect(after.first.toJson(), e.tasks.first.toJson());
    expect(after.map((t) => t.id), isNot(contains('duplicate')));
    expect(after.map((t) => t.id), isNot(contains('new-0')));
    expect(after.map((t) => t.id).toSet(), hasLength(8));
    expect(ProtocolEditing.describe(e.tasks, after), contains('삭제: 사용자 단계'));
    expect(e.tasks, hasLength(3));
  });

  test(
      'after execution only keep/append preserve every record; repeated append is idempotent',
      () {
    final e = protocolExperiment(status: ExperimentStatus.inProgress);
    final recorded = e.copyWith(tasks: [
      e.tasks.first
          .copyWith(title: '세포 seeding', startedAt: DateTime.utc(2026)),
      ...e.tasks.skip(1)
    ]);
    expect(
        () => ProtocolPresets.apply(
            recorded, 'MTT', ProtocolPresetMode.replace, 'p'),
        throwsFormatException);
    final after =
        ProtocolPresets.apply(recorded, 'MTT', ProtocolPresetMode.append, 'p');
    expect(after.take(3).map((t) => t.toJson()),
        recorded.tasks.map((t) => t.toJson()));
    final twice = ProtocolPresets.apply(
        recorded.copyWith(tasks: after), 'MTT', ProtocolPresetMode.append, 'p');
    expect(twice.map((t) => t.toJson()), after.map((t) => t.toJson()));
    expect(
        ProtocolPresets.canReplace(
            recorded.copyWith(status: ExperimentStatus.planned)),
        false);
    expect(
        ProtocolPresets.canReplace(
            e.copyWith(status: ExperimentStatus.correcting)),
        false);
    for (final status in [
      ExperimentStatus.completed,
      ExperimentStatus.archived
    ]) {
      expect(
          () => ProtocolPresets.apply(
              e.copyWith(status: status), 'MTT', ProtocolPresetMode.keep, 'p'),
          throwsFormatException);
    }
  });

  test(
      'type-only changes produce immutable old/new type history with existing serialized fields',
      () {
    final e = protocolExperiment(status: ExperimentStatus.inProgress)
        .copyWith(experimentType: 'CCK-8');
    final r = ProtocolEditing.revision(e, e.tasks, '분류 정정', DateTime.utc(2026),
        afterType: 'MTT');
    final decoded = ExperimentRevision.fromJson(r.toJson());
    expect(decoded.before!.experimentType, 'CCK-8');
    expect(decoded.summary, '실험 유형 변경: CCK-8 → MTT');
    expect(decoded.protocolAfterTasks!.map((t) => t.toJson()),
        e.tasks.map((t) => t.toJson()));
    expect(
        () => ProtocolEditing.revision(e, e.tasks, '사유', DateTime.utc(2026),
            afterType: 'CCK-8'),
        throwsFormatException);
  });
}

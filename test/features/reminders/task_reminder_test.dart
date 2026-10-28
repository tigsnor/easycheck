import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/data/file_experiment_repository.dart';
import 'package:easycheck/features/experiments/application/experiment_duplication_service.dart';
import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/backup/data/file_backup_recovery_service.dart';
import 'package:easycheck/features/reminders/application/task_reminder_coordinator.dart';
import 'package:easycheck/features/reminders/domain/task_reminder.dart';
import 'package:easycheck/features/reminders/data/task_reminder_service.dart';
import '../../support/reminder_fixture.dart';
import '../plates/presentation/plate_editor_screen_test.dart'
    show FakePlateRepository;

void main() {
  test(
      'UTC deadlines, planned time and preferences survive disk and fresh backup recovery',
      () async {
    final dir = await Directory.systemTemp.createTemp('reminders-');
    final restoredDir =
        await Directory.systemTemp.createTemp('reminders-restored-');
    addTearDown(() => dir.delete(recursive: true));
    addTearDown(() => restoredDir.delete(recursive: true));
    final source = timedExperiment();
    final task = ExperimentTask.fromJson({
      ...source.tasks.single.toJson(),
      'startedAt': '2026-10-28T12:00:00+09:00'
    });
    expect(task.dueAt, DateTime.utc(2026, 10, 28, 3, 30));
    expect(task.toJson()['startedAt'], '2026-10-28T03:00:00.000Z');
    final repo = FileExperimentRepository(rootDirectory: dir.path);
    await repo.saveExperiment(source.copyWith(tasks: [task]));
    final loaded = (await repo.loadExperiments()).single;
    const backupService = EasyCheckBackupService();
    final backup = backupService
        .decode(backupService.encode(experiments: [loaded], plates: []));
    expect(backup.schemaVersion, 5);
    await FileBackupRecoveryService(rootDirectory: restoredDir.path)
        .recover(backup);
    final restored =
        (await FileExperimentRepository(rootDirectory: restoredDir.path)
                .loadExperiments())
            .single;
    expect(restored.tasks.single.dueAt, task.dueAt);
    expect(restored.tasks.single.reminderEnabled, true);
    final copy = await ExperimentDuplicationService(
            experimentRepository: repo, plateRepository: FakePlateRepository())
        .duplicateDesign(source.id);
    expect(copy.tasks.single.plannedMinutes, 30);
    expect(copy.tasks.single.reminderEnabled, false);
    expect(copy.tasks.single.dueAt, isNull);
  });

  test(
      'legacy tasks default to no alarm and invalid durations cannot enter a backup',
      () {
    final legacy = ExperimentTask.fromJson({'id': 't', 'title': '반응'});
    expect(legacy.plannedMinutes, isNull);
    expect(legacy.reminderEnabled, false);
    for (final value in [0, -1, 43201, 1.5, '30']) {
      expect(
          () => ExperimentTask.fromJson(
              {'id': 't', 'title': '반응', 'plannedMinutes': value}),
          throwsFormatException);
    }
    expect(
        () => ExperimentTask.fromJson(
            {'id': 't', 'title': '반응', 'reminderEnabled': true}),
        throwsFormatException);
    final source = timedExperiment();
    expect(
        () => const EasyCheckBackupService().encode(experiments: [
              source.copyWith(
                  tasks: [source.tasks.single.copyWith(plannedMinutes: 0)])
            ], plates: []),
        throwsFormatException);
  });

  test('only future active enabled tasks produce stable distinct IDs', () {
    final e = timedExperiment();
    final items = [
      e,
      timedExperiment(id: 'other'),
      e.copyWith(id: 'completed', status: ExperimentStatus.completed),
      e.copyWith(id: 'archived', status: ExperimentStatus.archived),
      e.copyWith(
          id: 'no-start', tasks: [e.tasks.single.copyWith(startedAt: null)]),
      e.copyWith(
          id: 'disabled',
          tasks: [e.tasks.single.copyWith(reminderEnabled: false)]),
      e.copyWith(
          id: 'task-done', tasks: [e.tasks.single.copyWith(isCompleted: true)])
    ];
    final first = buildTaskReminders(items, reminderNow);
    expect(first.length, 2);
    expect(first.map((e) => e.id).toSet().length, 2);
    expect(
        buildTaskReminders(items.reversed.toList(), reminderNow)
            .map((e) => e.id),
        first.map((e) => e.id));
    expect(
        buildTaskReminders(items, reminderNow.add(const Duration(minutes: 30))),
        isEmpty);
  });

  group('persisted notification reconciliation', () {
    late FakeReminderService os;
    late TaskReminderCoordinator coordinator;
    late List<Experiment> records;
    late DateTime now;
    setUp(() {
      records = [timedExperiment()];
      os = FakeReminderService();
      now = reminderNow;
      coordinator = TaskReminderCoordinator(
          loadExperiments: () async => records, service: os, now: () => now);
    });
    tearDown(() => coordinator.dispose());
    test('idempotent restart, changed duration and completed/deleted records',
        () async {
      await coordinator.refresh();
      await coordinator.refresh();
      expect(os.scheduled.length, 1);
      expect(os.requests, 0);
      final old = os.scheduled.single;
      records = [timedExperiment(minutes: 60)];
      await coordinator.refresh();
      expect(os.cancelled, contains(old.id));
      expect(os.scheduled.last.dueAt, now.add(const Duration(hours: 1)));
      records = [
        records.single.copyWith(
            tasks: [records.single.tasks.single.copyWith(isCompleted: true)])
      ];
      await coordinator.refresh();
      expect(os.entries, isEmpty);
      records = [timedExperiment()];
      await coordinator.refresh();
      records = [];
      await coordinator.refresh();
      expect(os.entries, isEmpty);
    });
    test(
        'permission is requested only explicitly and unsupported never schedules',
        () async {
      os.allowed = ReminderPermission.denied;
      await coordinator.refresh();
      expect(os.requests, 0);
      expect(os.entries, isEmpty);
      await coordinator.refresh(requestPermission: true);
      expect(os.requests, 1);
      os.allowed = ReminderPermission.granted;
      await coordinator.refresh();
      expect(os.entries.length, 1);
      os.allowed = ReminderPermission.denied;
      await coordinator.refresh();
      expect(os.entries, isEmpty);
      os.allowed = ReminderPermission.unsupported;
      await coordinator.refresh();
      expect(os.entries, isEmpty);
    });
    test('scheduling and cancellation failures are visible and retryable',
        () async {
      os.failSchedule = true;
      await coordinator.refresh();
      expect(coordinator.error, isNotNull);
      os.failSchedule = false;
      await coordinator.refresh();
      expect(coordinator.error, isNull);
      records = [];
      os.failCancel = true;
      await coordinator.refresh();
      expect(coordinator.error, isNotNull);
      os.failCancel = false;
      await coordinator.refresh();
      expect(coordinator.error, isNull);
      expect(os.entries, isEmpty);
    });
    test('read failure preserves existing OS reservations', () async {
      await coordinator.refresh();
      final broken = TaskReminderCoordinator(
          loadExperiments: () async => throw StateError('unreadable data'),
          service: os,
          now: () => now);
      await broken.refresh();
      expect(broken.error, isNotNull);
      expect(os.entries.length, 1);
      expect(os.cancelled, isEmpty);
      broken.dispose();
    });
    test('concurrent refreshes finish with latest persisted state', () async {
      final gate = Completer<void>();
      final entered = Completer<void>();
      os.gate = () async {
        if (!entered.isCompleted) entered.complete();
        await gate.future;
      };
      final first = coordinator.refresh();
      await entered.future;
      records = [];
      final second = coordinator.refresh();
      gate.complete();
      await Future.wait([first, second]);
      expect(os.entries, isEmpty);
      expect(coordinator.error, isNull);
    });
    test(
        'overdue restore never creates an alert, already delayed OS alert is retained',
        () async {
      await coordinator.refresh();
      now = now.add(const Duration(hours: 1));
      await coordinator.refresh();
      expect(os.scheduled.length, 1);
      expect(os.entries.length, 1);
      os.entries.clear();
      await coordinator.refresh();
      expect(os.entries, isEmpty);
      expect(os.scheduled.length, 1);
    });
    test('permission wait crossing deadline never schedules stale alarm',
        () async {
      os.gate = () async {
        now = now.add(const Duration(hours: 1));
      };
      await coordinator.refresh(requestPermission: true);
      expect(os.entries, isEmpty);
    });
    test('nearest 60 limit is visible and freed slots are replenished',
        () async {
      records = [
        for (var i = 0; i < 62; i++) timedExperiment(id: 'e-$i', minutes: i + 1)
      ];
      await coordinator.refresh();
      expect(os.entries.length, 60);
      expect(coordinator.deferredCount, 2);
      expect(os.scheduled.first.dueAt, now.add(const Duration(minutes: 1)));
      records.removeAt(0);
      await coordinator.refresh();
      expect(os.entries.length, 60);
      expect(coordinator.deferredCount, 1);
      expect(os.scheduled.last.dueAt, now.add(const Duration(minutes: 61)));
    });
    test('unrelated notifications are never cancelled or overwritten',
        () async {
      os.entries[42] = 'another-feature';
      await coordinator.refresh();
      records = [];
      await coordinator.refresh();
      expect(os.entries, {42: 'another-feature'});
    });
  });
}

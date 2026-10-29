import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/reminders/presentation/task_record_status.dart';
import 'package:easycheck/features/reminders/application/task_reminder_coordinator.dart';
import 'package:easycheck/features/reminders/data/task_reminder_service.dart';
import '../../support/reminder_fixture.dart';

class _UnconfirmedService extends FakeReminderService {
  bool hidePending = true;
  @override
  Future<Map<int, String?>> pending() async =>
      hidePending ? {} : super.pending();
}

class _UncancelledService extends FakeReminderService {
  bool ignoreCancel = true;
  @override
  Future<void> cancel(int id) async {
    if (!ignoreCancel) await super.cancel(id);
  }
}

void main() {
  late List<Experiment> records;
  late FakeReminderService os;
  late TaskReminderCoordinator coordinator;
  setUp(() {
    final now = DateTime.now();
    records = [
      Experiment(
          id: 'e',
          title: 'Assay',
          createdAt: now,
          updatedAt: now,
          status: ExperimentStatus.inProgress,
          tasks: [
            ExperimentTask(
                id: 't',
                title: '반응',
                startedAt: now,
                plannedMinutes: 30,
                reminderEnabled: true)
          ])
    ];
    os = FakeReminderService();
  });
  tearDown(() => coordinator.dispose());
  Future<void> show(WidgetTester tester,
      {Experiment? experiment,
      ExperimentTask? draft,
      bool saving = false,
      bool failed = false,
      bool withCoordinator = true}) async {
    final e = experiment ?? records.first;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TaskRecordStatus(
                experiment: e,
                task: draft ?? e.tasks.first,
                coordinator: withCoordinator ? coordinator : null,
                saving: saving,
                failed: failed))));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'saved reservation and dirty settings are distinguished from delivery',
      (tester) async {
    coordinator = TaskReminderCoordinator(
        loadExperiments: () async => records, service: os);
    await coordinator.refresh();
    await show(tester);
    expect(find.textContaining('단계 기록 저장됨'), findsOneWidget);
    expect(find.textContaining('알림 예약 확인됨 · 수신 보장 아님'), findsOneWidget);
    await show(tester,
        draft: records.first.tasks.first.copyWith(plannedMinutes: 60));
    expect(find.textContaining('단계 변경 미저장'), findsOneWidget);
    expect(find.textContaining('알림은 저장된 단계 기록을 기준'), findsOneWidget);
    expect(find.textContaining('알림 예약 확인됨'), findsOneWidget);
  });

  testWidgets('permission denied and unsupported never claim a saved alarm',
      (tester) async {
    coordinator = TaskReminderCoordinator(
        loadExperiments: () async => records, service: os);
    for (final permission in [
      ReminderPermission.denied,
      ReminderPermission.unsupported
    ]) {
      os.allowed = permission;
      await coordinator.refresh();
      await show(tester);
      expect(find.textContaining('단계 기록 저장됨'), findsOneWidget);
      expect(
          find.textContaining(permission == ReminderPermission.denied
              ? '알림 권한 꺼짐'
              : '종료 알림 미지원'),
          findsOneWidget);
      expect(find.textContaining('알림 예약 확인됨'), findsNothing);
      expect(os.requests, 0);
    }
  });

  testWidgets(
      'schedule and cancellation failures report uncertainty without unsaving records',
      (tester) async {
    coordinator = TaskReminderCoordinator(
        loadExperiments: () async => records, service: os);
    os.failSchedule = true;
    await coordinator.refresh();
    await show(tester);
    expect(find.textContaining('단계 기록 저장됨'), findsOneWidget);
    expect(find.textContaining('알림 예약·취소 확인 실패'), findsOneWidget);
    os.failSchedule = false;
    await coordinator.refresh();
    records = [
      records.first.copyWith(tasks: [
        records.first.tasks.first
            .copyWith(isCompleted: true, completedAt: DateTime.now())
      ])
    ];
    os.failCancel = true;
    await coordinator.refresh();
    await show(tester);
    expect(os.entries.length, 1);
    expect(find.textContaining('알림 예약·취소 확인 실패'), findsOneWidget);
    expect(find.textContaining('알림 예약 없음'), findsNothing);
    os.failCancel = false;
    await coordinator.refresh();
    await show(tester);
    expect(find.textContaining('완료 단계 · 알림 예약 없음'), findsOneWidget);
  });

  testWidgets(
      'reservation limit identifies deferred step and clears when capacity is freed',
      (tester) async {
    coordinator = TaskReminderCoordinator(
        loadExperiments: () async => records, service: os);
    final base = records.first;
    records = [
      for (var i = 0; i < 62; i++)
        base.copyWith(
            id: 'e-$i',
            tasks: [base.tasks.first.copyWith(plannedMinutes: i + 1)])
    ];
    await coordinator.refresh();
    expect(coordinator.deferredKeys.length, 2);
    await show(tester, experiment: records.last);
    expect(find.textContaining('예약 한도로 대기 중'), findsOneWidget);
    records.removeRange(0, 2);
    await coordinator.refresh();
    await show(tester, experiment: records.last);
    expect(coordinator.deferredKeys, isEmpty);
    expect(find.textContaining('알림 예약 확인됨'), findsOneWidget);
  });

  testWidgets('past deadline never implies the alert was received',
      (tester) async {
    coordinator = TaskReminderCoordinator(
        loadExperiments: () async => records, service: os);
    records = [
      records.first.copyWith(tasks: [
        records.first.tasks.first.copyWith(
            startedAt: DateTime.now().subtract(const Duration(hours: 1)))
      ])
    ];
    await coordinator.refresh();
    await show(tester);
    expect(os.entries, isEmpty);
    expect(find.textContaining('예정 시각 지남 · 수신 여부 확인 불가'), findsOneWidget);
  });

  testWidgets(
      'successful schedule call without matching OS reservation is not reported as confirmed',
      (tester) async {
    coordinator = TaskReminderCoordinator(
        loadExperiments: () async => records, service: os);
    coordinator.dispose();
    final service = _UnconfirmedService();
    coordinator = TaskReminderCoordinator(
        loadExperiments: () async => records, service: service);
    await coordinator.refresh();
    await show(tester);
    expect(service.scheduled.length, 1);
    expect(coordinator.scheduledKeys, isEmpty);
    expect(find.textContaining('예약 확인 필요'), findsOneWidget);
    service.hidePending = false;
    await coordinator.refresh();
    await show(tester);
    expect(find.textContaining('알림 예약 확인됨'), findsOneWidget);
  });

  testWidgets(
      'successful cancel call with a remaining OS alarm still reports uncertainty',
      (tester) async {
    final service = _UncancelledService();
    coordinator = TaskReminderCoordinator(
        loadExperiments: () async => records, service: service);
    await coordinator.refresh();
    records = [
      records.first.copyWith(
          tasks: [records.first.tasks.first.copyWith(isCompleted: true)])
    ];
    await coordinator.refresh();
    await show(tester);
    expect(find.textContaining('알림 예약·취소 확인 실패'), findsOneWidget);
    expect(find.textContaining('알림 예약 없음'), findsNothing);
    expect(service.entries.length, 1);
    service.ignoreCancel = false;
    await coordinator.refresh();
    await show(tester);
    expect(find.textContaining('완료 단계 · 알림 예약 없음'), findsOneWidget);
  });

  testWidgets(
      'busy, failed draft and absent coordinator do not imply saved or scheduled',
      (tester) async {
    coordinator = TaskReminderCoordinator(
        loadExperiments: () async => records, service: os);
    final gate = Completer<void>();
    os.gate = () => gate.future;
    final refreshing = coordinator.refresh();
    await tester.pump();
    await show(tester, saving: true);
    expect(find.textContaining('단계 기록 저장 중'), findsOneWidget);
    expect(find.textContaining('알림 동기화 중'), findsOneWidget);
    gate.complete();
    await refreshing;
    await show(tester,
        failed: true,
        draft: records.first.tasks.first.copyWith(isCompleted: true));
    expect(find.textContaining('단계 기록 저장 실패'), findsOneWidget);
    expect(find.textContaining('알림 예약 확인됨'), findsOneWidget);
    await show(tester, withCoordinator: false);
    expect(find.textContaining('알림 상태 확인 불가'), findsOneWidget);
  });
}

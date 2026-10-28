import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/presentation/experiments_home_screen.dart';
import 'package:easycheck/features/reminders/data/task_reminder_service.dart';
import '../../support/reminder_fixture.dart';
import '../experiments/presentation/experiments_home_screen_test.dart'
    show
        FakeExperimentRepository,
        FakePlateRepository,
        FakePlateTemplateRepository;

class _Repository extends FakeExperimentRepository {
  _Repository(super.experiments);
  bool fail = false;
  @override
  Future<void> saveExperiment(Experiment experiment) async {
    if (fail) throw StateError('disk full');
    await super.saveExperiment(experiment);
  }
}

void main() {
  late _Repository repo;
  late FakeReminderService os;
  setUp(() {
    final now = DateTime.now();
    repo = _Repository([
      Experiment(
          id: 'e',
          title: 'Timed assay',
          createdAt: now,
          updatedAt: now,
          status: ExperimentStatus.inProgress,
          tasks: const [ExperimentTask(id: 't', title: '반응')])
    ]);
    os = FakeReminderService();
  });
  Future<void> open(WidgetTester tester, {bool narrow = false}) async {
    await tester.pumpWidget(MaterialApp(
        builder: narrow
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!)
            : null,
        home: ExperimentsHomeScreen(
            repository: repo,
            plateRepository: FakePlateRepository(),
            plateTemplateRepository: FakePlateTemplateRepository(),
            reminderService: os)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Timed assay'));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(f, 200,
          scrollable: find.byType(Scrollable).first);
    }
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await reveal(tester, f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> configure(WidgetTester tester,
      {String minutes = '30', bool enabled = true}) async {
    await tap(tester, 'focused-task-time-t');
    await tester.enterText(
        find.byKey(const ValueKey('task-planned-minutes')), minutes);
    if (enabled) {
      await tester.tap(find.byKey(const ValueKey('task-reminder-enabled')));
    }
    await tap(tester, 'apply-task-timer');
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, '저장'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'settings validate, cancel, and remain unscheduled until start is saved',
      (tester) async {
    await open(tester);
    expect(os.requests, 0);
    await configure(tester, minutes: '0');
    expect(find.textContaining('1~43200분의 정수'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repo.experiments.single.tasks.single.plannedMinutes, isNull);
    await configure(tester);
    expect(os.entries, isEmpty);
    expect(repo.experiments.single.tasks.single.plannedMinutes, isNull);
    await save(tester);
    expect(repo.experiments.single.tasks.single.plannedMinutes, 30);
    expect(os.entries, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tap(tester, 'focused-task-t');
    expect(os.entries, isEmpty);
    await save(tester);
    expect(os.entries.length, 1);
    expect(
        os.scheduled.single.dueAt, repo.experiments.single.tasks.single.dueAt);
    expect(os.requests, 0);
  });

  testWidgets(
      'failed data save cannot publish an alarm and retry uses the same start',
      (tester) async {
    await open(tester);
    await configure(tester);
    await tap(tester, 'focused-task-t');
    repo.fail = true;
    await save(tester);
    expect(os.entries, isEmpty);
    expect(repo.experiments.single.tasks.single.startedAt, isNull);
    repo.fail = false;
    await save(tester);
    expect(os.entries.length, 1);
    final started = repo.experiments.single.tasks.single.startedAt;
    await save(tester);
    expect(repo.experiments.single.tasks.single.startedAt, started);
    expect(os.scheduled.length, 1);
  });

  testWidgets(
      'OS failure does not undo saved record, status allows retry and completion cancels',
      (tester) async {
    await open(tester);
    await configure(tester);
    await tap(tester, 'focused-task-t');
    os.failSchedule = true;
    await save(tester);
    expect(repo.experiments.single.tasks.single.startedAt, isNotNull);
    final status = find.textContaining('알림 예약 상태를 확인하지 못했습니다');
    await reveal(tester, status);
    expect(status, findsOneWidget);
    os.failSchedule = false;
    await tap(tester, 'refresh-reminders');
    expect(os.entries.length, 1);
    await tap(tester, 'focused-task-t');
    expect(os.entries.length,
        1); // Unsaved completion cannot cancel the saved running step.
    await save(tester);
    expect(os.entries, isEmpty);
    expect(repo.experiments.single.tasks.single.isCompleted, true);
  });

  testWidgets('permission request is explicit and resume rechecks settings',
      (tester) async {
    os.allowed = ReminderPermission.denied;
    await open(tester);
    await configure(tester);
    await tap(tester, 'focused-task-t');
    await save(tester);
    expect(os.entries, isEmpty);
    expect(os.requests, 0);
    await tap(tester, 'request-reminder-permission');
    expect(os.requests, 1);
    expect(os.entries, isEmpty);
    os.allowed = ReminderPermission.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(os.entries.length, 1);
    expect(os.requests, 1);
  });

  testWidgets('overdue display and completed note settings remain read-only',
      (tester) async {
    final e = repo.experiments.single;
    repo.experiments[0] = e.copyWith(tasks: [
      e.tasks.single.copyWith(
          startedAt: DateTime.now().subtract(const Duration(hours: 1)),
          plannedMinutes: 1,
          reminderEnabled: true)
    ]);
    await open(tester);
    expect(find.textContaining('초과'), findsOneWidget);
    expect(os.entries, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    repo.experiments[0] =
        repo.experiments.single.copyWith(status: ExperimentStatus.completed);
    await open(tester);
    await tap(tester, 'experiment-section-execution');
    final button = find.byKey(const ValueKey('focused-task-time-t'));
    await reveal(tester, button);
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    expect(os.entries, isEmpty);
  });

  testWidgets('deletion cancels a saved alarm and undo restores it',
      (tester) async {
    final e = repo.experiments.single;
    repo.experiments[0] = e.copyWith(tasks: [
      e.tasks.single.copyWith(
          startedAt: DateTime.now(), plannedMinutes: 30, reminderEnabled: true)
    ]);
    await open(tester);
    expect(os.entries.length, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tap(tester, 'confirm-delete-experiment-button');
    expect(repo.experiments, isEmpty);
    expect(os.entries, isEmpty);
    await tester.tap(find.text('실행 취소'));
    await tester.pumpAndSettle();
    expect(repo.experiments.length, 1);
    expect(os.entries.length, 1);
  });

  testWidgets('320px large text supports local-only deadline and clearing it',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, narrow: true);
    await configure(tester, minutes: '1440', enabled: false);
    await save(tester);
    expect(repo.experiments.single.tasks.single.plannedMinutes, 1440);
    expect(os.entries, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tap(tester, 'focused-task-time-t');
    await tester.tap(find.text('예정 시간 해제'));
    await tester.pumpAndSettle();
    await save(tester);
    expect(repo.experiments.single.tasks.single.plannedMinutes, isNull);
    expect(tester.takeException(), isNull);
  });
}

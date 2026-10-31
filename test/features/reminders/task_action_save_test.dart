import 'dart:async';
import 'package:easycheck/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/presentation/experiment_detail_screen.dart';
import 'package:easycheck/features/reminders/application/task_reminder_coordinator.dart';
import '../../support/reminder_fixture.dart';
import '../plates/presentation/plate_editor_screen_test.dart'
    show FakePlateRepository;

void main() {
  late Experiment stored;
  late FakeReminderService os;
  late TaskReminderCoordinator reminders;
  late List<Experiment> saved;
  late List<Experiment> attempts;
  bool fail = false;
  Completer<void>? gate;
  setUp(() {
    stored = Experiment(
        id: 'e',
        title: 'Assay',
        notes: 'Saved notes',
        status: ExperimentStatus.inProgress,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        tasks: const [
          ExperimentTask(
              id: 'a',
              title: '반응 A',
              plannedMinutes: 30,
              reminderEnabled: true),
          ExperimentTask(id: 'b', title: '반응 B'),
        ]);
    os = FakeReminderService();
    saved = [];
    attempts = [];
    fail = false;
    gate = null;
  });
  tearDown(() => reminders.dispose());
  Future<void> open(WidgetTester tester, {bool narrow = false}) async {
    await reminders.refresh();
    await tester.pumpWidget(MaterialApp(
        theme: buildEasyCheckTheme(),
        builder: narrow
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!)
            : null,
        home: ExperimentDetailScreen(
            experiment: stored,
            reminders: reminders,
            plateRepository: FakePlateRepository(),
            onChanged: (e) async {
              attempts.add(e);
              if (gate != null) await gate!.future;
              if (fail) throw StateError('disk full');
              stored = e;
              saved.add(e);
              await reminders.refresh();
            })));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(finder, 200,
          scrollable: find.byType(Scrollable).first);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, String value) =>
      tap(tester, find.byKey(ValueKey(value)));
  Future<void> section(WidgetTester tester, String value) =>
      key(tester, 'experiment-section-$value');
  Future<void> notes(WidgetTester tester, String text) async {
    final field = find.widgetWithText(TextField, '실행·관찰 메모');
    await reveal(tester, field);
    await tester.enterText(field, text);
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
  }

  Future<void> configure(
      WidgetTester tester, String button, String minutes) async {
    await key(tester, button);
    await tester.enterText(
        find.byKey(const ValueKey('task-planned-minutes')), minutes);
    tester.testTextInput.hide();
    await key(tester, 'apply-task-timer');
  }

  testWidgets(
      'start saves only target settings, advances planned status and preserves other drafts even invalid title',
      (tester) async {
    reminders = TaskReminderCoordinator(
        loadExperiments: () async => [stored], service: os);
    stored = stored.copyWith(status: ExperimentStatus.planned);
    await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Assay'), '');
    await section(tester, 'execution');
    await notes(tester, 'Draft notes');
    await tap(tester, find.byKey(const PageStorageKey('all-experiment-tasks')));
    await configure(tester, 'task-time-b', '45');
    await configure(tester, 'focused-task-time-a', '60');
    await key(tester, 'focused-task-a');
    expect(saved.length, 1);
    expect(stored.title, 'Assay');
    expect(stored.notes, 'Saved notes');
    expect(stored.status, ExperimentStatus.inProgress);
    expect(stored.tasks.first.plannedMinutes, 60);
    expect(stored.tasks.last.plannedMinutes, isNull);
    expect(stored.tasks.first.startedAt, isNotNull);
    expect(os.entries.length, 1);
    await section(tester, 'design');
    final title = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '실험 제목');
    expect(tester.widget<TextField>(title).controller!.text, isEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('저장하지 않은 변경이 있습니다'), findsOneWidget);
    await tap(tester, find.text('계속 편집'));
    await tester.enterText(title, 'Final title');
    await tap(tester, find.widgetWithText(TextButton, '저장'));
    expect(stored.notes, 'Draft notes');
    expect(stored.tasks.last.plannedMinutes, 45);
  });

  testWidgets(
      'failed start retries the original instant once without publishing an alarm',
      (tester) async {
    reminders = TaskReminderCoordinator(
        loadExperiments: () async => [stored], service: os);
    await open(tester);
    fail = true;
    await key(tester, 'focused-task-a');
    final first = attempts.single.tasks.first.startedAt;
    expect(first, isNotNull);
    expect(stored.tasks.first.startedAt, isNull);
    expect(os.entries, isEmpty);
    await reveal(tester, find.byKey(const ValueKey('focused-task-a')));
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('focused-task-a')))
            .onPressed,
        isNull);
    await tester.pump(const Duration(seconds: 10));
    fail = false;
    await key(tester, 'retry-task-record');
    expect(attempts.length, 2);
    expect(saved.length, 1);
    expect(stored.tasks.first.startedAt, first);
    expect(os.entries.length, 1);
    expect(stored.status, ExperimentStatus.inProgress);
  });

  testWidgets(
      'failed completion keeps saved alarm and discard restores step but preserves notes',
      (tester) async {
    reminders = TaskReminderCoordinator(
        loadExperiments: () async => [stored], service: os);
    final start = DateTime.now();
    stored = stored.copyWith(tasks: [
      stored.tasks.first.copyWith(startedAt: start),
      stored.tasks.last
    ]);
    await open(tester);
    await notes(tester, 'Keep this draft');
    fail = true;
    await key(tester, 'focused-task-a');
    expect(os.entries.length, 1);
    expect(stored.tasks.first.isCompleted, isFalse);
    await key(tester, 'discard-task-record');
    await tap(tester, find.widgetWithText(FilledButton, '단계 변경 취소'));
    expect(attempts.length, 1);
    await reveal(tester, find.widgetWithText(TextField, '실행·관찰 메모'));
    expect(find.text('Keep this draft'), findsOneWidget);
    expect(stored.tasks.first.startedAt, start);
    fail = false;
    await key(tester, 'focused-task-a');
    expect(stored.tasks.first.isCompleted, isTrue);
    expect(os.entries, isEmpty);
    expect(stored.notes, 'Saved notes');
  });

  testWidgets(
      'in-flight action blocks duplicate and back; typing elsewhere stays unsaved',
      (tester) async {
    reminders = TaskReminderCoordinator(
        loadExperiments: () async => [stored], service: os);
    await open(tester);
    gate = Completer<void>();
    await key(tester, 'focused-task-a');
    expect(attempts.length, 1);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('focused-task-a')))
            .onPressed,
        isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ExperimentDetailScreen), findsOneWidget);
    await notes(tester, 'Typed during save');
    gate!.complete();
    await tester.pumpAndSettle();
    expect(saved.length, 1);
    expect(stored.notes, 'Saved notes');
    expect(find.text('Typed during save'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('저장하지 않은 변경이 있습니다'), findsOneWidget);
  });

  testWidgets(
      'completed and archived reject actions; correction keeps state and original revision',
      (tester) async {
    reminders = TaskReminderCoordinator(
        loadExperiments: () async => [stored], service: os);
    for (final status in [
      ExperimentStatus.completed,
      ExperimentStatus.archived
    ]) {
      stored = stored.copyWith(status: status);
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      await section(tester, 'execution');
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('focused-task-a')))
              .onPressed,
          isNull);
      expect(saved, isEmpty);
    }
    stored = stored
        .copyWith(status: ExperimentStatus.completed)
        .beginCorrection('단계 기록 정정', DateTime.now());
    await tester.pumpWidget(const SizedBox());
    await open(tester);
    await section(tester, 'execution');
    await key(tester, 'focused-task-a');
    expect(stored.status, ExperimentStatus.correcting);
    expect(stored.revisions.first.reason, '단계 기록 정정');
    expect(stored.revisions.last.before!.tasks.first.startedAt, isNull);
    expect(os.entries, isEmpty);
  });

  testWidgets(
      'pending manually selected note status is not applied by step save',
      (tester) async {
    reminders = TaskReminderCoordinator(
        loadExperiments: () async => [stored], service: os);
    await open(tester);
    await section(tester, 'design');
    await tap(tester, find.byType(DropdownButtonFormField<ExperimentStatus>));
    await tap(tester, find.text('보관됨').last);
    await section(tester, 'execution');
    await key(tester, 'focused-task-a');
    expect(stored.status, ExperimentStatus.inProgress);
    await section(tester, 'design');
    expect(find.text('보관됨'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('저장하지 않은 변경이 있습니다'), findsOneWidget);
  });

  testWidgets(
      'completion retry uses original completion instant and preserves actual start',
      (tester) async {
    reminders = TaskReminderCoordinator(
        loadExperiments: () async => [stored], service: os);
    final start = DateTime.now().subtract(const Duration(minutes: 1));
    stored = stored.copyWith(tasks: [
      stored.tasks.first.copyWith(startedAt: start),
      stored.tasks.last
    ]);
    await open(tester);
    fail = true;
    await key(tester, 'focused-task-a');
    final completed = attempts.single.tasks.first.completedAt;
    await tester.pump(const Duration(seconds: 10));
    fail = false;
    await key(tester, 'retry-task-record');
    expect(stored.tasks.first.completedAt, completed);
    expect(stored.tasks.first.startedAt, start);
    expect(stored.status, ExperimentStatus.inProgress);
    expect(os.entries, isEmpty);
  });

  testWidgets(
      'starting a newly added task saves it without dropping existing tasks',
      (tester) async {
    reminders = TaskReminderCoordinator(
        loadExperiments: () async => [stored], service: os);
    await open(tester);
    for (final title in ['추가 관찰 X', '추가 관찰 Y']) {
      await tap(tester, find.text('단계 추가'));
      await tester.enterText(
          find.byKey(const ValueKey('new-experiment-task-field')), title);
      tester.testTextInput.hide();
      await tap(tester, find.widgetWithText(FilledButton, '추가'));
    }
    expect(saved, isEmpty);
    await tap(tester, find.byKey(const PageStorageKey('all-experiment-tasks')));
    for (final title in ['추가 관찰 Y', '추가 관찰 X']) {
      final row = find.widgetWithText(CheckboxListTile, title);
      await reveal(tester, row);
      await tap(
          tester,
          find.descendant(
              of: row, matching: find.widgetWithText(TextButton, '시작·저장')));
    }
    expect(stored.tasks.map((task) => task.title),
        ['반응 A', '반응 B', '추가 관찰 X', '추가 관찰 Y']);
    expect(stored.tasks[0].startedAt, isNull);
    expect(stored.tasks[1].startedAt, isNull);
    expect(stored.tasks[2].startedAt, isNotNull);
    expect(stored.tasks[3].startedAt, isNotNull);
  });

  testWidgets(
      '320px large text supports failed start retry without hiding next action',
      (tester) async {
    reminders = TaskReminderCoordinator(
        loadExperiments: () async => [stored], service: os);
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, narrow: true);
    fail = true;
    await key(tester, 'focused-task-a');
    fail = false;
    await key(tester, 'retry-task-record');
    await key(tester, 'focused-task-a');
    expect(stored.tasks.first.isCompleted, isTrue);
    await key(tester, 'focused-task-b');
    expect(stored.tasks.last.startedAt, isNotNull);
    expect(tester.takeException(), isNull);
  });

  Future<void> resetTask(
      WidgetTester tester, String control, String reason) async {
    await key(tester, control);
    await tester.enterText(find.widgetWithText(TextField, '변경 사유'), reason);
    tester.testTextInput.hide();
    await key(tester, 'confirm-task-reset');
  }

  testWidgets(
      'cancel start preserves history and notes even if OS cancellation fails',
      (tester) async {
    reminders = TaskReminderCoordinator(
        loadExperiments: () async => [stored], service: os);
    final start = DateTime.now();
    stored = stored.copyWith(tasks: [
      stored.tasks.first.copyWith(startedAt: start),
      stored.tasks.last
    ]);
    await open(tester);
    await notes(tester, 'Keep draft');
    os.failCancel = true;
    await resetTask(tester, 'focused-cancel-start-a', '잘못 누름');
    final task = stored.tasks.first;
    expect(task.startedAt, isNull);
    expect(task.executionHistory.single.startedAt, start.toUtc());
    expect(task.executionHistory.single.reason, '잘못 누름');
    expect(stored.notes, 'Saved notes');
    expect(stored.status, ExperimentStatus.inProgress);
    expect(os.entries, hasLength(1));
    expect(find.textContaining('알림 예약·취소 확인 실패'), findsWidgets);
    os.failCancel = false;
    await reminders.refresh();
    await tester.pumpAndSettle();
    expect(os.entries, isEmpty);
    await key(tester, 'focused-history-a');
    expect(find.textContaining('사유: 잘못 누름'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await key(tester, 'focused-task-a');
    expect(stored.tasks.first.startedAt, isNotNull);
    expect(stored.tasks.first.executionHistory, hasLength(1));
    expect(os.entries, hasLength(1));
    await reveal(tester, find.widgetWithText(TextField, '실행·관찰 메모'));
    expect(find.text('Keep draft'), findsOneWidget);
  });

  testWidgets(
      'failed restart retries exact timestamp and history once; discard leaves old execution',
      (tester) async {
    reminders = TaskReminderCoordinator(
        loadExperiments: () async => [stored], service: os);
    final start = DateTime.now().subtract(const Duration(minutes: 2));
    stored = stored.copyWith(tasks: [
      stored.tasks.first.copyWith(startedAt: start),
      stored.tasks.last
    ]);
    await open(tester);
    final oldPayload = os.entries.values.single;
    await configure(tester, 'focused-task-time-a', '60');
    fail = true;
    await resetTask(tester, 'focused-restart-a', '새 시료 재실행');
    final first = attempts.single.tasks.first;
    expect(stored.tasks.first.startedAt, start);
    expect(os.entries.values.single, oldPayload);
    expect(stored.tasks.first.executionHistory, isEmpty);
    await reveal(tester, find.byKey(const ValueKey('focused-restart-a')));
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('focused-restart-a')))
            .onPressed,
        isNull);
    await key(tester, 'discard-task-record');
    await tap(tester, find.widgetWithText(FilledButton, '단계 변경 취소'));
    expect(stored.tasks.first.executionHistory, isEmpty);
    await resetTask(tester, 'focused-restart-a', '새 시료 재실행');
    final retry = attempts.last.tasks.first;
    expect(retry.executionHistory, hasLength(1));
    expect(first.executionHistory.single.startedAt, start.toUtc());
    await tester.pump(const Duration(seconds: 10));
    fail = false;
    await key(tester, 'retry-task-record');
    expect(saved, hasLength(1));
    expect(stored.tasks.first.toJson(), retry.toJson());
    expect(stored.tasks.first.plannedMinutes, 60);
    expect(stored.tasks.first.executionHistory.single.plannedMinutes, 30);
    expect(stored.tasks.first.startedAt, isNot(start));
    expect(os.entries.values.single, isNot(oldPayload));
  });

  testWidgets(
      'completed step restart and completion reopening both preserve the old completion',
      (tester) async {
    reminders = TaskReminderCoordinator(
        loadExperiments: () async => [stored], service: os);
    final start = DateTime.now().subtract(const Duration(minutes: 5));
    final end = start.add(const Duration(minutes: 1));
    stored = stored.copyWith(tasks: [
      stored.tasks.first
          .copyWith(startedAt: start, isCompleted: true, completedAt: end),
      stored.tasks.last
    ]);
    await open(tester);
    await tap(tester, find.byKey(const PageStorageKey('all-experiment-tasks')));
    await resetTask(tester, 'task-restart-a', '추가 반복');
    expect(stored.tasks.first.isCompleted, false);
    expect(stored.tasks.first.executionHistory.single.completedAt, end.toUtc());
    final newStart = stored.tasks.first.startedAt;
    await key(tester, 'focused-task-a');
    final newEnd = stored.tasks.first.completedAt;
    await tap(tester, find.byKey(const ValueKey('experiment-task-a')));
    await key(tester, 'confirm-reopen-task');
    expect(stored.tasks.first.startedAt, newStart);
    expect(stored.tasks.first.executionHistory, hasLength(2));
    expect(
        stored.tasks.first.executionHistory.last.completedAt, newEnd!.toUtc());
    expect(stored.tasks.first.executionHistory.last.action,
        TaskExecutionAction.reopen);
    await tester.pumpWidget(const SizedBox());
    await open(tester);
    await key(tester, 'focused-history-a');
    expect(find.text('완료 해제'), findsOneWidget);
    expect(find.text('다시 시작'), findsOneWidget);
  });

  testWidgets(
      'read-only notes allow history inspection but reject resetting; correction keeps history',
      (tester) async {
    reminders = TaskReminderCoordinator(
        loadExperiments: () async => [stored], service: os);
    final task = stored.tasks.first
        .copyWith(startedAt: DateTime.now())
        .resetExecution(TaskExecutionAction.restart, '반복', DateTime.now());
    for (final status in [
      ExperimentStatus.completed,
      ExperimentStatus.archived
    ]) {
      stored =
          stored.copyWith(tasks: [task, stored.tasks.last], status: status);
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      await section(tester, 'execution');
      await reveal(tester, find.byKey(const ValueKey('focused-restart-a')));
      expect(
          tester
              .widget<TextButton>(
                  find.byKey(const ValueKey('focused-restart-a')))
              .onPressed,
          isNull);
      await key(tester, 'focused-history-a');
      expect(find.textContaining('사유: 반복'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    stored = stored
        .copyWith(status: ExperimentStatus.completed)
        .beginCorrection('기록 확인', DateTime.now());
    await tester.pumpWidget(const SizedBox());
    await open(tester);
    await section(tester, 'execution');
    await resetTask(tester, 'focused-cancel-start-a', '오시작 정정');
    expect(stored.status, ExperimentStatus.correcting);
    expect(stored.tasks.first.executionHistory, hasLength(2));
    expect(stored.revisions.last.before!.tasks.first.executionHistory,
        hasLength(1));
    expect(os.entries, isEmpty);
  });

  testWidgets(
      '320px large text and keyboard keep reason error visible and guard abandoned reason',
      (tester) async {
    reminders = TaskReminderCoordinator(
        loadExperiments: () async => [stored], service: os);
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    stored = stored.copyWith(tasks: [
      stored.tasks.first.copyWith(startedAt: DateTime.now()),
      stored.tasks.last
    ]);
    await open(tester, narrow: true);
    await key(tester, 'focused-cancel-start-a');
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await key(tester, 'confirm-task-reset');
    final error = find.text('사유를 입력해주세요.');
    expect(error, findsOneWidget);
    expect(tester.getBottomRight(error).dy, lessThan(560));
    expect(saved, isEmpty);
    await tester.enterText(find.widgetWithText(TextField, '변경 사유'), '오시작');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('입력한 사유를 버릴까요?'), findsOneWidget);
    await tap(tester, find.text('계속 입력'));
    expect(find.text('오시작'), findsOneWidget);
    await key(tester, 'confirm-task-reset');
    expect(stored.tasks.first.executionHistory.single.reason, '오시작');
    expect(tester.takeException(), isNull);
  });
}

import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/presentation/experiment_detail_screen.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../plates/presentation/plate_editor_screen_test.dart'
    show FakePlateRepository, FakePlateTemplateRepository;

void main() {
  late FakePlateRepository plates;
  late List<Experiment> saved;
  setUp(() {
    plates = FakePlateRepository();
    saved = [];
  });
  Experiment experiment(
          {ExperimentStatus status = ExperimentStatus.draft,
          List<ExperimentTask>? tasks}) =>
      Experiment(
          id: 'e',
          title: 'Assay',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          status: status,
          tasks: tasks ??
              const [
                ExperimentTask(id: 'first', title: '시료 준비'),
                ExperimentTask(id: 'second', title: '측정')
              ]);
  Future<void> open(WidgetTester tester,
      {Experiment? value,
      Future<void> Function(Experiment)? save,
      bool narrow = false}) async {
    await tester.pumpWidget(MaterialApp(
        builder: narrow
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!)
            : null,
        home: ExperimentDetailScreen(
            experiment: value ?? experiment(),
            plateRepository: plates,
            plateTemplateRepository: FakePlateTemplateRepository(),
            onChanged: save ??
                (value) async {
                  saved.add(value);
                })));
    await tester.pumpAndSettle();
  }

  Future<void> section(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(ValueKey('experiment-section-$name')));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 200,
          scrollable: find.byType(Scrollable).first);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('switches retain unsaved design, tasks and notes without writing',
      (tester) async {
    await open(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Assay'), 'Updated assay');
    await section(tester, 'execution');
    expect(find.text('시약 및 장비'), findsNothing);
    await tapKey(tester, 'focused-task-first');
    final notes = find.widgetWithText(TextField, '실행·관찰 메모');
    await reveal(tester, notes);
    await tester.enterText(notes, '기포 관찰');
    await section(tester, 'results');
    expect(find.textContaining('아직 Plate 기록이 없습니다'), findsOneWidget);
    await section(tester, 'design');
    expect(find.widgetWithText(TextField, 'Updated assay'), findsOneWidget);
    await section(tester, 'execution');
    await reveal(tester, notes);
    expect(find.text('기포 관찰'), findsOneWidget);
    expect(saved, isEmpty);
    expect(plates.saveCount, 0);
    await tester.tap(find.widgetWithText(TextButton, '저장'));
    await tester.pumpAndSettle();
    expect(saved.single.title, 'Updated assay');
    expect(saved.single.notes, '기포 관찰');
    expect(saved.single.tasks.first.startedAt, isNotNull);
  });

  testWidgets('leaving results still warns about changes made in design',
      (tester) async {
    await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Assay'), 'Unsaved');
    await section(tester, 'results');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('저장하지 않은 변경이 있습니다'), findsOneWidget);
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();
    await section(tester, 'design');
    expect(find.widgetWithText(TextField, 'Unsaved'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('running tasks take priority and completion reveals next step',
      (tester) async {
    final started = DateTime.now().subtract(const Duration(minutes: 5));
    await open(tester,
        value: experiment(status: ExperimentStatus.inProgress, tasks: [
          const ExperimentTask(id: 'first', title: '준비'),
          ExperimentTask(id: 'running', title: '반응', startedAt: started),
          ExperimentTask(id: 'other', title: '동시 반응', startedAt: started),
        ]));
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1);
    expect(find.text('진행 중 2개 단계'), findsOneWidget);
    expect(find.byKey(const ValueKey('focused-task-first')), findsNothing);
    await tapKey(tester, 'focused-task-running');
    await tapKey(tester, 'focused-task-other');
    expect(find.text('다음 단계'), findsOneWidget);
    expect(find.byKey(const ValueKey('focused-task-first')), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '저장'));
    await tester.pumpAndSettle();
    expect(saved.single.tasks[1].startedAt, started);
    expect(saved.single.tasks[1].isCompleted, true);
    expect(saved.single.tasks.first.startedAt, isNull);
  });

  testWidgets(
      'read failure is shown instead of zero and retry loads exact counts',
      (tester) async {
    final p = Plate(id: 'p', experimentId: 'e', name: 'Plate');
    plates.plate = p.copyWith(wells: [
      for (final w in p.wells)
        if (w.label == 'A1')
          w.copyWith(resultValue: 0)
        else if (w.label == 'A2')
          w.copyWith(resultValue: -2, excluded: true)
        else if (w.label == 'A3')
          w.copyWith(excluded: true)
        else
          w
    ]);
    plates.failNextLoad = true;
    await open(tester);
    await section(tester, 'results');
    expect(find.textContaining('측정 현황을 읽지 못했습니다'), findsOneWidget);
    expect(find.textContaining('결과 입력 0'), findsNothing);
    await tester.tap(find.text('현황 다시 불러오기'));
    await tester.pumpAndSettle();
    expect(find.text('결과 입력 2 / 96 well'), findsOneWidget);
    expect(find.text('분석에 포함된 측정값 1개 · 분석 제외 표시 2개'), findsOneWidget);
    expect(saved, isEmpty);
    expect(plates.saveCount, 0);
  });

  testWidgets('completed opens results and analysis read-only without saving',
      (tester) async {
    plates.plate = Plate(id: 'p', experimentId: 'e', name: 'Plate');
    await open(tester, value: experiment(status: ExperimentStatus.completed));
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2);
    expect(find.byKey(const ValueKey('complete-experiment')), findsNothing);
    await tapKey(tester, 'open-result-analysis');
    expect(find.text('분석'), findsOneWidget);
    expect(
        tester
            .widget<PlateEditorScreen>(find.byType(PlateEditorScreen))
            .readOnly,
        true);
    expect(saved, isEmpty);
    expect(plates.saveCount, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await section(tester, 'execution');
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('focused-task-first')))
            .onPressed,
        isNull);
    final notes = find.widgetWithText(TextField, '실행·관찰 메모');
    await reveal(tester, notes);
    expect(tester.widget<TextField>(notes).enabled, false);
  });

  testWidgets(
      'result entry saves draft, starts in result view and refreshes on return',
      (tester) async {
    plates.plate = Plate(id: 'p', experimentId: 'e', name: 'Plate');
    await open(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Assay'), 'Reader assay');
    await section(tester, 'results');
    await tapKey(tester, 'open-result-plate');
    expect(saved.single.title, 'Reader assay');
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('plate-results-view')))
            .selected,
        true);
    // Simulate the repository state produced by a successfully saved import.
    final p = plates.plate!;
    await plates.savePlate(p.copyWith(
        wells: [p.wells.first.copyWith(resultValue: 0), ...p.wells.skip(1)]));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('결과 입력 1 / 96 well'), findsOneWidget);
  });

  testWidgets(
      'save failure prevents result navigation and retains cross-section edits',
      (tester) async {
    var fail = true;
    await open(tester, save: (value) async {
      if (fail) throw StateError('disk full');
      saved.add(value);
    });
    await tester.enterText(
        find.widgetWithText(TextField, 'Assay'), 'Unsaved assay');
    await section(tester, 'results');
    await tapKey(tester, 'open-result-plate');
    expect(find.byType(PlateEditorScreen), findsNothing);
    expect(saved, isEmpty);
    await section(tester, 'design');
    expect(find.widgetWithText(TextField, 'Unsaved assay'), findsOneWidget);
    fail = false;
    await section(tester, 'results');
    await tapKey(tester, 'open-result-plate');
    expect(saved.single.title, 'Unsaved assay');
    expect(find.byType(PlateEditorScreen), findsOneWidget);
  });

  testWidgets(
      'result completion uses review and cancel does not publish completed status',
      (tester) async {
    await open(tester);
    await section(tester, 'results');
    await tapKey(tester, 'complete-experiment');
    expect(find.text('완료 전 점검'), findsOneWidget);
    expect(saved, isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    await section(tester, 'design');
    expect(
        find.byKey(const ValueKey('experiment-status-draft')), findsOneWidget);
    await section(tester, 'results');
    await tapKey(tester, 'complete-experiment');
    final note = find.byKey(const ValueKey('completion-review-note'));
    await reveal(tester, note);
    await tester.enterText(note, 'Plate 미사용, 관찰로 마침');
    tester.testTextInput.hide();
    await tapKey(tester, 'confirm-completion-review');
    expect(saved.single.status, ExperimentStatus.completed);
    expect(saved.single.revisions.single.reason, contains('Plate 미사용, 관찰로 마침'));
    expect(find.byKey(const ValueKey('complete-experiment')), findsNothing);
  });

  testWidgets(
      'save from execution with empty title returns to design validation',
      (tester) async {
    await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Assay'), '');
    await section(tester, 'execution');
    await tester.tap(find.widgetWithText(TextButton, '저장'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0);
    expect(find.text('실험 제목을 입력해주세요.'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('all sections fit at 320px with large text and preserve typing',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, narrow: true);
    await section(tester, 'execution');
    await tapKey(tester, 'focused-task-first');
    final notes = find.widgetWithText(TextField, '실행·관찰 메모');
    await reveal(tester, notes);
    await tester.enterText(notes, '관찰 기록');
    await section(tester, 'results');
    await tapKey(tester, 'complete-experiment');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await section(tester, 'execution');
    await reveal(tester, notes);
    expect(find.text('관찰 기록'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

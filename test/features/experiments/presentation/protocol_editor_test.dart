import 'package:easycheck/app/theme.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/presentation/experiment_detail_screen.dart';
import 'package:easycheck/features/experiments/presentation/widgets/protocol_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/protocol_fixture.dart';

void main() {
  Finder key(String value) => find.byKey(ValueKey(value));
  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.pumpAndSettle();
    if (target.evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(target, 180,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> editor(
      WidgetTester tester, ValueChanged<List<ExperimentTask>?> result,
      {Experiment? source}) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildEasyCheckTheme(),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async => result(
                        await Navigator.push<List<ExperimentTask>>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ProtocolEditorScreen(
                                    experiment:
                                        source ?? protocolExperiment())))),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'renames/reorders/deletes/adds a local draft and retains settings until explicit application',
      (tester) async {
    List<ExperimentTask>? result;
    await editor(tester, (value) => result = value);
    await tester.enterText(key('protocol-title-a'), '시약 준비');
    await tap(tester, key('protocol-down-a'));
    await tap(tester, key('protocol-delete-c'));
    await tap(tester, key('confirm-protocol-delete'));
    await tap(tester, key('protocol-add-task'));
    final input = find.byType(TextField).last;
    await tester.enterText(input, ' 결과 확인 ');
    expect(result, isNull);
    await tap(tester, key('apply-protocol-draft'));
    expect(result!.map((t) => t.title), ['흡광도 측정', '시약 준비', '결과 확인']);
    expect(result!.take(2).map((t) => t.id), ['b', 'a']);
    expect(result![1].plannedMinutes, 10);
    expect(result![1].reminderEnabled, true);
    expect(result!.last.startedAt, isNull);
  });

  testWidgets(
      'dirty close and delete confirmation protect edits; unchanged apply returns no draft',
      (tester) async {
    List<ExperimentTask>? result;
    await editor(tester, (value) => result = value);
    await tester.enterText(key('protocol-title-a'), '변경');
    await tap(tester, key('close-protocol-editor'));
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(key('protocol-title-a')).controller!.text,
        '변경');
    await tap(tester, key('protocol-delete-a'));
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(key('protocol-title-a'), findsOneWidget);
    await tester.enterText(key('protocol-title-a'), '시료 준비');
    await tap(tester, key('apply-protocol-draft'));
    expect(find.byType(ProtocolEditorScreen), findsNothing);
    expect(result, isNull);
  });

  testWidgets(
      'empty name error stays above keyboard and the last stage cannot be deleted',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await editor(tester, (_) {},
        source: protocolExperiment(tasks: [protocolExperiment().tasks.first]));
    expect(
        tester.widget<TextButton>(key('protocol-delete-a')).onPressed, isNull);
    await tester.enterText(key('protocol-title-a'), '  ');
    await tap(tester, key('apply-protocol-draft'));
    final error = find.text('단계 이름을 입력해주세요.');
    expect(error, findsOneWidget);
    expect(tester.getRect(error).bottom, lessThanOrEqualTo(460));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'applied protocol must save before execution; failed notebook save retains other drafts, IDs and order',
      (tester) async {
    final writes = <Experiment>[];
    var fail = true;
    await tester.pumpWidget(MaterialApp(
        theme: buildEasyCheckTheme(),
        home: ExperimentDetailScreen(
            experiment: protocolExperiment(),
            onChanged: (e) async {
              if (fail) {
                fail = false;
                throw StateError('disk');
              }
              writes.add(e);
            })));
    await tester.pumpAndSettle();
    await tap(tester, key('experiment-section-execution'));
    final notes = find.widgetWithText(TextField, '실행·관찰 메모');
    await tap(tester, notes);
    await tester.enterText(notes, '메모 초안 보존');
    await tap(tester, key('edit-protocol-steps'));
    await tester.enterText(key('protocol-title-a'), '준비 수정');
    await tap(tester, key('protocol-down-a'));
    await tap(tester, key('apply-protocol-draft'));
    expect(writes, isEmpty);
    await tester.ensureVisible(key('focused-task-b'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<FilledButton>(key('focused-task-b')).onPressed, isNull);
    await tap(tester, find.widgetWithText(TextButton, '저장'));
    expect(writes, isEmpty);
    await tap(tester, key('retry-save-button'));
    expect(writes.single.tasks.map((t) => t.id), ['b', 'a', 'c']);
    expect(writes.single.tasks[1].title, '준비 수정');
    expect(writes.single.tasks[1].plannedMinutes, 10);
    expect(writes.single.tasks[1].reminderEnabled, true);
    expect(writes.single.notes, '메모 초안 보존');
    await tap(tester, key('focused-task-b'));
    expect(writes.last.tasks.first.startedAt, isNotNull);
    expect(writes.last.tasks[1].title, '준비 수정');
    expect(writes.last.status, ExperimentStatus.inProgress);
    expect(tester.widget<TextButton>(key('edit-protocol-steps')).onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a cancelled prior execution still locks structure even with cleared timestamps',
      (tester) async {
    final task = protocolExperiment()
        .tasks
        .first
        .copyWith(startedAt: DateTime.utc(2026))
        .resetExecution(
            TaskExecutionAction.cancelStart, '오시작', DateTime.utc(2026));
    await editor(tester, (_) {}, source: protocolExperiment(tasks: [task]));
    expect(find.byType(TextField), findsNothing);
    expect(tester.widget<TextButton>(key('apply-protocol-draft')).onPressed,
        isNull);
    expect(find.text('수행 기록이 없는 초안·계획 실험에서만 편집할 수 있습니다.'), findsOneWidget);
  });
}

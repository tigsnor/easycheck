import 'dart:async';
import 'package:easycheck/app/theme.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/presentation/experiment_detail_screen.dart';
import 'package:easycheck/features/experiments/presentation/widgets/experiment_revision_screen.dart';
import 'package:easycheck/features/experiments/presentation/widgets/protocol_change_review_screen.dart';
import 'package:easycheck/features/reminders/application/task_reminder_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/protocol_fixture.dart';
import '../../../support/reminder_fixture.dart';

void main() {
  Finder key(String value) => find.byKey(ValueKey(value));
  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.pumpAndSettle();
    if (target.evaluate().isEmpty) {
      for (var i = 0; i < 3; i++) {
        final p = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        p.jumpTo(p.minScrollExtent);
        await tester.pumpAndSettle();
        if (p.pixels == p.minScrollExtent) break;
      }
      await tester.scrollUntilVisible(target, 160,
          scrollable: find.byType(Scrollable).first);
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'running protocol retry preserves exact audit, execution and reminders; history is read-only',
      (tester) async {
    final base = protocolExperiment(status: ExperimentStatus.inProgress);
    var stored = base.copyWith(tasks: [
      base.tasks.first.copyWith(startedAt: DateTime.now()),
      ...base.tasks.skip(1)
    ]);
    final original = stored;
    final attempts = <Experiment>[];
    var fail = true;
    final os = FakeReminderService();
    final reminders = TaskReminderCoordinator(
        loadExperiments: () async => [stored], service: os);
    addTearDown(reminders.dispose);
    await reminders.refresh();
    final oldAlarm = os.scheduled.single;
    await tester.pumpWidget(MaterialApp(
        theme: buildEasyCheckTheme(),
        home: ExperimentDetailScreen(
            experiment: stored,
            reminders: reminders,
            onChanged: (e) async {
              attempts.add(e);
              if (fail) throw StateError('disk');
              stored = e;
              await reminders.refresh();
            })));
    await tester.pumpAndSettle();
    await tap(tester, key('edit-protocol-steps'));
    expect(
        tester.widget<TextButton>(key('protocol-delete-a')).onPressed, isNull);
    await tester.enterText(key('protocol-title-a'), '시료 준비 수정');
    await tap(tester, key('protocol-down-a'));
    await tap(tester, key('protocol-delete-c'));
    await tap(tester, key('confirm-protocol-delete'));
    await tap(tester, key('apply-protocol-draft'));
    expect(
        tester.widget<FilledButton>(key('focused-task-a')).onPressed, isNull);
    await tap(tester, find.widgetWithText(TextButton, '저장'));
    await tap(tester, key('confirm-protocol-change'));
    expect(find.text('변경 사유를 입력해주세요.'), findsOneWidget);
    expect(attempts, isEmpty);
    await tester.enterText(key('protocol-change-reason'), '실제 SOP 순서와 명칭 확인');
    await tap(tester, key('confirm-protocol-change'));
    expect(stored.toJson(), original.toJson());
    expect(os.entries.values.single, oldAlarm.payload);
    final attemptedRevision = attempts.single.revisions.single.toJson();
    fail = false;
    await tap(tester, key('retry-save-button'));
    expect(attempts, hasLength(2));
    expect(stored.revisions.single.toJson(), attemptedRevision);
    expect(stored.tasks.map((t) => t.id), ['b', 'a']);
    expect(stored.tasks.last.startedAt, original.tasks.first.startedAt);
    expect(stored.tasks.last.plannedMinutes, 10);
    expect(os.scheduled.last.id, oldAlarm.id);
    expect(os.scheduled.last.dueAt, oldAlarm.dueAt);
    expect(os.scheduled.last.body, contains('시료 준비 수정'));
    final revision = stored.revisions.single;
    // Snapshot remains historical even after the current task gets another name.
    stored = stored.copyWith(tasks: [
      stored.tasks.first,
      stored.tasks.last.copyWith(title: '나중 이름')
    ]);
    await tester.pumpWidget(
        MaterialApp(home: ExperimentRevisionScreen(revision: revision)));
    await tester.pumpAndSettle();
    final text =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(text, contains('이름 변경: 시료 준비 → 시료 준비 수정'));
    expect(text, contains('삭제: 정리'));
    expect(text, isNot(contains('나중 이름')));
    expect(attempts, hasLength(2));
  });

  testWidgets(
      'audited save blocks editing, duplicate saves and leaving until persistence completes',
      (tester) async {
    final gate = Completer<void>();
    final writes = <Experiment>[];
    await tester.pumpWidget(MaterialApp(
        home: ExperimentDetailScreen(
            experiment: protocolExperiment(status: ExperimentStatus.inProgress),
            onChanged: (e) async {
              writes.add(e);
              await gate.future;
            })));
    await tester.pumpAndSettle();
    await tap(tester, key('edit-protocol-steps'));
    await tester.enterText(key('protocol-title-a'), '확정 이름');
    await tap(tester, key('apply-protocol-draft'));
    await tap(tester, find.widgetWithText(TextButton, '저장'));
    await tester.enterText(key('protocol-change-reason'), '명칭 정정');
    await tester.tap(key('confirm-protocol-change'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(writes, hasLength(1));
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '저장 중…'))
            .onPressed,
        isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ExperimentDetailScreen), findsOneWidget);
    expect(writes, hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();
    expect(writes.single.revisions.single.reason, '명칭 정정');
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '저장'))
            .onPressed,
        isNotNull);
  });

  testWidgets(
      'small screen keyboard reason stays visible; cancel preserves protocol draft and notes',
      (tester) async {
    final writes = <Experiment>[];
    await tester.pumpWidget(MaterialApp(
        theme: buildEasyCheckTheme(),
        home: ExperimentDetailScreen(
            experiment: protocolExperiment(status: ExperimentStatus.inProgress),
            onChanged: (e) async => writes.add(e))));
    await tester.pumpAndSettle();
    final notes = find.widgetWithText(TextField, '실행·관찰 메모');
    await tap(tester, notes);
    await tester.enterText(notes, '관찰 메모 초안');
    await tap(tester, key('edit-protocol-steps'));
    await tester.enterText(key('protocol-title-a'), '수정 초안');
    await tap(tester, key('apply-protocol-draft'));
    await tap(tester, find.widgetWithText(TextButton, '저장'));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await tap(tester, key('confirm-protocol-change'));
    expect(tester.getRect(find.text('변경 사유를 입력해주세요.')).bottom,
        lessThanOrEqualTo(460));
    await tester.enterText(key('protocol-change-reason'), '취소할 사유');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('사유 버리고 닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(ProtocolChangeReviewScreen), findsNothing);
    expect(writes, isEmpty);
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await tester.pumpAndSettle();
    await tap(tester, notes);
    expect(tester.widget<TextField>(notes).controller!.text, '관찰 메모 초안');
    await tap(tester, find.widgetWithText(TextButton, '저장'));
    await tester.enterText(key('protocol-change-reason'), '순서 정리');
    await tap(tester, key('confirm-protocol-change'));
    expect(writes.single.notes, '관찰 메모 초안');
    expect(writes.single.tasks.first.title, '수정 초안');
    expect(tester.takeException(), isNull);
  });
}

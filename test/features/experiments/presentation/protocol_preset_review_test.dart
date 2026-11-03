import 'package:easycheck/app/theme.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/presentation/experiment_detail_screen.dart';
import 'package:easycheck/features/experiments/presentation/widgets/protocol_change_review_screen.dart';
import 'package:easycheck/features/experiments/presentation/widgets/protocol_preset_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/protocol_fixture.dart';

void main() {
  Finder key(String k) => find.byKey(ValueKey(k));
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      for (var i = 0; i < 3; i++) {
        final p = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        p.jumpTo(p.minScrollExtent);
        await tester.pumpAndSettle();
        if (p.pixels == p.minScrollExtent) break;
      }
      await tester.scrollUntilVisible(finder, 150,
          scrollable: find.byType(Scrollable).first);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String type) async {
    await tap(tester, find.byType(DropdownButtonFormField<String>).first);
    await tester.tap(find.text(type).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'cancelling type selection restores dropdown; keep changes type only after notebook save',
      (tester) async {
    final original = protocolExperiment().copyWith(experimentType: 'CCK-8');
    final writes = <Experiment>[];
    await tester.pumpWidget(MaterialApp(
        home: ExperimentDetailScreen(
            experiment: original, onChanged: (e) async => writes.add(e))));
    await tester.pumpAndSettle();
    await choose(tester, 'MTT');
    expect(
        tester.widget<ChoiceChip>(key('protocol-preset-keep')).selected, true);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('CCK-8'), findsOneWidget);
    expect(find.text('MTT'), findsNothing);
    expect(writes, isEmpty);
    await choose(tester, 'MTT');
    await tap(tester, key('apply-protocol-preset'));
    expect(writes, isEmpty);
    await tap(tester, find.widgetWithText(TextButton, '저장'));
    expect(writes.single.experimentType, 'MTT');
    expect(writes.single.tasks.map((t) => t.toJson()),
        original.tasks.map((t) => t.toJson()));
    expect(find.byType(ProtocolChangeReviewScreen), findsNothing);
  });

  testWidgets(
      'replacement requires explicit choice and retains matching settings',
      (tester) async {
    final original = protocolExperiment();
    final e = original.copyWith(tasks: [
      original.tasks.first.copyWith(title: '세포 seeding'),
      ...original.tasks.skip(1)
    ]);
    final writes = <Experiment>[];
    await tester.pumpWidget(MaterialApp(
        home: ExperimentDetailScreen(
            experiment: e, onChanged: (e) async => writes.add(e))));
    await tester.pumpAndSettle();
    await choose(tester, 'MTT');
    await tap(tester, key('protocol-preset-replace'));
    expect(find.text('추가 7개 · 삭제 2개'), findsOneWidget);
    await tap(tester, key('apply-protocol-preset'));
    await tap(tester, find.widgetWithText(TextButton, '저장'));
    expect(writes.single.tasks, hasLength(8));
    expect(writes.single.tasks.first.toJson(), e.tasks.first.toJson());
    expect(writes.single.tasks.map((t) => t.title), contains('Formazan 용해'));
  });

  testWidgets(
      'in-progress type-only save requires reason and retries same type history',
      (tester) async {
    final original = protocolExperiment(status: ExperimentStatus.inProgress)
        .copyWith(experimentType: 'CCK-8');
    final attempts = <Experiment>[];
    var fail = true;
    await tester.pumpWidget(MaterialApp(
        home: ExperimentDetailScreen(
            experiment: original,
            onChanged: (e) async {
              attempts.add(e);
              if (fail) throw StateError('disk');
            })));
    await tester.pumpAndSettle();
    await tap(tester, key('experiment-section-design'));
    // A draft status downgrade must not bypass the persisted execution policy.
    await tap(tester, find.byType(DropdownButtonFormField<ExperimentStatus>));
    await tester.tap(find.text('계획됨').last);
    await tester.pumpAndSettle();
    await choose(tester, 'MTT');
    expect(tester.widget<ChoiceChip>(key('protocol-preset-replace')).onSelected,
        isNull);
    await tap(tester, key('apply-protocol-preset'));
    await tap(tester, key('experiment-section-execution'));
    expect(
        tester.widget<FilledButton>(key('focused-task-a')).onPressed, isNull);
    await tap(tester, find.widgetWithText(TextButton, '저장'));
    expect(find.text('유형 변경: CCK-8 → MTT'), findsOneWidget);
    await tester.enterText(key('protocol-change-reason'), '실험 분류 정정');
    await tap(tester, key('confirm-protocol-change'));
    final first = attempts.single.revisions.single;
    expect(first.before!.experimentType, 'CCK-8');
    expect(attempts.single.experimentType, 'MTT');
    fail = false;
    await tap(tester, key('retry-save-button'));
    expect(attempts.last.revisions.single.toJson(), first.toJson());
    expect(attempts.last.tasks.map((t) => t.toJson()),
        original.tasks.map((t) => t.toJson()));
  });

  testWidgets(
      'small screen large text append preserves performed stages and all controls remain usable',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final base = protocolExperiment(status: ExperimentStatus.inProgress);
    final e = base.copyWith(tasks: [
      base.tasks.first.copyWith(startedAt: DateTime.utc(2026)),
      ...base.tasks.skip(1)
    ]);
    ProtocolPresetDraft? result;
    await tester.pumpWidget(MaterialApp(
        theme: buildEasyCheckTheme(),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async => result =
                        await Navigator.push<ProtocolPresetDraft>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ProtocolPresetReviewScreen(
                                    experiment: e, targetType: 'MTT'))),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(key('protocol-preset-replace')).onSelected,
        isNull);
    await tap(tester, key('protocol-preset-append'));
    await tap(tester, key('apply-protocol-preset'));
    expect(result!.tasks.take(e.tasks.length).map((t) => t.toJson()),
        e.tasks.map((t) => t.toJson()));
    expect(result!.tasks.length, greaterThan(e.tasks.length));
    expect(tester.takeException(), isNull);
  });
}

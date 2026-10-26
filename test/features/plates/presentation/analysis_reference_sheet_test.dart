import 'dart:async';

import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_reference.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:easycheck/features/plates/presentation/widgets/analysis_reference_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/analysis_reference_fixture.dart';
import '../../../support/fake_document_exchange_service.dart';
import 'plate_editor_screen_test.dart' show FakePlateRepository;

void main() {
  Future<void> open(WidgetTester tester,
      Future<bool> Function(PlateAnalysisReferenceSelection?) save,
      {Plate? plate, double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        isDismissible: false,
                        enableDrag: false,
                        builder: (_) => AnalysisReferenceSheet(
                            plate: plate ?? referencePlate(),
                            groupId: 'a',
                            groupLabel: 'Drug A',
                            resultUnit: 'OD450',
                            onSave: save)),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'filters references, retains failure and prevents duplicate saves/back while saving',
      (tester) async {
    final pending = Completer<bool>();
    var count = 0;
    PlateAnalysisReferenceSelection? saved;
    await open(tester, (selection) {
      saved = selection;
      count++;
      return count == 1 ? pending.future : Future.value(true);
    });
    await tap(tester, 'automatic-references');
    expect(find.byKey(const ValueKey('reference-control-B3')), findsNothing);
    expect(find.byKey(const ValueKey('reference-control-B4')), findsNothing);
    expect(find.byKey(const ValueKey('reference-control-C1')), findsNothing);
    await tap(tester, 'reference-blank-A1');
    await tap(tester, 'reference-control-B1');
    await tap(tester, 'save-analysis-references');
    expect(count, 1);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('save-analysis-references')))
            .onPressed,
        isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AnalysisReferenceSheet), findsOneWidget);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('저장하지 못했습니다'), findsOneWidget);
    expect(saved!.blankWellLabels, ['A1']);
    expect(saved!.controlWellLabels, ['B1']);
    await tap(tester, 'save-analysis-references');
    expect(count, 2);
    expect(find.byType(AnalysisReferenceSheet), findsNothing);
  });

  testWidgets('cancel confirms discarding changes and never persists them',
      (tester) async {
    var count = 0;
    await open(tester, (_) async {
      count++;
      return true;
    });
    await tap(tester, 'automatic-references');
    await tap(tester, 'reference-control-B1');
    await tap(tester, 'close-reference-editor');
    expect(find.text('기준 변경을 버릴까요?'), findsOneWidget);
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('reference-control-B1')))
            .value,
        true);
    await tap(tester, 'close-reference-editor');
    await tester.tap(find.text('변경 버리고 닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(AnalysisReferenceSheet), findsNothing);
    expect(count, 0);
  });

  testWidgets('unavailable stored selections are visible and can be cleared',
      (tester) async {
    final original = referencePlate(manual: true);
    final plate = original.copyWith(wells: [
      for (final w in original.wells)
        w.label == 'B1' ? w.copyWith(excluded: true) : w
    ]);
    PlateAnalysisReferenceSelection? saved;
    await open(tester, (s) async {
      saved = s;
      return true;
    }, plate: plate);
    expect(find.text('B1 · 사용 불가'), findsOneWidget);
    await tap(tester, 'reference-unavailable-control-B1');
    await tap(tester, 'reference-control-B2');
    await tap(tester, 'save-analysis-references');
    expect(saved!.controlWellLabels, ['B2']);
  });

  testWidgets(
      'supports narrow screens, large text and restoring automatic mode',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saved = false;
    await open(tester, (s) async {
      expect(s, isNull);
      saved = true;
      return true;
    }, plate: referencePlate(manual: true), scale: 1.6);
    expect(tester.takeException(), isNull);
    await tap(tester, 'automatic-references');
    await tap(tester, 'save-analysis-references');
    expect(saved, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'saved references refresh analysis/export, record undo history and survive reopening',
      (tester) async {
    final repo = FakePlateRepository()..plate = referencePlate();
    final exchange = FakeDocumentExchangeService();
    await tester.pumpWidget(MaterialApp(
        home: PlateEditorScreen(
            experimentId: 'e',
            repository: repo,
            documentExchangeService: exchange)));
    await tester.pumpAndSettle();
    await tap(tester, 'show-analysis-action');
    await tap(tester, 'edit-reference-a-OD450');
    await tap(tester, 'automatic-references');
    await tap(tester, 'reference-blank-A1');
    await tap(tester, 'reference-control-B1');
    repo.failNextSave = true;
    await tap(tester, 'save-analysis-references');
    expect(repo.plate!.analysisReferences, isEmpty);
    await tap(tester, 'save-analysis-references');
    expect(repo.plate!.analysisReferences.single.toJson(), referenceA.toJson());
    expect(repo.plate!.revisions, hasLength(1));
    expect(repo.plate!.revisions.single.snapshot!.analysisReferences, isEmpty);
    expect(find.text('Control 대비 · 50%'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('share-analysis-file-button')), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-analysis-file-button')));
    await tester.pumpAndSettle();
    expect(exchange.sharedContent, contains('OD450\tmanual\tA1\tB1'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tap(tester, 'show-analysis-action');
    await tap(tester, 'edit-reference-a-OD450');
    expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const ValueKey('automatic-references')))
            .value,
        false);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('reference-control-B1')))
            .value,
        true);
    await tap(tester, 'close-reference-editor');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('마지막 Plate 변경 실행 취소'));
    await tester.pumpAndSettle();
    expect(repo.plate!.analysisReferences, isEmpty);
  });

  testWidgets(
      'analysis and reference controls remain usable at 320px and large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakePlateRepository()..plate = referencePlate(manual: true);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: PlateEditorScreen(experimentId: 'e', repository: repo)));
    await tester.pumpAndSettle();
    await tap(tester, 'show-analysis-action');
    expect(tester.takeException(), isNull);
    await tap(tester, 'edit-reference-a-OD450');
    expect(tester.takeException(), isNull);
    await tap(tester, 'close-reference-editor');
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('share-analysis-file-button')), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('charts keep concentration units separate within the same group',
      (tester) async {
    final original = referencePlate(manual: true);
    final repo = FakePlateRepository()
      ..plate = original.copyWith(wells: [
        for (final w in original.wells)
          w.label == 'C3'
              ? w.copyWith(
                  groupId: 'a',
                  role: WellRole.treatment,
                  concentrationValue: 10,
                  concentrationUnit: 'nM',
                  resultValue: .4,
                  resultUnit: 'OD450')
              : w
      ]);
    await tester.pumpWidget(MaterialApp(
        home: PlateEditorScreen(
            experimentId: 'e', repository: repo, readOnly: true)));
    await tester.pumpAndSettle();
    await tap(tester, 'show-analysis-action');
    expect(find.byKey(const ValueKey('analysis-chart-a-treatment-µM-OD450')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('analysis-chart-a-treatment-nM-OD450')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed experiments show chosen references but cannot edit',
      (tester) async {
    final repo = FakePlateRepository()..plate = referencePlate(manual: true);
    await tester.pumpWidget(MaterialApp(
        home: PlateEditorScreen(
            experimentId: 'e', repository: repo, readOnly: true)));
    await tester.pumpAndSettle();
    await tap(tester, 'show-analysis-action');
    expect(find.byKey(const ValueKey('edit-reference-a-OD450')), findsNothing);
    expect(find.text('수동 기준 · OD450'), findsNWidgets(2));
    expect(repo.saveCount, 0);
  });
}

import 'package:easycheck/features/plates/domain/cell_condition.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_reference.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:easycheck/features/plates/presentation/widgets/analysis_reference_sheet.dart';
import 'package:easycheck/features/plates/presentation/widgets/cell_condition_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/cell_condition_fixture.dart';
import 'plate_editor_screen_test.dart'
    show FakePlateRepository, FakePlateTemplateRepository;

void main() {
  Finder key(String k) => find.byKey(ValueKey(k));
  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.pumpAndSettle();
    if (target.evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Plate empty() => Plate(id: 'p', experimentId: 'e', name: 'Cells');
  Future<FakePlateRepository> open(WidgetTester tester,
      {Plate? plate, bool readOnly = false}) async {
    final repo = FakePlateRepository()..plate = plate ?? empty();
    await tester.pumpWidget(MaterialApp(
        home: PlateEditorScreen(
            experimentId: 'e',
            repository: repo,
            readOnly: readOnly,
            templateRepository: FakePlateTemplateRepository())));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> edit(WidgetTester tester, String position) async {
    await tap(tester, key(position));
    await tap(tester, key('assign-cell-condition-action'));
  }

  Future<void> enter(WidgetTester tester, String name, String density) async {
    await tester.enterText(key('cell-name-input'), name);
    await tester.enterText(key('cell-density-input'), density);
    await tap(tester, key('apply-cell-condition'));
  }

  testWidgets(
      'assigns multiple types and densities to row selections and reuses conditions without changing treatment',
      (tester) async {
    final original = cellPlate().copyWith(wells: [
      for (final w in cellPlate().wells)
        w.copyWith(cellCondition: null, resultValue: null)
    ]);
    final repo = await open(tester, plate: original);
    await edit(tester, 'row-header-A');
    await enter(tester, 'HEK293', '5e3');
    expect(
        repo.plate!.wells.take(12).map((w) => w.cellCondition),
        everyElement(const CellCondition(
            name: 'HEK293', density: 5000, unit: 'cells/mL')));
    expect(repo.plate!.wells.first.concentrationValue, 10);
    expect(repo.plate!.wells.first.groupId, 'drug');
    await edit(tester, 'row-header-B');
    await enter(tester, 'HEK293', '10000');
    await edit(tester, 'row-header-C');
    await enter(tester, 'HeLa', '5000');
    await edit(tester, 'well-D1');
    await tap(
        tester, find.widgetWithText(ActionChip, 'HEK293 · 5000 cells/mL'));
    await tap(tester, key('apply-cell-condition'));
    expect(repo.plate!.wells.where((w) => w.cellCondition != null).length, 37);
    expect(
        repo.plate!.wells.map((w) => w.cellCondition).nonNulls.toSet().length,
        3);
    expect(repo.plate!.wells.first.concentrationValue,
        original.wells.first.concentrationValue);
    await tap(tester, key('plate-cells-view'));
    expect(find.textContaining('C1 · HEK293 · 5000 cells/mL'), findsOneWidget);
    expect(find.textContaining('C3 · HeLa · 5000 cells/mL'), findsOneWidget);
  });

  testWidgets(
      'unit selection is explicit and removing density keeps the type without an invented value',
      (tester) async {
    final repo = await open(tester);
    await edit(tester, 'well-A1');
    await tester.enterText(key('cell-name-input'), 'HeLa');
    await tester.enterText(key('cell-density-input'), '5e3');
    await tap(tester, key('cell-unit-cells/mL'));
    await tap(tester, find.text('cells/well').last);
    await tap(tester, key('apply-cell-condition'));
    expect(repo.plate!.wells.first.cellCondition, hela);
    await tap(tester, key('assign-cell-condition-action'));
    await tester.enterText(key('cell-density-input'), '');
    await tap(tester, key('apply-cell-condition'));
    expect(repo.plate!.wells.first.cellCondition,
        const CellCondition(name: 'HeLa'));
    expect(repo.plate!.wells.first.concentrationValue, isNull);
  });

  testWidgets(
      'single condition opens prefilled, unchanged apply does not write and clear preserves other fields',
      (tester) async {
    final original = empty().copyWith(wells: [
      for (final w in empty().wells)
        w.label == 'A1'
            ? w.copyWith(
                cellCondition: hekLow, concentrationValue: 2, note: 'memo')
            : w
    ]);
    final repo = await open(tester, plate: original);
    await edit(tester, 'well-A1');
    expect(tester.widget<TextField>(key('cell-name-input')).controller!.text,
        'HEK293');
    await tap(tester, key('apply-cell-condition'));
    expect(repo.saveCount, 0);
    await tap(tester, key('assign-cell-condition-action'));
    await tap(tester, key('clear-cell-condition'));
    await tap(tester, find.text('취소'));
    expect(repo.saveCount, 0);
    await tap(tester, key('clear-cell-condition'));
    await tap(tester, find.widgetWithText(FilledButton, '세포 조건 해제'));
    expect(repo.plate!.wells.first.cellCondition, isNull);
    expect(repo.plate!.wells.first.note, 'memo');
    expect(repo.plate!.wells.first.concentrationValue, 2);
    expect(repo.plate!.revisions.single.snapshot!.wells.first.cellCondition,
        hekLow);
  });

  testWidgets('mixed selection is explicit and closing protects edited fields',
      (tester) async {
    final repo = await open(tester, plate: cellPlate());
    await edit(tester, 'row-header-A');
    expect(find.textContaining('서로 다른 세포 조건'), findsOneWidget);
    expect(tester.widget<TextField>(key('cell-name-input')).controller!.text,
        isEmpty);
    await tester.enterText(key('cell-name-input'), 'CHO');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('세포 조건 입력을 버릴까요?'), findsOneWidget);
    await tap(tester, find.text('계속 편집'));
    expect(tester.widget<TextField>(key('cell-name-input')).controller!.text,
        'CHO');
    await tap(tester, key('close-cell-condition'));
    await tap(tester, find.text('입력 버리고 닫기'));
    expect(find.byType(CellConditionSheet), findsNothing);
    expect(repo.saveCount, 0);
    expect(repo.plate!.wells.first.cellCondition, hekLow);
  });

  testWidgets(
      'measured cells require a reason; failed save retries same conditions with original history',
      (tester) async {
    final original = cellPlate().copyWith(wells: [
      for (final w in cellPlate().wells)
        w.label == 'A1' ? w.copyWith(resultValue: 0, excluded: true) : w
    ]);
    final repo = await open(tester, plate: original);
    await edit(tester, 'well-A1');
    await enter(tester, 'CHO', '2000');
    expect(repo.saveCount, 0);
    expect(find.textContaining('변경 전: HEK293'), findsOneWidget);
    await tap(tester, key('confirm-condition-correction'));
    expect(find.text('측정 후 조건을 바꾸는 사유를 입력해주세요.'), findsOneWidget);
    await tester.enterText(key('condition-correction-reason'), '실제 세포 기록 확인');
    repo.failNextSave = true;
    await tap(tester, key('confirm-condition-correction'));
    expect(repo.plate!.toJson(), original.toJson());
    await tap(tester, key('retry-save-button'));
    expect(repo.plate!.wells.first.cellCondition,
        const CellCondition(name: 'CHO', density: 2000, unit: 'cells/well'));
    expect(repo.plate!.wells.first.resultValue, 0);
    expect(repo.plate!.wells.first.excluded, true);
    expect(repo.plate!.revisions.single.summary, contains('실제 세포 기록 확인'));
    expect(repo.plate!.revisions.single.snapshot!.wells.first.cellCondition,
        hekLow);
  });

  testWidgets(
      'read-only plates display cell assignments without offering editing',
      (tester) async {
    final repo = await open(tester, plate: cellPlate(), readOnly: true);
    await tap(tester, key('plate-cells-view'));
    expect(find.textContaining('HEK293 · 10000 cells/well'), findsWidgets);
    await tap(tester, key('well-A1'));
    expect(key('assign-cell-condition-action'), findsNothing);
    expect(repo.saveCount, 0);
  });

  testWidgets(
      'cell reference sheet excludes other types and densities, allows explicit unassigned blank',
      (tester) async {
    PlateAnalysisReferenceSelection? saved;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AnalysisReferenceSheet(
      plate: cellPlate(),
      groupId: 'drug',
      groupLabel: 'Drug',
      resultUnit: 'OD450',
      cellCondition: hekLow,
      onSave: (s) async {
        saved = s;
        return false;
      },
    ))));
    await tester.pumpAndSettle();
    await tap(tester, key('automatic-references'));
    expect(key('reference-control-A6'), findsOneWidget);
    expect(key('reference-control-A7'), findsNothing);
    expect(key('reference-control-A8'), findsNothing);
    expect(key('reference-blank-A9'), findsOneWidget);
    expect(key('reference-blank-A11'), findsNothing);
    await tap(tester, key('reference-control-A6'));
    await tap(tester, key('reference-blank-A9'));
    await tap(tester, key('save-analysis-references'));
    expect(saved!.cellCondition, hekLow);
    expect(saved!.controlWellLabels, ['A6']);
    expect(saved!.blankWellLabels, ['A9']);
  });

  testWidgets(
      'analysis editor saves one cell target without replacing another target',
      (tester) async {
    const high = PlateAnalysisReferenceSelection(
        groupId: 'drug',
        resultUnit: 'OD450',
        cellCondition: hekHigh,
        blankWellLabels: [],
        controlWellLabels: []);
    final repo = FakePlateRepository()
      ..plate = cellPlate().copyWith(analysisReferences: [high]);
    await tester.pumpWidget(MaterialApp(
        home: PlateEditorScreen(
            experimentId: 'e',
            repository: repo,
            templateRepository: FakePlateTemplateRepository(),
            openAnalysisOnLoad: true)));
    await tester.pumpAndSettle();
    await tap(tester, key('edit-reference-drug-OD450-${hekLow.key}'));
    await tap(tester, key('automatic-references'));
    await tap(tester, key('reference-control-A6'));
    await tap(tester, key('reference-blank-A9'));
    await tap(tester, key('save-analysis-references'));
    expect(repo.plate!.analysisReferences.length, 2);
    expect(
        repo.plate!.analysisReferences
            .singleWhere((s) => s.cellCondition == hekHigh)
            .toJson(),
        high.toJson());
    expect(
        repo.plate!.analysisReferences
            .singleWhere((s) => s.cellCondition == hekLow)
            .controlWellLabels,
        ['A6']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '320px large text and keyboard keep validation visible and accept scientific notation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    CellConditionDraft? result;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!),
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                  child: const Text('Open'),
                  onPressed: () async {
                    result = await showModalBottomSheet<CellConditionDraft>(
                        context: context,
                        isScrollControlled: true,
                        isDismissible: false,
                        enableDrag: false,
                        builder: (_) => CellConditionSheet(
                            wells: [empty().wells.first],
                            available: const [hekLow]));
                  }))),
    ));
    await tap(tester, find.text('Open'));
    await tap(tester, key('apply-cell-condition'));
    final error = find.text('세포 종류를 입력해주세요.');
    expect(error, findsOneWidget);
    expect(tester.getBottomRight(error).dy, lessThan(460));
    await tester.enterText(key('cell-name-input'), 'HeLa');
    for (final value in ['-1', 'NaN', 'Infinity', 'abc']) {
      await tester.enterText(key('cell-density-input'), value);
      await tap(tester, key('apply-cell-condition'));
      expect(find.textContaining('0 이상의 숫자'), findsOneWidget);
      expect(tester.getBottomRight(find.textContaining('0 이상의 숫자')).dy,
          lessThan(460));
      expect(result, isNull);
    }
    await enter(tester, 'HeLa', '1.25e5');
    expect(result!.condition,
        const CellCondition(name: 'HeLa', density: 125000, unit: 'cells/mL'));
    expect(tester.takeException(), isNull);
  });
}

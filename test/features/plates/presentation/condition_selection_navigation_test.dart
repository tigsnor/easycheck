import 'package:easycheck/features/plates/application/plate_editor_controller.dart';
import 'package:easycheck/features/plates/domain/assay_condition.dart';
import 'package:easycheck/features/plates/domain/cell_condition.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:easycheck/shared/models/well_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plate_editor_screen_test.dart' show FakePlateRepository;

const cells = CellCondition(name: 'HeLa', density: 1000, unit: 'cells/well');
const medium =
    AssayCondition(medium: 'DMEM', vehicle: 'DMSO', vehiclePercent: .1);
Plate fixture() {
  final base = Plate(id: 'p', experimentId: 'e', name: 'P');
  return base.copyWith(wells: [
    for (final w in base.wells)
      switch (w.label) {
        'A1' || 'A3' || 'D4' => w.copyWith(
            cellCondition: cells,
            assayCondition: medium,
            excluded: w.label == 'D4'),
        'A2' => w.copyWith(
            cellCondition: const CellCondition(
                name: 'HeLa', density: 2000, unit: 'cells/well'),
            assayCondition: medium),
        'A4' => w.copyWith(
            cellCondition: const CellCondition(
                name: 'HeLa', density: 1000, unit: 'cells/mL'),
            assayCondition: const AssayCondition(
                medium: 'DMEM', vehicle: 'DMSO', vehiclePercent: .2)),
        'A5' => w.copyWith(
            cellCondition: const CellCondition(
                name: 'CHO', density: 1000, unit: 'cells/well'),
            assayCondition: const AssayCondition(
                medium: 'RPMI', vehicle: 'DMSO', vehiclePercent: .1)),
        'A6' => w.copyWith(
            assayCondition: const AssayCondition(
                medium: 'DMEM', vehicle: 'ethanol', vehiclePercent: .1)),
        _ => w,
      },
  ]);
}

void main() {
  test(
      'same-condition selection uses all explicit fields independently of other layer',
      () {
    final plate = fixture();
    final before = plate.toJson();
    final controller = PlateEditorController();
    addTearDown(controller.dispose);
    controller.selectWell(WellPosition.fromLabel('A1'));
    controller.selectMatchingCondition(plate);
    expect(
        controller.selectedPositions.map((p) => p.label), ['A1', 'A3', 'D4']);
    expect(controller.selectedPosition!.label, 'A1');
    controller.setView(PlateView.medium);
    controller.selectMatchingCondition(plate);
    expect(controller.selectedPositions.map((p) => p.label),
        ['A1', 'A2', 'A3', 'D4']);
    controller.setView(PlateView.cells);
    expect(
        controller.matchingConditionPositions(plate), isEmpty); // mixed density
    controller.selectWell(WellPosition.fromLabel('H12'));
    controller.selectMatchingCondition(plate);
    expect(
        controller.selectedPositions.single.label, 'H12'); // unknown stays one
    controller.setView(PlateView.results);
    expect(controller.matchingConditionPositions(plate), isEmpty);
    expect(plate.toJson(), before);
  });

  testWidgets(
      'matching scattered wells is view-only and each tab starts with its task',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final original = fixture();
    final repo = FakePlateRepository()..plate = original;
    Finder key(String value) => find.byKey(ValueKey(value));
    Future<void> tap(String value) async {
      await tester.ensureVisible(key(value));
      await tester.pumpAndSettle();
      await tester.tap(key(value));
      await tester.pumpAndSettle();
    }

    String firstAction(String view) {
      final button = find
          .descendant(
              of: key('plate-actions-$view'),
              matching: find.byType(FilledButton))
          .first;
      return tester
          .widget<Text>(
              find.descendant(of: button, matching: find.byType(Text)).first)
          .data!;
    }

    await tester.pumpWidget(MaterialApp(
        home: PlateEditorScreen(experimentId: 'e', repository: repo)));
    await tester.pumpAndSettle();
    expect(firstAction('cells'), '세포 조건');
    await tap('well-A1');
    await tap('select-matching-condition-action');
    expect(find.text('3개 well 선택됨 · A1, A3, D4'), findsOneWidget);
    await tap('plate-medium-view');
    expect(firstAction('medium'), '배지·용매');
    await tap('select-matching-condition-action');
    expect(find.text('4개 well 선택됨 · A1, A2, A3 외 1개'), findsOneWidget);
    await tap('plate-results-view');
    expect(firstAction('results'), '결과 연속 입력');
    expect(key('select-matching-condition-action'), findsNothing);
    expect(repo.saveCount, 0);
    expect(repo.plate!.toJson(), original.toJson());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'same-condition action rejects mixed and unknown seeds and edits only scattered matches',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final original = fixture();
    final repo = FakePlateRepository()..plate = original;
    Finder key(String value) => find.byKey(ValueKey(value));
    Future<void> tap(String value) async {
      await tester.ensureVisible(key(value));
      await tester.pumpAndSettle();
      await tester.tap(key(value));
      await tester.pumpAndSettle();
    }

    FilledButton matchingAction() =>
        tester.widget<FilledButton>(find.descendant(
            of: key('select-matching-condition-action'),
            matching: find.byType(FilledButton)));

    await tester.pumpWidget(MaterialApp(
        home: PlateEditorScreen(experimentId: 'e', repository: repo)));
    await tester.pumpAndSettle();
    expect(matchingAction().onPressed, isNull); // No selection.
    await tap('well-H12');
    expect(matchingAction().onPressed, isNull); // Unrecorded condition.
    await tap('row-header-A');
    expect(matchingAction().onPressed, isNull); // Mixed cell conditions.
    expect(repo.saveCount, 0);

    await tap('well-A1');
    expect(matchingAction().onPressed, isNotNull);
    await tap('select-matching-condition-action');
    await tap('assign-cell-condition-action');
    await tester.enterText(key('cell-name-input'), 'Renamed HeLa');
    await tap('apply-cell-condition');
    expect(repo.saveCount, 1);
    for (var i = 0; i < original.wells.length; i++) {
      final before = original.wells[i];
      final expected = {'A1', 'A3', 'D4'}.contains(before.label)
          ? before.copyWith(
              cellCondition: const CellCondition(
                  name: 'Renamed HeLa', density: 1000, unit: 'cells/well'))
          : before;
      expect(repo.plate!.wells[i].toJson(), expected.toJson(),
          reason:
              'Only the exact selected matches may change: ${before.label}');
    }
    expect(tester.takeException(), isNull);
  });
}

import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/cell_condition.dart';
import 'package:easycheck/features/plates/domain/assay_condition.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:easycheck/features/plates/presentation/widgets/assay_condition_sheet.dart';
import 'package:easycheck/features/plates/presentation/widgets/cell_condition_sheet.dart';
import 'package:easycheck/features/plates/presentation/widgets/condition_edit_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'plate_editor_screen_test.dart' show FakePlateRepository;

void main() {
  Finder key(String name) => find.byKey(ValueKey(name));
  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  test(
      'patches preserve independent values, clear explicitly and reject unknown required conditions',
      () {
    const a = CellCondition(name: 'A', density: 1000, unit: 'cells/well');
    const rename = CellConditionDraft.patch(CellCondition(name: 'New'),
        nameAction: ConditionEditAction.change,
        quantityAction: ConditionEditAction.keep);
    expect(rename.applyTo(a)!.density, 1000);
    const clear = CellConditionDraft.patch(null,
        nameAction: ConditionEditAction.keep,
        quantityAction: ConditionEditAction.clear);
    expect(clear.applyTo(a), const CellCondition(name: 'A'));
    const amount = CellConditionDraft.patch(
        CellCondition(name: '', density: 2, unit: 'cells/well'),
        nameAction: ConditionEditAction.keep,
        quantityAction: ConditionEditAction.change);
    expect(() => amount.applyTo(null), throwsFormatException);
    const medium = AssayConditionDraft.patch(
        AssayCondition(medium: 'New', vehiclePercent: 0),
        mediumAction: ConditionEditAction.change,
        vehicleAction: ConditionEditAction.keep);
    expect(() => medium.applyTo(null), throwsFormatException);
    expect(
        medium.applyTo(const AssayCondition(
            medium: 'Old', vehicle: 'DMSO', vehiclePercent: .2)),
        const AssayCondition(
            medium: 'New', vehicle: 'DMSO', vehiclePercent: .2));
  });
  for (final cells in [true, false]) {
    testWidgets(
        'mixed ${cells ? 'cell' : 'medium'} rename preserves per-well quantities and outside wells',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final base = Plate(id: 'p', experimentId: 'e', name: 'P');
      final original = base.copyWith(wells: [
        for (final w in base.wells)
          w.position.rowIndex == 0
              ? w.copyWith(
                  cellCondition: CellCondition(
                      name: 'Old',
                      density: 1000 + w.position.columnIndex.toDouble(),
                      unit: 'cells/well'),
                  assayCondition: AssayCondition(
                      medium: 'Old',
                      vehicle: 'DMSO',
                      vehiclePercent: .1 + w.position.columnIndex / 100),
                  role: WellRole.treatment,
                  note: 'keep')
              : w
      ]);
      final repo = FakePlateRepository()..plate = original;
      await tester.pumpWidget(MaterialApp(
          home: PlateEditorScreen(experimentId: 'e', repository: repo)));
      await tester.pumpAndSettle();
      await tap(tester, key('row-header-A'));
      final action = key(cells
          ? 'assign-cell-condition-action'
          : 'assign-assay-condition-action');
      await tap(tester, action);
      expect(key(cells ? 'cell-density-input' : 'assay-percent-input'),
          findsNothing);
      await tap(tester,
          key(cells ? 'apply-cell-condition' : 'apply-assay-condition'));
      expect(repo.saveCount, 0); // mixed default keeps every field
      await tap(tester, action);
      await tap(
          tester, key(cells ? 'cell-name-action' : 'assay-medium-action'));
      await tap(tester, find.text('입력값으로 변경').last);
      await tester.enterText(
          key(cells ? 'cell-name-input' : 'assay-medium-input'), 'New');
      await tap(tester,
          key(cells ? 'apply-cell-condition' : 'apply-assay-condition'));
      expect(repo.saveCount, 1);
      for (var i = 0; i < 96; i++) {
        final before = original.wells[i];
        final after = repo.plate!.wells[i];
        if (i >= 12) {
          expect(after.toJson(), before.toJson());
          continue;
        }
        expect(after.note, 'keep');
        if (cells) {
          expect(after.cellCondition!.name, 'New');
          expect(after.cellCondition!.density, before.cellCondition!.density);
          expect(after.assayCondition, before.assayCondition);
        } else {
          expect(after.assayCondition!.medium, 'New');
          expect(after.assayCondition!.vehiclePercent,
              before.assayCondition!.vehiclePercent);
          expect(after.cellCondition, before.cellCondition);
        }
      }
    });
  }

  testWidgets(
      'unknown solvent blocks the entire patch until explicitly set to none',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final base = Plate(id: 'p', experimentId: 'e', name: 'P');
    final original = base.copyWith(wells: [
      base.wells.first.copyWith(
          assayCondition: const AssayCondition(
              medium: 'Old', vehicle: 'DMSO', vehiclePercent: .1),
          cellCondition: const CellCondition(name: 'HeLa'),
          note: 'retain'),
      ...base.wells.skip(1),
    ]);
    final repo = FakePlateRepository()..plate = original;
    await tester.pumpWidget(MaterialApp(
        home: PlateEditorScreen(experimentId: 'e', repository: repo)));
    await tester.pumpAndSettle();
    await tap(tester, key('row-header-A'));
    await tap(tester, key('assign-assay-condition-action'));
    await tap(tester, key('assay-medium-action'));
    await tap(tester, find.text('입력값으로 변경').last);
    await tester.enterText(key('assay-medium-input'), 'Fresh');
    await tap(tester, key('apply-assay-condition'));
    expect(find.textContaining('용매 조건이 미지정인 well'), findsOneWidget);
    expect(repo.saveCount, 0);
    expect(repo.plate!.toJson(), original.toJson());
    await tap(tester, key('assay-vehicle-action'));
    await tap(tester, find.text('용매 없음 (0%)').last);
    expect(key('assay-percent-input'), findsNothing);
    expect(find.text('용매 없음 (0%)으로 기록합니다.'), findsOneWidget);
    await tap(tester, key('apply-assay-condition'));
    expect(repo.saveCount, 1);
    for (var i = 0; i < 96; i++) {
      expect(
          repo.plate!.wells[i].toJson(),
          i < 12
              ? original.wells[i]
                  .copyWith(
                      assayCondition: const AssayCondition(
                          medium: 'Fresh', vehiclePercent: 0))
                  .toJson()
              : original.wells[i].toJson());
    }
  });

  testWidgets('clear cell quantity preserves mixed names and unrecorded wells',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final base = Plate(id: 'p', experimentId: 'e', name: 'P');
    final original = base.copyWith(wells: [
      base.wells[0].copyWith(
          cellCondition: const CellCondition(
              name: 'HeLa', density: 1000, unit: 'cells/well')),
      base.wells[1].copyWith(
          cellCondition: const CellCondition(
              name: 'CHO', density: 10000, unit: 'cells/mL')),
      ...base.wells.skip(2),
    ]);
    final repo = FakePlateRepository()..plate = original;
    await tester.pumpWidget(MaterialApp(
        home: PlateEditorScreen(experimentId: 'e', repository: repo)));
    await tester.pumpAndSettle();
    await tap(tester, key('row-header-A'));
    await tap(tester, key('assign-cell-condition-action'));
    await tap(tester, key('cell-quantity-action'));
    await tap(tester, find.text('수치·단위 해제').last);
    expect(key('cell-density-input'), findsNothing);
    expect(find.textContaining('세포 수치·단위를 해제합니다.'), findsOneWidget);
    await tap(tester, key('apply-cell-condition'));
    expect(repo.saveCount, 1);
    expect(
        repo.plate!.wells[0].cellCondition, const CellCondition(name: 'HeLa'));
    expect(
        repo.plate!.wells[1].cellCondition, const CellCondition(name: 'CHO'));
    expect(repo.plate!.wells.skip(2).map((w) => w.toJson()),
        original.wells.skip(2).map((w) => w.toJson()));
  });
}

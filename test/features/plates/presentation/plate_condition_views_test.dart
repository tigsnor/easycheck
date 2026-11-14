import 'dart:convert';

import 'package:easycheck/app/theme.dart';
import 'package:easycheck/features/plates/domain/assay_condition.dart';
import 'package:easycheck/features/plates/domain/cell_condition.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well_group.dart';
import 'package:easycheck/features/plates/presentation/condition_colors.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:easycheck/features/plates/presentation/widgets/plate_grid.dart';
import 'package:easycheck/shared/presentation/readable_foreground.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/assay_condition_fixture.dart';
import '../../../support/cell_condition_fixture.dart';
import 'plate_editor_screen_test.dart' show FakePlateRepository;

void main() {
  Finder key(String value) => find.byKey(ValueKey(value));
  Future<void> tap(WidgetTester tester, String value) async {
    await tester.ensureVisible(key(value));
    await tester.pumpAndSettle();
    await tester.tap(key(value));
    await tester.pumpAndSettle();
  }

  Color fill(WidgetTester tester, String coordinate) => tester
      .widgetList<Container>(find.descendant(
          of: key('well-$coordinate'), matching: find.byType(Container)))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .first
      .color!;

  Plate sample() {
    final base = assayPlate();
    return base.copyWith(wells: [
      base.wells[0].copyWith(cellCondition: hekLow, assayCondition: dmsoLow),
      base.wells[1].copyWith(cellCondition: hekLow, assayCondition: dmsoHigh),
      base.wells[2].copyWith(cellCondition: hekHigh, assayCondition: dmsoLow),
      base.wells[3].copyWith(cellCondition: null, assayCondition: noVehicle),
      base.wells[4].copyWith(cellCondition: hela, assayCondition: null),
      ...base.wells.skip(5),
    ]);
  }

  Future<void> open(WidgetTester tester, FakePlateRepository repo,
      {bool readOnly = false}) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildEasyCheckTheme(),
        home: PlateEditorScreen(
            experimentId: 'e', repository: repo, readOnly: readOnly)));
    await tester.pumpAndSettle();
  }

  test(
      'condition colors survive serialization and distinguish no vehicle from missing',
      () {
    for (final condition in [hekLow, hekHigh, hela]) {
      expect(ConditionColors.cell(CellCondition.fromJson(condition.toJson())),
          ConditionColors.cell(condition));
    }
    for (final condition in [dmsoLow, dmsoHigh, rpmi, ethanol, noVehicle]) {
      final color = ConditionColors.medium(condition);
      expect(
          ConditionColors.medium(AssayCondition.fromJson(condition.toJson())),
          color);
      final ink = readableForeground(color);
      final a = color.computeLuminance(), b = ink.computeLuminance();
      expect(((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
          greaterThanOrEqualTo(4.5));
    }
    expect(
        [dmsoLow, dmsoHigh, rpmi, ethanol, noVehicle]
            .map(ConditionColors.medium)
            .toSet(),
        hasLength(5));
    expect([hekLow, hekHigh, hela].map(ConditionColors.cell).toSet(),
        hasLength(3));
    expect(
        ConditionColors.medium(const AssayCondition(
            medium: 'DMEM + 10% FBS', vehiclePercent: -0.0)),
        ConditionColors.medium(noVehicle));
    expect(
        ConditionColors.cell(const CellCondition(
            name: 'CHO', density: -0.0, unit: 'cells/well')),
        ConditionColors.cell(
            const CellCondition(name: 'CHO', density: 0, unit: 'cells/well')));
  });

  testWidgets(
      'cells and medium have independent colors, legends and unchanged selection/results',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakePlateRepository()..plate = sample();
    final before = jsonEncode(repo.plate!.toJson());
    await open(tester, repo);
    expect(key('plate-layout-view'), findsNothing);
    expect(tester.widget<ChoiceChip>(key('plate-cells-view')).selected, isTrue);
    expect(fill(tester, 'A1'), fill(tester, 'A2'));
    expect(fill(tester, 'A1'), isNot(fill(tester, 'A3')));
    final cellColor = fill(tester, 'A1');
    await tap(tester, 'row-header-A');
    expect(find.text('12개 well 선택됨 · A1–A12'), findsOneWidget);
    expect(fill(tester, 'A1'), cellColor);
    await tap(tester, 'plate-medium-view');
    expect(fill(tester, 'A1'), fill(tester, 'A3'));
    expect(fill(tester, 'A1'), isNot(fill(tester, 'A2')));
    expect(fill(tester, 'A4'), isNot(fill(tester, 'A5')));
    expect(fill(tester, 'A1'), isNot(cellColor));
    expect(find.text('12개 well 선택됨 · A1–A12'), findsOneWidget);
    await tap(tester, 'plate-medium-legend');
    expect(find.textContaining('M1 · DMEM + 10% FBS · DMSO · 0.1% v/v'),
        findsOneWidget);
    final swatch = tester.widget<Container>(key('legend-M1-color')).decoration!
        as BoxDecoration;
    expect(swatch.color, fill(tester, 'A1'));
    await tap(tester, 'plate-results-view');
    expect(key('plate-results-progress'), findsOneWidget);
    expect(find.text('12개 well 선택됨 · A1–A12'), findsOneWidget);
    await tap(tester, 'plate-cells-view');
    expect(fill(tester, 'A1'), cellColor);
    expect(jsonEncode(repo.plate!.toJson()), before);
    expect(repo.saveCount, 0);
  });

  testWidgets(
      'unrelated group, medium and position edits do not recolor cells and restore preserves both layers',
      (tester) async {
    Plate plate = sample();
    Future<void> render() async {
      await tester.pumpWidget(MaterialApp(
          theme: buildEasyCheckTheme(),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: PlateGrid(
            plate: plate,
            selectedPositions: const {},
            requestedCellSize: null,
            onZoomOut: null,
            onFit: null,
            onZoomIn: null,
            onSelected: (_) {},
            onRangeSelected: (_) {},
            onRectangleSelected: (_, __) {},
            onRowSelected: (_) {},
            onColumnSelected: (_) {},
          )))));
      await tester.pumpAndSettle();
    }

    await render();
    final oldCellColor = fill(tester, 'A1');
    await tap(tester, 'plate-medium-view');
    final oldMediumColor = fill(tester, 'A1');
    plate = plate.copyWith(groups: [
      const WellGroup(
          id: 'drug', name: 'Renamed', shortLabel: 'R', color: Colors.red)
    ], wells: [
      for (final w in plate.wells)
        w.label == 'A2'
            ? w.copyWith(assayCondition: rpmi)
            : w.label == 'H12'
                ? w.copyWith(cellCondition: hekLow, assayCondition: dmsoLow)
                : w,
    ]);
    plate = Plate.fromJson(jsonDecode(jsonEncode(plate.toJson())));
    await render();
    expect(fill(tester, 'A1'), oldMediumColor);
    expect(fill(tester, 'H12'), oldMediumColor);
    await tap(tester, 'plate-cells-view');
    expect(fill(tester, 'A1'), oldCellColor);
    expect(fill(tester, 'H12'), oldCellColor);
  });

  testWidgets(
      'populated cell and medium views keep all 96 wells visible on first fit and remain readable when enlarged',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakePlateRepository()..plate = sample();
    await open(tester, repo);
    for (final view in ['cells', 'medium']) {
      await tap(tester, 'plate-$view-view');
      final viewport = tester.getRect(key('plate-horizontal-scroll'));
      final bottom = tester.getRect(key('plate-context-action-bar')).top;
      for (final w in repo.plate!.wells) {
        final rect = tester.getRect(key('well-${w.label}'));
        expect(rect.left, greaterThanOrEqualTo(viewport.left - .1));
        expect(rect.right, lessThanOrEqualTo(viewport.right + .1));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(bottom));
      }
    }
    await tap(tester, 'plate-zoom-in-button');
    expect(tester.getSize(key('well-A1')).width, closeTo(48, .1));
    expect(find.descendant(of: key('well-A1'), matching: find.text('0.1% v/v')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'read-only large-text views expose condition details without editing or saving',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final repo = FakePlateRepository()..plate = sample();
    await open(tester, repo, readOnly: true);
    await tap(tester, 'plate-medium-view');
    await tap(tester, 'plate-medium-legend');
    expect(find.textContaining('M1 · DMEM + 10% FBS'), findsOneWidget);
    await tap(tester, 'well-A1');
    expect(key('assign-cell-condition-action'), findsNothing);
    expect(key('assign-assay-condition-action'), findsNothing);
    expect(repo.saveCount, 0);
    expect(tester.takeException(), isNull);
    final semantics = tester.ensureSemantics();
    expect(
        find.bySemanticsLabel(
            RegExp('A1 well.*배지 조건 M1.*HEK293.*DMSO.*그룹 Drug.*농도 10')),
        findsOneWidget);
    semantics.dispose();
  });
}

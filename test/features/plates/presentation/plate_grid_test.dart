import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/features/plates/presentation/widgets/plate_grid.dart';
import 'package:easycheck/shared/models/well_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Plate sample() {
    final base = Plate(id: 'p', experimentId: 'e', name: 'Assay');
    return base.copyWith(wells: [
      base.wells[0].copyWith(
          role: WellRole.treatment,
          resultValue: 0,
          resultUnit: 'OD450',
          concentrationValue: 1000),
      base.wells[1].copyWith(role: WellRole.vehicleControl),
      base.wells[2].copyWith(
          role: WellRole.treatment,
          excluded: true,
          resultValue: 0.123456789,
          resultUnit: 'OD450'),
      base.wells[3].copyWith(role: WellRole.blank, excluded: true),
      ...base.wells.skip(4),
    ]);
  }

  Future<void> showGrid(WidgetTester tester,
      {double textScale = 1,
      ValueChanged<WellPosition>? onSelect,
      ValueChanged<WellPosition>? onRangeSelect}) async {
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
          body: SingleChildScrollView(
              child: PlateGrid(
        plate: sample(),
        selectedPositions: const {},
        requestedCellSize: 48,
        onZoomOut: null,
        onFit: () {},
        onZoomIn: () {},
        onSelected: onSelect ?? (_) {},
        onRangeSelected: onRangeSelect ?? (_) {},
        onRectangleSelected: (_, __) {},
        onToggleDragSelection: () {},
        onRowSelected: (_) {},
        onColumnSelected: (_) {},
      ))),
    )));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'distinguishes zero results, missing planned wells and exclusions',
      (tester) async {
    await showGrid(tester);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('well-A1')),
            matching: find.text('1000')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plate-results-view')));
    await tester.pumpAndSettle();
    expect(find.text('입력 2개 · 미입력 1개 · 제외 2개'), findsOneWidget);
    expect(find.text('결과 단위: OD450'), findsOneWidget);
    for (final entry in {
      'A1': '0',
      'A2': '미입력',
      'A3': '0.1235',
      'A4': '제외',
      'A5': '빈 well'
    }.entries) {
      expect(
          find.descendant(
              of: find.byKey(ValueKey('well-${entry.key}')),
              matching: find.text(entry.value)),
          findsOneWidget);
    }
    expect(find.text('A3 ×'), findsOneWidget);
    expect(find.text('A4 ×'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('A3 well.*0.123456789 OD450.*분석 제외')),
        findsOneWidget);
    semantics.dispose();
    await tester.tap(find.byKey(const ValueKey('plate-layout-view')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('well-A1')),
            matching: find.text('1000')),
        findsOneWidget);
  });

  testWidgets('allows screen readers to select a well and start a range',
      (tester) async {
    final semantics = tester.ensureSemantics();
    WellPosition? selected;
    WellPosition? rangeStart;
    await showGrid(tester,
        onSelect: (p) => selected = p, onRangeSelect: (p) => rangeStart = p);
    final node =
        tester.getSemantics(find.bySemanticsLabel(RegExp('A1 well.*')));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(
        node.getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);
    for (final action in [SemanticsAction.tap, SemanticsAction.longPress]) {
      tester.binding.performSemanticsAction(SemanticsActionEvent(
          type: action, nodeId: node.id, viewId: tester.view.viewId));
    }
    expect(selected, const WellPosition(rowIndex: 0, columnIndex: 0));
    expect(rangeStart, const WellPosition(rowIndex: 0, columnIndex: 0));
    semantics.dispose();
  });

  testWidgets(
      'keeps readable touch targets and coordinates on a small screen with large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    WellPosition? selected;
    await showGrid(tester, textScale: 1.6, onSelect: (p) => selected = p);
    final a1 = find.byKey(const ValueKey('well-A1'));
    expect(tester.getSize(a1).width, greaterThanOrEqualTo(48));
    await tester.tap(a1);
    expect(selected, const WellPosition(rowIndex: 0, columnIndex: 0));
    await tester.tap(find.byKey(const ValueKey('plate-results-view')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(a1);
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(a1).dx;
    await tester.dragFrom(tester.getCenter(a1), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(a1).dx, lessThan(before));
    expect(tester.takeException(), isNull);
  });
}

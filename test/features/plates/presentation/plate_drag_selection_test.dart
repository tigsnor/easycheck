import 'dart:ui' show Tristate;

import 'package:easycheck/features/plates/application/plate_editor_controller.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/presentation/widgets/plate_grid.dart';
import 'package:easycheck/shared/models/well_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Finder well(String label) => find.byKey(ValueKey('well-$label'));
  Future<PlateEditorController> showGrid(WidgetTester tester,
      {Size size = const Size(900, 1000),
      double scale = 1,
      bool fit = false}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = PlateEditorController();
    addTearDown(controller.dispose);
    if (fit) controller.fitToScreen();
    final plate = Plate(id: 'p', experimentId: 'e', name: 'Plate');
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
          body: SingleChildScrollView(
        child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => PlateGrid(
                  plate: plate,
                  selectedPositions: controller.selectedPositions,
                  requestedCellSize: controller.requestedCellSize,
                  onZoomOut: controller.zoomOut,
                  onZoomIn: controller.zoomIn,
                  onFit: controller.fitToScreen,
                  onSelected: controller.selectWell,
                  onRangeSelected: controller.selectRangeTo,
                  onRectangleSelected: controller.selectRectangle,
                  dragSelectionEnabled: controller.dragSelectionEnabled,
                  onToggleDragSelection: controller.toggleDragSelection,
                  onRowSelected: (r) => controller.selectRow(r, 12),
                  onColumnSelected: (c) => controller.selectColumn(c, 8),
                )),
      )),
    )));
    await tester.pumpAndSettle();
    return controller;
  }

  for (final direct in [false, true]) {
    testWidgets(
        'drag updates and shrinks a rectangle from a fixed anchor, direct=$direct',
        (tester) async {
      final controller = await showGrid(tester);
      // A previous selection must not become the new gesture's anchor.
      controller.selectWell(WellPosition.fromLabel('D5'));
      if (direct) {
        await tester.tap(find.byKey(const ValueKey('plate-drag-selection')));
      }
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(well('A1')));
      if (!direct) await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(tester.getCenter(well('C3')));
      await tester.pump();
      expect(controller.selectedPositions, hasLength(9));
      expect(
          controller.selectedPositions, contains(WellPosition.fromLabel('A1')));
      final node = tester.ensureSemantics();
      expect(
          tester
              .getSemantics(well('B2'))
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue);
      node.dispose();
      await gesture.moveTo(tester.getCenter(well('B2')));
      await tester.pump();
      expect(controller.selectedPositions, hasLength(4));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.selectedPositions, hasLength(4));
      final reverse = await tester.startGesture(tester.getCenter(well('C3')));
      if (!direct) await tester.pump(const Duration(milliseconds: 600));
      await reverse.moveTo(tester.getCenter(well('A1')));
      await tester.pump();
      expect(controller.selectedPositions, hasLength(9));
      await reverse.up();
      await tester.pumpAndSettle();
      await tester.tap(well('D1'));
      await tester.pumpAndSettle();
      expect(controller.selectedPositions, {WellPosition.fromLabel('D1')});
    });
  }

  testWidgets(
      'quick swipes scroll without selecting and offset drag maps to correct wells',
      (tester) async {
    final controller = await showGrid(tester, size: const Size(320, 500));
    final before = tester.getTopLeft(well('A1')).dx;
    await tester.dragFrom(tester.getCenter(well('A2')), const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(well('A1')).dx, lessThan(before));
    expect(controller.selectedPositions, isEmpty);
    final top = tester.getTopLeft(well('A3')).dy;
    await tester.dragFrom(tester.getCenter(well('A3')), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(well('A3')).dy, lessThan(top));
    expect(controller.selectedPositions, isEmpty);
    Scrollable.of(tester.element(find.byType(PlateGrid)), axis: Axis.vertical)
        .position
        .jumpTo(0);
    final scroll = tester
        .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('plate-horizontal-scroll')))
        .controller!;
    scroll.jumpTo(200);
    controller.toggleDragSelection();
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(well('A5')));
    await gesture.moveTo(tester.getCenter(well('B7')));
    await tester.pump();
    expect(controller.selectedPositions, hasLength(6));
    expect(
        controller.selectedPositions, contains(WellPosition.fromLabel('A5')));
    expect(
        controller.selectedPositions, contains(WellPosition.fromLabel('B7')));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'edge scrolling reaches H12 and pointer cancellation stops scrolling',
      (tester) async {
    final controller = await showGrid(tester, size: const Size(320, 500));
    controller.toggleDragSelection();
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(well('A1')));
    await gesture.moveTo(const Offset(310, 490));
    for (var i = 0; i < 65; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(controller.selectedPositions, hasLength(96));
    expect(controller.selectedPosition, WellPosition.fromLabel('H12'));
    await gesture.cancel();
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(well('A1'));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(well('A1')), before);
    expect(tester.takeException(), isNull);
  });

  for (final fit in [false, true]) {
    testWidgets('drag respects scaled and fitted cell coordinates, fit=$fit',
        (tester) async {
      final controller = await showGrid(tester, scale: 1.6, fit: fit);
      controller.toggleDragSelection();
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(well('B2')));
      await gesture.moveTo(tester.getCenter(well('C4')));
      await tester.pump();
      expect(controller.selectedPositions, hasLength(6));
      expect(
          controller.selectedPositions, contains(WellPosition.fromLabel('B2')));
      expect(controller.selectedPosition, WellPosition.fromLabel('C4'));
      await gesture.up();
      await tester.pumpAndSettle();
    });
  }

  testWidgets('disposing during an active drag cancels its scroll timer',
      (tester) async {
    await showGrid(tester);
    final gesture = await tester.startGesture(tester.getCenter(well('A1')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await gesture.cancel();
    expect(tester.takeException(), isNull);
  });
}

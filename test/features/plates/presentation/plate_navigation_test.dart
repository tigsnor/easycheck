import 'package:easycheck/features/plates/application/plate_editor_controller.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/presentation/widgets/plate_grid.dart';
import 'package:easycheck/shared/models/well_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Finder key(String name) => find.byKey(ValueKey(name));
  Future<PlateEditorController> open(WidgetTester tester,
      {bool fit = false, double scale = 1}) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = PlateEditorController();
    addTearDown(controller.dispose);
    if (!fit) controller.zoomIn();
    final plate = Plate(id: 'p', experimentId: 'e', name: 'P');
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
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
                                onRowSelected: (r) =>
                                    controller.selectRow(r, 12),
                                onColumnSelected: (c) =>
                                    controller.selectColumn(c, 8)))))))));
    await tester.pumpAndSettle();
    return controller;
  }

  ScrollController scroll(WidgetTester tester, String axis) => tester
      .widget<SingleChildScrollView>(key('plate-$axis-scroll'))
      .controller!;

  for (final fit in [false, true]) {
    testWidgets('coordinate navigation selects and reveals H12, fit=$fit',
        (tester) async {
      final controller = await open(tester, fit: fit, scale: 1.6);
      controller.selectRectangle(
          WellPosition.fromLabel('A1'), WellPosition.fromLabel('B2'));
      await tester.pumpAndSettle();
      await tester.tap(key('plate-coordinate-action'));
      await tester.pumpAndSettle();
      await tester.enterText(key('plate-coordinate-input'), ' h12 ');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(controller.selectedPositions, {WellPosition.fromLabel('H12')});
      expect(controller.requestedCellSize, fit ? null : 48);
      expect(key('well-H12').hitTestable(), findsOneWidget);
      expect(key('column-header-12').hitTestable(), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invalid or cancelled coordinates preserve existing selection',
      (tester) async {
    final controller = await open(tester);
    controller.selectWell(WellPosition.fromLabel('C4'));
    await tester.pumpAndSettle();
    await tester.tap(key('plate-coordinate-action'));
    await tester.pumpAndSettle();
    for (final invalid in ['', 'A0', 'A13', 'I1', 'A+1', 'A01']) {
      await tester.enterText(key('plate-coordinate-input'), invalid);
      await tester.tap(key('plate-coordinate-go'));
      await tester.pumpAndSettle();
      expect(find.textContaining('A1~H12 범위'), findsOneWidget);
      expect(controller.selectedPositions, {WellPosition.fromLabel('C4')});
    }
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(controller.selectedPositions, {WellPosition.fromLabel('C4')});
    expect(tester.takeException(), isNull);
  });

  testWidgets('headers stay fixed on their axes and remain aligned/selectable',
      (tester) async {
    final controller = await open(tester);
    final rowLeft = tester.getTopLeft(key('row-header-A')).dx;
    final columnTop = tester.getTopLeft(key('column-header-1')).dy;
    final before = tester.getTopLeft(key('well-A1'));
    scroll(tester, 'horizontal').jumpTo(180);
    scroll(tester, 'vertical').jumpTo(100);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(key('row-header-A')).dx, rowLeft);
    expect(tester.getTopLeft(key('column-header-1')).dy, columnTop);
    expect(tester.getTopLeft(key('well-A1')), before - const Offset(180, 100));
    expect(tester.getTopLeft(key('row-header-D')).dy,
        tester.getTopLeft(key('well-D5')).dy);
    expect(tester.getTopLeft(key('column-header-5')).dx,
        tester.getTopLeft(key('well-D5')).dx);
    await tester.tap(key('row-header-D'));
    await tester.pumpAndSettle();
    expect(controller.selectedPositions, hasLength(12));
    expect(controller.selectedPositions.every((p) => p.rowLabel == 'D'), true);
    await tester.tap(key('column-header-5'));
    await tester.pumpAndSettle();
    expect(controller.selectedPositions, hasLength(8));
    expect(
        controller.selectedPositions.every((p) => p.columnNumber == 5), true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning to fit resets offsets and keeps all headers aligned',
      (tester) async {
    final controller = await open(tester);
    scroll(tester, 'horizontal').jumpTo(180);
    scroll(tester, 'vertical').jumpTo(100);
    await tester.pumpAndSettle();
    controller.fitToScreen();
    await tester.pumpAndSettle();
    expect(scroll(tester, 'horizontal').offset, 0);
    expect(scroll(tester, 'vertical').offset, 0);
    expect(tester.getTopLeft(key('column-header-1')).dx,
        tester.getTopLeft(key('well-A1')).dx);
    expect(tester.getTopLeft(key('row-header-A')).dy,
        tester.getTopLeft(key('well-A1')).dy);
    expect(key('well-A1').hitTestable(), findsOneWidget);
    expect(key('well-H12').hitTestable(), findsOneWidget);
    expect(key('column-header-12').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('body swipes and offset drag preserve fixed-header hit mapping',
      (tester) async {
    final controller = await open(tester);
    final columnTop = tester.getTopLeft(key('column-header-1')).dy;
    await tester.drag(key('well-B2'), const Offset(0, -90));
    await tester.pumpAndSettle();
    expect(scroll(tester, 'vertical').offset, greaterThan(0));
    expect(tester.getTopLeft(key('column-header-1')).dy, columnTop);
    expect(controller.selectedPositions, isEmpty);
    scroll(tester, 'horizontal').jumpTo(180);
    scroll(tester, 'vertical').jumpTo(100);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(key('well-D5')));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(key('well-F7')));
    await tester.pump();
    expect(controller.selectedPositions, hasLength(9));
    expect(
        controller.selectedPositions, contains(WellPosition.fromLabel('D5')));
    expect(controller.selectedPosition, WellPosition.fromLabel('F7'));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

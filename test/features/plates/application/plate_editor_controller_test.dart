import 'package:easycheck/features/plates/application/plate_editor_controller.dart';
import 'package:easycheck/shared/models/well_position.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlateEditorController', () {
    test('selects wells, rows, columns, and rectangular ranges', () {
      final controller = PlateEditorController();
      addTearDown(controller.dispose);

      controller.selectWell(
        const WellPosition(rowIndex: 1, columnIndex: 1),
      );
      expect(controller.selectedPositions, hasLength(1));

      controller.startRange();
      controller.selectWell(
        const WellPosition(rowIndex: 2, columnIndex: 3),
      );
      expect(controller.selectedPositions, hasLength(6));
      expect(controller.rangeAnchor, isNull);

      controller.selectRow(0, 12);
      expect(controller.selectedPositions, hasLength(12));

      controller.selectColumn(2, 8);
      expect(controller.selectedPositions, hasLength(8));
      expect(
        controller.selectedPosition,
        const WellPosition(rowIndex: 0, columnIndex: 2),
      );

      controller.clearSelection();
      expect(controller.selectedPositions, isEmpty);
      expect(controller.selectedPosition, isNull);
    });

    test('manages fit and bounded zoom state', () {
      final controller = PlateEditorController();
      addTearDown(controller.dispose);

      expect(controller.requestedCellSize, isNull);
      expect(controller.canZoomOut, isFalse);
      controller.zoomIn();
      expect(controller.requestedCellSize, 40);
      expect(controller.canZoomOut, isTrue);

      for (var index = 0; index < 10; index++) {
        controller.zoomIn();
      }
      expect(controller.requestedCellSize, 64);
      expect(controller.canZoomIn, isFalse);

      controller.fitToScreen();
      expect(controller.requestedCellSize, isNull);
    });

    test('notifies listeners for meaningful interaction changes', () {
      final controller = PlateEditorController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.clearSelection();
      expect(notifications, 0);
      controller.selectWell(
        const WellPosition(rowIndex: 0, columnIndex: 0),
      );
      controller.zoomIn();
      controller.fitToScreen();
      controller.clearSelection();

      expect(notifications, 4);
    });
  });
}

import 'package:flutter/foundation.dart';

import '../../../shared/models/well_position.dart';

/// Owns transient Plate-editor interaction state independently from widgets.
///
/// Persistence and domain mutations intentionally remain outside this class;
/// this first state-management boundary covers selection and viewport state.
class PlateEditorController extends ChangeNotifier {
  WellPosition? get selectedPosition => _selectedPosition;
  WellPosition? _selectedPosition;

  Set<WellPosition> get selectedPositions => _selectedPositions;
  Set<WellPosition> _selectedPositions = const {};

  WellPosition? get rangeAnchor => _rangeAnchor;
  WellPosition? _rangeAnchor;

  double? get requestedCellSize => _requestedCellSize;
  double? _requestedCellSize;

  bool get canZoomOut => _requestedCellSize != null && _requestedCellSize! > 32;
  bool get canZoomIn => _requestedCellSize == null || _requestedCellSize! < 64;

  void zoomOut() {
    final current = _requestedCellSize ?? 32;
    _requestedCellSize = (current - 8).clamp(32, 64).toDouble();
    notifyListeners();
  }

  void zoomIn() {
    final current = _requestedCellSize ?? 32;
    _requestedCellSize = (current + 8).clamp(32, 64).toDouble();
    notifyListeners();
  }

  void fitToScreen() {
    if (_requestedCellSize == null) return;
    _requestedCellSize = null;
    notifyListeners();
  }

  void selectWell(WellPosition position) {
    _selectedPosition = position;
    final anchor = _rangeAnchor;
    _selectedPositions =
        anchor == null ? {position} : _rectangle(anchor, position).toSet();
    _rangeAnchor = null;
    notifyListeners();
  }

  void selectRangeTo(WellPosition position) {
    final anchor = _selectedPosition ?? _rangeAnchor ?? position;
    _selectedPosition = position;
    _selectedPositions = _rectangle(anchor, position).toSet();
    _rangeAnchor = null;
    notifyListeners();
  }

  void selectRow(int rowIndex, int columnCount) {
    _selectedPosition = WellPosition(rowIndex: rowIndex, columnIndex: 0);
    _selectedPositions = {
      for (var column = 0; column < columnCount; column++)
        WellPosition(rowIndex: rowIndex, columnIndex: column),
    };
    _rangeAnchor = null;
    notifyListeners();
  }

  void selectColumn(int columnIndex, int rowCount) {
    _selectedPosition = WellPosition(rowIndex: 0, columnIndex: columnIndex);
    _selectedPositions = {
      for (var row = 0; row < rowCount; row++)
        WellPosition(rowIndex: row, columnIndex: columnIndex),
    };
    _rangeAnchor = null;
    notifyListeners();
  }

  void startRange() {
    final selected = _selectedPosition;
    if (selected == null) return;
    _rangeAnchor = selected;
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedPosition == null && _selectedPositions.isEmpty) return;
    _selectedPosition = null;
    _selectedPositions = const {};
    _rangeAnchor = null;
    notifyListeners();
  }

  Iterable<WellPosition> _rectangle(
    WellPosition start,
    WellPosition end,
  ) sync* {
    final rowStart =
        start.rowIndex < end.rowIndex ? start.rowIndex : end.rowIndex;
    final rowEnd =
        start.rowIndex > end.rowIndex ? start.rowIndex : end.rowIndex;
    final columnStart = start.columnIndex < end.columnIndex
        ? start.columnIndex
        : end.columnIndex;
    final columnEnd = start.columnIndex > end.columnIndex
        ? start.columnIndex
        : end.columnIndex;

    for (var row = rowStart; row <= rowEnd; row++) {
      for (var column = columnStart; column <= columnEnd; column++) {
        yield WellPosition(rowIndex: row, columnIndex: column);
      }
    }
  }
}

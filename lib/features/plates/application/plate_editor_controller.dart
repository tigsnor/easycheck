import 'package:flutter/foundation.dart';

import '../../../shared/models/well_position.dart';
import '../domain/plate.dart';

enum PlateView { cells, medium, results }

/// Owns transient Plate-editor interaction state independently from widgets.
///
/// Persistence and domain mutations intentionally remain outside this class;
/// this first state-management boundary covers selection and viewport state.
class PlateEditorController extends ChangeNotifier {
  PlateEditorController({PlateView initialView = PlateView.cells})
      : _view = initialView;

  PlateView get view => _view;
  PlateView _view;

  void setView(PlateView view) {
    if (_view == view) return;
    _view = view;
    notifyListeners();
  }

  WellPosition? get selectedPosition => _selectedPosition;
  WellPosition? _selectedPosition;

  Set<WellPosition> get selectedPositions => _selectedPositions;
  Set<WellPosition> _selectedPositions = const {};

  WellPosition? get rangeAnchor => _rangeAnchor;
  WellPosition? _rangeAnchor;

  bool get dragSelectionEnabled => _dragSelectionEnabled;
  bool _dragSelectionEnabled = false;

  void toggleDragSelection() {
    _dragSelectionEnabled = !_dragSelectionEnabled;
    _rangeAnchor = null;
    notifyListeners();
  }

  void selectRectangle(WellPosition start, WellPosition end) {
    _selectedPosition = end;
    _selectedPositions = _rectangle(start, end).toSet();
    _rangeAnchor = null;
    notifyListeners();
  }

  double? get requestedCellSize => _requestedCellSize;
  // Open with every well visible across the screen; zoom is an explicit choice.
  double? _requestedCellSize;

  bool get canZoomOut => _requestedCellSize != null && _requestedCellSize! > 48;
  bool get canZoomIn => _requestedCellSize == null || _requestedCellSize! < 80;

  void zoomOut() {
    final current = _requestedCellSize ?? 56;
    _requestedCellSize = (current - 8).clamp(48, 80).toDouble();
    notifyListeners();
  }

  void zoomIn() {
    final current = _requestedCellSize ?? 40;
    _requestedCellSize = (current + 8).clamp(48, 80).toDouble();
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

  /// Only a single explicit condition may seed a condition selection. Unknown
  /// conditions and mixed selections never silently expand to unrelated wells.
  Set<WellPosition> matchingConditionPositions(Plate plate) {
    if (_view == PlateView.results || _selectedPositions.isEmpty) return {};
    final selected = plate.wells
        .where((w) => _selectedPositions.contains(w.position))
        .toList();
    if (selected.length != _selectedPositions.length) return {};
    final condition = _view == PlateView.cells
        ? selected.first.cellCondition
        : selected.first.assayCondition;
    if (condition == null ||
        selected.any((w) =>
            (_view == PlateView.cells ? w.cellCondition : w.assayCondition) !=
            condition)) {
      return {};
    }
    return {
      for (final well in plate.wells)
        if ((_view == PlateView.cells
                ? well.cellCondition
                : well.assayCondition) ==
            condition)
          well.position,
    };
  }

  void selectMatchingCondition(Plate plate) {
    final positions = matchingConditionPositions(plate);
    if (positions.isEmpty) return;
    _selectedPositions = Set.unmodifiable(positions);
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
    if (_selectedPosition == null &&
        _selectedPositions.isEmpty &&
        !_dragSelectionEnabled) {
      return;
    }
    _selectedPosition = null;
    _selectedPositions = const {};
    _rangeAnchor = null;
    _dragSelectionEnabled = false;
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

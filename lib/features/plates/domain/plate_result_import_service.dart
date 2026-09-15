import '../../../shared/models/well_position.dart';
import 'plate.dart';

class PlateResultImportIssue {
  const PlateResultImportIssue({
    required this.rowNumber,
    required this.columnNumber,
    required this.value,
    required this.message,
  });

  final int rowNumber;
  final int columnNumber;
  final String value;
  final String message;
}

class PlateResultImportPreview {
  const PlateResultImportPreview({
    required this.values,
    required this.issues,
    required this.detectedRowCount,
    required this.detectedColumnCount,
  });

  final Map<WellPosition, double> values;
  final List<PlateResultImportIssue> issues;
  final int detectedRowCount;
  final int detectedColumnCount;

  bool get canApply => values.isNotEmpty && issues.isEmpty;
  int get valueCount => values.length;
}

class PlateResultImportService {
  const PlateResultImportService();

  PlateResultImportPreview parseMatrix({
    required String text,
    int rowCount = 8,
    int columnCount = 12,
  }) {
    final rawLines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (rawLines.isEmpty) {
      return const PlateResultImportPreview(
        values: {},
        issues: [],
        detectedRowCount: 0,
        detectedColumnCount: 0,
      );
    }

    final delimiter = rawLines.any((line) => line.contains('\t'))
        ? '\t'
        : rawLines.any((line) => line.contains(','))
            ? ','
            : null;
    var rows = rawLines.map((line) => _split(line, delimiter)).toList();

    if (_isColumnHeader(rows.first, columnCount)) {
      rows = rows.skip(1).toList();
    }

    final values = <WellPosition, double>{};
    final issues = <PlateResultImportIssue>[];
    var detectedColumnCount = 0;

    for (var sourceRow = 0; sourceRow < rows.length; sourceRow++) {
      final originalCells = rows[sourceRow];
      final hasRowLabel =
          originalCells.isNotEmpty && _rowIndex(originalCells.first) != null;
      final targetRow =
          hasRowLabel ? _rowIndex(originalCells.first)! : sourceRow;
      final cells =
          hasRowLabel ? originalCells.skip(1).toList() : originalCells;
      detectedColumnCount = detectedColumnCount < cells.length
          ? cells.length
          : detectedColumnCount;

      if (targetRow >= rowCount) {
        issues.add(
          PlateResultImportIssue(
            rowNumber: sourceRow + 1,
            columnNumber: 1,
            value: originalCells.isEmpty ? '' : originalCells.first,
            message: 'Plate 범위를 벗어난 행입니다.',
          ),
        );
        continue;
      }

      for (var column = 0; column < cells.length; column++) {
        final raw = cells[column].trim();
        if (raw.isEmpty) {
          continue;
        }
        if (column >= columnCount) {
          issues.add(
            PlateResultImportIssue(
              rowNumber: sourceRow + 1,
              columnNumber: column + 1,
              value: raw,
              message: 'Plate 범위를 벗어난 열입니다.',
            ),
          );
          continue;
        }
        final value = double.tryParse(raw);
        if (value == null || !value.isFinite) {
          issues.add(
            PlateResultImportIssue(
              rowNumber: sourceRow + 1,
              columnNumber: column + 1,
              value: raw,
              message: '숫자로 읽을 수 없습니다.',
            ),
          );
          continue;
        }
        values[WellPosition(rowIndex: targetRow, columnIndex: column)] = value;
      }
    }

    return PlateResultImportPreview(
      values: values,
      issues: issues,
      detectedRowCount: rows.length,
      detectedColumnCount: detectedColumnCount,
    );
  }

  Plate apply({
    required Plate plate,
    required PlateResultImportPreview preview,
    required String resultUnit,
  }) {
    if (!preview.canApply) {
      throw ArgumentError('오류가 없는 결과 미리보기만 적용할 수 있습니다.');
    }
    final normalizedUnit = resultUnit.trim();
    return plate.copyWith(
      wells: [
        for (final well in plate.wells)
          if (preview.values.containsKey(well.position))
            well.copyWith(
              resultValue: preview.values[well.position],
              resultUnit: normalizedUnit.isEmpty ? null : normalizedUnit,
            )
          else
            well,
      ],
    );
  }

  List<String> _split(String line, String? delimiter) {
    if (delimiter != null) {
      return line.split(delimiter);
    }
    return line.trim().split(RegExp(r'\s+'));
  }

  bool _isColumnHeader(List<String> cells, int columnCount) {
    if (cells.isEmpty) {
      return false;
    }
    final normalized = cells.map((cell) => cell.trim()).toList();
    final candidates =
        normalized.first.isEmpty || normalized.first.toLowerCase() == 'well'
            ? normalized.skip(1).toList()
            : normalized;
    if (candidates.isEmpty || candidates.length > columnCount) {
      return false;
    }
    for (var index = 0; index < candidates.length; index++) {
      if (int.tryParse(candidates[index]) != index + 1) {
        return false;
      }
    }
    return true;
  }

  int? _rowIndex(String value) {
    final normalized = value.trim().toUpperCase();
    if (normalized.length != 1) {
      return null;
    }
    final index = normalized.codeUnitAt(0) - 'A'.codeUnitAt(0);
    return index >= 0 ? index : null;
  }
}

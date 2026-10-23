import '../../../shared/models/well_position.dart';
import 'plate.dart';
import 'well.dart';

enum MatrixHeaderMode { automatic, present, absent }

enum ResultImportChange { added, overwritten, identical, untouched }

class ResultImportComparisonEntry {
  const ResultImportComparisonEntry(
      {required this.before, required this.after, required this.change});

  final Well before;
  final Well after;
  final ResultImportChange change;
  bool get changesResult =>
      change == ResultImportChange.added ||
      change == ResultImportChange.overwritten;
  String get label => switch (change) {
        ResultImportChange.added => '신규',
        ResultImportChange.overwritten => '덮어쓰기',
        ResultImportChange.identical => '동일',
        ResultImportChange.untouched => '유지',
      };
}

class PlateResultImportComparison {
  PlateResultImportComparison(List<ResultImportComparisonEntry> entries)
      : entries = List.unmodifiable(entries);

  final List<ResultImportComparisonEntry> entries;
  int count(ResultImportChange change) =>
      entries.where((entry) => entry.change == change).length;
  String get summary =>
      '신규 ${count(ResultImportChange.added)}개 · 덮어쓰기 ${count(ResultImportChange.overwritten)}개 · 동일 ${count(ResultImportChange.identical)}개 · 유지 ${count(ResultImportChange.untouched)}개';
}

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

  /// Build the review from the same transformation used by the actual import.
  /// Invalid or ambiguous input must be corrected before comparing results.
  PlateResultImportComparison compare({
    required Plate plate,
    required PlateResultImportPreview preview,
    required String resultUnit,
  }) {
    final applied =
        apply(plate: plate, preview: preview, resultUnit: resultUnit);
    final entries = <ResultImportComparisonEntry>[];
    for (var row = 0; row < plate.rowCount; row++) {
      for (var column = 0; column < plate.columnCount; column++) {
        final position = WellPosition(rowIndex: row, columnIndex: column);
        final before = plate.wellAt(position);
        final after = applied.wellAt(position);
        final change = !preview.values.containsKey(position)
            ? ResultImportChange.untouched
            : before.resultValue == null
                ? ResultImportChange.added
                : before.resultValue == after.resultValue &&
                        before.resultUnit == after.resultUnit
                    ? ResultImportChange.identical
                    : ResultImportChange.overwritten;
        entries.add(ResultImportComparisonEntry(
            before: before, after: after, change: change));
      }
    }
    return PlateResultImportComparison(entries);
  }

  PlateResultImportPreview parseMatrix({
    required String text,
    int rowCount = 8,
    int columnCount = 12,
    MatrixHeaderMode headerMode = MatrixHeaderMode.automatic,
  }) {
    final rawLines = text
        .replaceFirst(RegExp(r'^\uFEFF'), '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .toList();
    // Interior (and leading) blank rows carry coordinates in an unlabeled
    // matrix. Only trailing empty lines can be safely ignored.
    while (rawLines.isNotEmpty && rawLines.last.trim().isEmpty) {
      rawLines.removeLast();
    }
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
    final issues = <PlateResultImportIssue>[];
    final firstCell = rows.first.first.trim().toLowerCase();
    final isHeader = _isColumnHeader(rows.first, columnCount);
    final explicitHeader =
        isHeader && (firstCell.isEmpty || firstCell == 'well');

    if (headerMode == MatrixHeaderMode.present ||
        (headerMode == MatrixHeaderMode.automatic && explicitHeader)) {
      if (!isHeader) {
        issues.add(const PlateResultImportIssue(
          rowNumber: 1,
          columnNumber: 1,
          value: '',
          message: '열 제목은 1부터 순서대로 지정해야 합니다.',
        ));
      }
      rows = rows.skip(1).toList();
    } else if (headerMode == MatrixHeaderMode.automatic && isHeader) {
      issues.add(const PlateResultImportIssue(
        rowNumber: 1,
        columnNumber: 1,
        value: '',
        message: '첫 행이 측정값인지 열 제목인지 선택해주세요.',
      ));
    }

    final values = <WellPosition, double>{};
    final seenRows = <int>{};
    final nonemptyRows =
        rows.where((row) => row.any((cell) => cell.trim().isNotEmpty));
    final labeledCount =
        nonemptyRows.where((row) => _rowIndex(row.first) != null).length;
    if (labeledCount > 0 && labeledCount != nonemptyRows.length) {
      issues.add(const PlateResultImportIssue(
        rowNumber: 1,
        columnNumber: 1,
        value: '',
        message: '행 좌표가 있는 행과 없는 행을 함께 사용할 수 없습니다.',
      ));
    }
    var detectedColumnCount = 0;

    for (var sourceRow = 0; sourceRow < rows.length; sourceRow++) {
      final originalCells = rows[sourceRow];
      if (labeledCount > 0 &&
          originalCells.every((cell) => cell.trim().isEmpty)) {
        continue;
      }
      final hasRowLabel =
          originalCells.isNotEmpty && _rowIndex(originalCells.first) != null;
      final targetRow =
          hasRowLabel ? _rowIndex(originalCells.first)! : sourceRow;
      if (!seenRows.add(targetRow)) {
        issues.add(PlateResultImportIssue(
          rowNumber: sourceRow + 1,
          columnNumber: 1,
          value: originalCells.first,
          message: '같은 행 좌표가 두 번 나타납니다.',
        ));
        continue;
      }
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
    if (!RegExp(r'^[A-Z]$').hasMatch(normalized)) {
      return null;
    }
    final index = normalized.codeUnitAt(0) - 'A'.codeUnitAt(0);
    return index >= 0 ? index : null;
  }
}

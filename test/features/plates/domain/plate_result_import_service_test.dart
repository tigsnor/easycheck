import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_result_import_service.dart';
import 'package:easycheck/shared/models/well_position.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = PlateResultImportService();

  test('parses an Excel-style matrix with row and column headers', () {
    const text = '\t1\t2\t3\nA\t0.1\t0.2\t0.3\nB\t1.1\t1.2\t1.3';

    final preview = service.parseMatrix(text: text);

    expect(preview.canApply, isTrue);
    expect(preview.valueCount, 6);
    expect(
      preview.values[const WellPosition(rowIndex: 0, columnIndex: 1)],
      0.2,
    );
    expect(
      preview.values[const WellPosition(rowIndex: 1, columnIndex: 2)],
      1.3,
    );
  });

  test('rejects duplicate and mixed row coordinates', () {
    for (final text in ['A\t0.1\nA\t0.9', 'A\t0.1\n0.9']) {
      expect(service.parseMatrix(text: text).canApply, isFalse);
    }
  });

  test('preserves leading and interior blank rows in unlabeled matrices', () {
    final preview = service.parseMatrix(text: '\t\n0.1\t0.2\n\t\n0.3\t0.4\n');
    expect(preview.canApply, isTrue);
    expect(
        preview.values[const WellPosition(rowIndex: 1, columnIndex: 0)], 0.1);
    expect(
        preview.values[const WellPosition(rowIndex: 3, columnIndex: 0)], 0.3);
    expect(preview.valueCount, 4);
  });

  test('requires an explicit choice for a numeric first row', () {
    const text = '1\t2\t3\n4\t5\t6';
    final automatic = service.parseMatrix(text: text);
    expect(automatic.canApply, isFalse);
    expect(automatic.valueCount, 6);
    final data =
        service.parseMatrix(text: text, headerMode: MatrixHeaderMode.absent);
    expect(data.canApply, isTrue);
    expect(data.valueCount, 6);
    final header =
        service.parseMatrix(text: text, headerMode: MatrixHeaderMode.present);
    expect(header.canApply, isTrue);
    expect(header.valueCount, 3);
    expect(header.values[const WellPosition(rowIndex: 0, columnIndex: 0)], 4);
  });

  test('rejects an invalid explicitly selected column header', () {
    expect(
        service
            .parseMatrix(
                text: '1\t3\n0.1\t0.2', headerMode: MatrixHeaderMode.present)
            .canApply,
        isFalse);
  });

  test('accepts a UTF-8 BOM before an explicit header', () {
    expect(service.parseMatrix(text: '\uFEFF\t1\t2\nA\t0.1\t0.2').canApply,
        isTrue);
  });

  test('reports invalid values and cells outside a 96-well plate', () {
    final tooManyColumns = List.generate(
      13,
      (index) => '${index + 1}',
    ).join('\t');
    final preview = service.parseMatrix(text: 'A\tbad\t$tooManyColumns');

    expect(preview.canApply, isFalse);
    expect(preview.issues, isNotEmpty);
    expect(
      preview.issues.map((issue) => issue.message),
      contains('숫자로 읽을 수 없습니다.'),
    );
    expect(
      preview.issues.map((issue) => issue.message),
      contains('Plate 범위를 벗어난 열입니다.'),
    );
  });

  test('applies imported values without changing unlisted wells', () {
    final plate = Plate(
      id: 'plate-1',
      experimentId: 'experiment-1',
      name: '96-well Plate',
    );
    final preview = service.parseMatrix(text: '0.8\t0.9');

    final updated = service.apply(
      plate: plate,
      preview: preview,
      resultUnit: 'OD450',
    );

    expect(updated.wells[0].resultValue, 0.8);
    expect(updated.wells[0].resultUnit, 'OD450');
    expect(updated.wells[1].resultValue, 0.9);
    expect(updated.wells[2].resultValue, isNull);
  });
}

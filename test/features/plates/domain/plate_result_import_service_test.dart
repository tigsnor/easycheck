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

  test('reports invalid values and cells outside a 96-well plate', () {
    final tooManyColumns =
        List.generate(13, (index) => '${index + 1}').join('\t');
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

import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/features/plates/templates/domain/plate_template.dart';
import 'package:easycheck/shared/models/well_position.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps setup fields but removes measured results', () {
    final plate = Plate(
      id: 'plate-source',
      experimentId: 'experiment-source',
      name: 'Source plate',
      wells: [
        const Well(
          position: WellPosition(rowIndex: 0, columnIndex: 0),
          role: WellRole.treatment,
          concentrationValue: 10,
          volumeValue: 100,
          note: 'Add reagent last',
          resultValue: 1.25,
          resultUnit: 'OD',
          excluded: true,
        ),
      ],
    );

    final template = PlateTemplate.fromPlate(
      id: 'template-1',
      name: 'CCK-8 template',
      plate: plate,
      createdAt: DateTime.utc(2026, 6, 12),
    );
    final instantiated = template.instantiate(
      plateId: 'plate-target',
      experimentId: 'experiment-target',
    );
    final well = instantiated.wells.single;

    expect(instantiated.id, 'plate-target');
    expect(instantiated.experimentId, 'experiment-target');
    expect(well.concentrationValue, 10);
    expect(well.volumeValue, 100);
    expect(well.note, 'Add reagent last');
    expect(well.resultValue, isNull);
    expect(well.resultUnit, isNull);
    expect(well.excluded, isFalse);
  });
}

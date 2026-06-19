import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_export_service.dart';
import 'package:easycheck/features/plates/domain/well_group.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/shared/models/well_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = PlateExportService();

  test('builds a TSV export with group summary and well rows', () {
    final plate = Plate(
      id: 'plate-1',
      experimentId: 'experiment-1',
      name: '96-well Plate',
      groups: const [
        WellGroup(
          id: 'drug-a',
          name: 'Drug A',
          shortLabel: 'A',
          color: Color(0xFFE6D9FF),
          role: WellRole.treatment,
          concentrationUnit: 'µM',
        ),
      ],
    );
    final updatedWells = plate.wells.map((well) {
      if (well.position == const WellPosition(rowIndex: 0, columnIndex: 0)) {
        return well.copyWith(
          groupId: 'drug-a',
          role: WellRole.treatment,
          concentrationValue: 100,
          concentrationUnit: 'µM',
          replicateIndex: 1,
          resultValue: 0.82,
          resultUnit: 'OD450',
          note: '기포 확인',
          excluded: true,
        );
      }
      return well;
    }).toList();
    final export = service.buildTsv(plate.copyWith(wells: updatedWells));

    expect(export, contains('PlateNote plate export'));
    expect(export, contains('group_id\tname\tlabel\trole\tunit\twell_count'));
    expect(export, contains('drug-a\tDrug A\tA\ttreatment\tµM\t1\t100 µM'));
    expect(
      export,
      contains(
        'A1\tA\t1\tDrug A\ttreatment\t100\tµM\t1\t\tµL\t0.82\tOD450\ttrue\t기포 확인',
      ),
    );
  });
}

import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well.dart';
import 'package:easycheck/features/plates/domain/well_group.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:flutter/material.dart';

Plate measuredPlate() {
  final base = Plate(id: 'p', experimentId: 'e', name: 'Measured');
  return base.copyWith(
    groups: const [
      WellGroup(id: 'g', name: 'Drug A', shortLabel: 'A', color: Colors.blue)
    ],
    wells: [
      for (final well in base.wells)
        well.label == 'A1'
            ? well.copyWith(
                groupId: 'g',
                role: WellRole.treatment,
                concentrationValue: 2,
                concentrationUnit: 'µM',
                volumeValue: 100,
                replicateIndex: 1,
                resultValue: 0,
                resultUnit: 'OD450')
            : well
    ],
  );
}

Plate replaceWell(Plate plate, String label, Well Function(Well) change) =>
    plate.copyWith(wells: [
      for (final well in plate.wells) well.label == label ? change(well) : well
    ]);

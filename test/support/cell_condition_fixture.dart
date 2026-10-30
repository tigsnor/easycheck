import 'package:easycheck/features/plates/domain/cell_condition.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/features/plates/domain/well_group.dart';
import 'package:flutter/material.dart';

const hekLow = CellCondition(name: 'HEK293', density: 5000, unit: 'cells/well');
const hekHigh =
    CellCondition(name: 'HEK293', density: 10000, unit: 'cells/well');
const hela = CellCondition(name: 'HeLa', density: 5000, unit: 'cells/well');

Plate cellPlate() {
  final plate =
      Plate(id: 'p', experimentId: 'e', name: 'Cell comparison', groups: [
    const WellGroup(
        id: 'drug',
        name: 'Drug',
        shortLabel: 'D',
        color: Colors.blue,
        concentrationUnit: 'µM'),
  ]);
  final conditions = [
    hekLow,
    hekLow,
    hekHigh,
    hela,
    null,
    hekLow,
    hekHigh,
    hela,
    null,
    hekLow,
    hekHigh,
    hela
  ];
  final results = [0.6, 0.8, 1.4, 2.2, 0.5, 1.0, 2.0, 4.0, 0.2, 0.1, 0.2, 0.4];
  return plate.copyWith(wells: [
    for (final well in plate.wells)
      well.position.rowIndex == 0
          ? well.copyWith(
              groupId: 'drug',
              role: well.position.columnIndex < 5
                  ? WellRole.treatment
                  : well.position.columnIndex < 8
                      ? WellRole.untreatedControl
                      : WellRole.blank,
              concentrationValue: well.position.columnIndex < 5 ? 10 : null,
              concentrationUnit: 'µM',
              cellCondition: conditions[well.position.columnIndex],
              resultValue: results[well.position.columnIndex],
              resultUnit: 'OD450',
            )
          : well,
  ]);
}

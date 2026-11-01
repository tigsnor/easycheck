import 'package:easycheck/features/plates/domain/assay_condition.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well_group.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:flutter/material.dart';
import 'cell_condition_fixture.dart';

const dmsoLow = AssayCondition(
    medium: 'DMEM + 10% FBS', vehicle: 'DMSO', vehiclePercent: 0.1);
const dmsoHigh = AssayCondition(
    medium: 'DMEM + 10% FBS', vehicle: 'DMSO', vehiclePercent: 0.2);
const rpmi =
    AssayCondition(medium: 'RPMI', vehicle: 'DMSO', vehiclePercent: 0.1);
const ethanol = AssayCondition(
    medium: 'DMEM + 10% FBS', vehicle: 'ethanol', vehiclePercent: 0.1);
const noVehicle = AssayCondition(medium: 'DMEM + 10% FBS', vehiclePercent: 0);
Plate assayPlate() {
  final p =
      Plate(id: 'p', experimentId: 'e', name: 'Conditions', groups: const [
    WellGroup(
        id: 'drug',
        name: 'Drug',
        shortLabel: 'D',
        color: Colors.blue,
        concentrationUnit: 'µM')
  ]);
  const conditions = [dmsoLow, dmsoHigh, rpmi, ethanol, null, noVehicle];
  const treatment = [0.6, 1.4, 2.2, 0.9, 0.5, 1.1];
  const controls = [1.0, 2.0, 4.0, 1.5, 0.9, 2.0];
  const blanks = [0.1, 0.2, 0.4, 0.1, 0.1, 0.2];
  return p.copyWith(wells: [
    for (final w in p.wells)
      if (w.position.rowIndex < 6 && [0, 2, 3].contains(w.position.columnIndex))
        w.copyWith(
            groupId: 'drug',
            role: w.position.columnIndex == 0
                ? WellRole.treatment
                : w.position.columnIndex == 2
                    ? WellRole.vehicleControl
                    : WellRole.blank,
            concentrationValue: w.position.columnIndex == 0 ? 10 : null,
            concentrationUnit: 'µM',
            cellCondition: w.position.rowIndex == 4 ? null : hekLow,
            assayCondition: conditions[w.position.rowIndex],
            resultUnit: 'OD450',
            resultValue: (w.position.columnIndex == 0
                ? treatment
                : w.position.columnIndex == 2
                    ? controls
                    : blanks)[w.position.rowIndex])
      else if (w.label == 'A2')
        w.copyWith(
            groupId: 'drug',
            role: WellRole.treatment,
            concentrationValue: 10,
            concentrationUnit: 'µM',
            cellCondition: hekLow,
            assayCondition: dmsoLow,
            resultValue: 0.8,
            resultUnit: 'OD450')
      else if (w.label == 'A5')
        w.copyWith(
            role: WellRole.blank,
            assayCondition: dmsoLow,
            resultValue: 0.2,
            resultUnit: 'OD450')
      else
        w,
  ]);
}

import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_reference.dart';
import 'package:easycheck/features/plates/domain/well_group.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:flutter/material.dart';

const referenceA = PlateAnalysisReferenceSelection(
    groupId: 'a',
    resultUnit: 'OD450',
    blankWellLabels: ['A1'],
    controlWellLabels: ['B1']);
const referenceB = PlateAnalysisReferenceSelection(
    groupId: 'b',
    resultUnit: 'OD450',
    blankWellLabels: ['A2'],
    controlWellLabels: ['B2']);

Plate referencePlate({bool manual = false}) {
  final plate = Plate(
      id: 'p',
      experimentId: 'e',
      name: 'References',
      groups: const [
        WellGroup(
            id: 'a', name: 'Drug A', shortLabel: 'A', color: Colors.purple),
        WellGroup(id: 'b', name: 'Drug B', shortLabel: 'B', color: Colors.blue),
      ],
      analysisReferences: manual ? [referenceA, referenceB] : []);
  return plate.copyWith(wells: [
    for (final w in plate.wells)
      switch (w.label) {
        'A1' => w.copyWith(
            role: WellRole.blank, resultValue: .1, resultUnit: 'OD450'),
        'A2' => w.copyWith(
            role: WellRole.blank, resultValue: .2, resultUnit: 'OD450'),
        'B1' => w.copyWith(
            role: WellRole.vehicleControl,
            resultValue: 1.1,
            resultUnit: 'OD450'),
        'B2' => w.copyWith(
            role: WellRole.vehicleControl,
            resultValue: 2.2,
            resultUnit: 'OD450'),
        'B3' => w.copyWith(
            role: WellRole.untreatedControl,
            resultValue: 99,
            resultUnit: 'OD450',
            excluded: true),
        'B4' => w.copyWith(
            role: WellRole.vehicleControl, resultValue: 4, resultUnit: 'RFU'),
        'C1' => w.copyWith(
            groupId: 'a',
            role: WellRole.treatment,
            concentrationValue: 10,
            resultValue: .6,
            resultUnit: 'OD450'),
        'C2' => w.copyWith(
            groupId: 'b',
            role: WellRole.treatment,
            concentrationValue: 10,
            resultValue: 1.2,
            resultUnit: 'OD450'),
        _ => w,
      }
  ]);
}

import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_service.dart';
import 'package:easycheck/features/plates/domain/well.dart';
import 'package:easycheck/features/plates/domain/well_group.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/shared/models/well_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = PlateAnalysisService();
  const treatment = WellGroup(
    id: 'drug-a',
    name: 'Drug A',
    shortLabel: 'A',
    color: Colors.purple,
  );

  test('calculates blank correction, sample SD, CV, and normalization', () {
    final plate = _plateWithWells(
      [
        _well('A1', 0.1, role: WellRole.blank),
        _well('A2', 0.2, role: WellRole.blank),
        _well('B1', 1.0, role: WellRole.vehicleControl),
        _well('B2', 1.1, role: WellRole.vehicleControl),
        _well('C1', 0.6, groupId: treatment.id, concentration: 100),
        _well('C2', 0.8, groupId: treatment.id, concentration: 100),
      ],
      groups: const [treatment],
    );

    final report = service.analyze(plate);
    final series = report.series.singleWhere(
      (item) => item.label == 'Drug A' && item.concentrationValue == 100,
    );

    expect(report.blankMeanByUnit['OD450'], closeTo(0.15, 0.000001));
    expect(report.controlByUnit['OD450']?.role, WellRole.vehicleControl);
    expect(
      report.controlByUnit['OD450']?.correctedMean,
      closeTo(0.9, 0.000001),
    );
    expect(series.rawMean, closeTo(0.7, 0.000001));
    expect(series.blankCorrectedMean, closeTo(0.55, 0.000001));
    expect(series.standardDeviation, closeTo(0.141421, 0.000001));
    expect(series.coefficientOfVariation, closeTo(20.20305, 0.00001));
    expect(series.normalizedPercent, closeTo(61.11111, 0.00001));
    expect(series.replicateCount, 2);
  });

  test('excludes flagged wells and reports their labels', () {
    final plate = _plateWithWells(
      [
        _well('C1', 0.5, groupId: treatment.id, concentration: 10),
        _well(
          'C2',
          100,
          groupId: treatment.id,
          concentration: 10,
          excluded: true,
        ),
      ],
      groups: const [treatment],
    );

    final report = service.analyze(plate);
    final series = report.series.single;

    expect(report.measuredWellCount, 2);
    expect(report.includedWellCount, 1);
    expect(report.excludedWellCount, 1);
    expect(series.rawMean, 0.5);
    expect(series.includedWellLabels, ['C1']);
    expect(series.excludedWellLabels, ['C2']);
    expect(series.standardDeviation, isNull);
  });

  test('does not mix result units or different concentrations', () {
    final plate = _plateWithWells(
      [
        _well('C1', 1, groupId: treatment.id, concentration: 100),
        _well('C2', 2, groupId: treatment.id, concentration: 10),
        _well(
          'C3',
          3,
          groupId: treatment.id,
          concentration: 100,
          resultUnit: 'RFU',
        ),
      ],
      groups: const [treatment],
    );

    final report = service.analyze(plate);

    expect(report.series, hasLength(3));
    expect(
      report.series.map((item) => item.resultUnit),
      containsAll(['OD450', 'RFU']),
    );
  });
}

Plate _plateWithWells(
  List<Well> replacements, {
  List<WellGroup> groups = const [],
}) {
  final plate = Plate(
    id: 'plate-1',
    experimentId: 'experiment-1',
    name: '96-well Plate',
    groups: groups,
  );
  final byPosition = {for (final well in replacements) well.position: well};
  return plate.copyWith(
    wells: [for (final well in plate.wells) byPosition[well.position] ?? well],
  );
}

Well _well(
  String label,
  double result, {
  String? groupId,
  WellRole role = WellRole.treatment,
  double? concentration,
  String resultUnit = 'OD450',
  bool excluded = false,
}) {
  return Well(
    position: WellPosition(
      rowIndex: label.codeUnitAt(0) - 'A'.codeUnitAt(0),
      columnIndex: int.parse(label.substring(1)) - 1,
    ),
    groupId: groupId,
    role: role,
    concentrationValue: concentration,
    concentrationUnit: concentration == null ? null : 'µM',
    resultValue: result,
    resultUnit: resultUnit,
    excluded: excluded,
  );
}

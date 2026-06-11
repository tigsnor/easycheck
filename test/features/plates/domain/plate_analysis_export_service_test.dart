import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_export_service.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_service.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = PlateAnalysisExportService();

  test('exports references and analysis series as TSV', () {
    final plate = Plate(
      id: 'plate-1',
      experimentId: 'experiment-1',
      name: 'CCK-8\tPlate',
    );
    const report = PlateAnalysisReport(
      measuredWellCount: 4,
      includedWellCount: 3,
      excludedWellCount: 1,
      blankMeanByUnit: {'OD450': 0.1},
      controlByUnit: {
        'OD450': PlateAnalysisControl(
          role: WellRole.vehicleControl,
          rawMean: 1.1,
          correctedMean: 1,
          wellCount: 1,
        ),
      },
      series: [
        PlateAnalysisSeries(
          label: 'Drug A',
          role: WellRole.treatment,
          concentrationValue: 100,
          concentrationUnit: 'µM',
          resultUnit: 'OD450',
          includedWellLabels: ['B1', 'B2'],
          excludedWellLabels: ['B3'],
          rawMean: 0.7,
          blankCorrectedMean: 0.6,
          standardDeviation: 0.141421,
          coefficientOfVariation: 20.203,
          normalizedPercent: 60,
        ),
      ],
    );

    final tsv = service.buildTsv(plate, report);

    expect(tsv, contains('EasyCheck analysis export'));
    expect(tsv, contains('Plate\tCCK-8 Plate'));
    expect(tsv, contains('OD450\t0.1\tvehicleControl\t1.1\t1\t1'));
    expect(
      tsv,
      contains(
        'Drug A\ttreatment\t100\tµM\tOD450\t2\tB1, B2\t1\tB3\t0.7\t0.6\t0.141421\t20.203\t60',
      ),
    );
  });

  test('leaves unavailable statistics empty', () {
    final plate = Plate(
      id: 'plate-1',
      experimentId: 'experiment-1',
      name: 'Plate',
    );
    const report = PlateAnalysisReport(
      measuredWellCount: 1,
      includedWellCount: 1,
      excludedWellCount: 0,
      blankMeanByUnit: {},
      controlByUnit: {},
      series: [
        PlateAnalysisSeries(
          label: 'Drug A',
          role: WellRole.treatment,
          concentrationValue: 10,
          concentrationUnit: 'µM',
          resultUnit: 'RFU',
          includedWellLabels: ['A1'],
          excludedWellLabels: [],
          rawMean: 2,
          blankCorrectedMean: 2,
          standardDeviation: null,
          coefficientOfVariation: null,
          normalizedPercent: null,
        ),
      ],
    );

    final lines = service.buildTsv(plate, report).split('\n');
    final seriesRow = lines[lines.length - 2].split('\t');

    expect(seriesRow.sublist(seriesRow.length - 5), ['2', '2', '', '', '']);
  });
}

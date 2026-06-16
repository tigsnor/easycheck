import 'plate.dart';
import 'plate_analysis_service.dart';

class PlateAnalysisExportService {
  const PlateAnalysisExportService();

  String buildTsv(Plate plate, PlateAnalysisReport report) {
    final buffer = StringBuffer()
      ..writeln('EasyCheck analysis export')
      ..writeln('Plate\t${_escape(plate.name)}')
      ..writeln('Experiment ID\t${_escape(plate.experimentId)}')
      ..writeln('Measured wells\t${report.measuredWellCount}')
      ..writeln('Included wells\t${report.includedWellCount}')
      ..writeln('Excluded wells\t${report.excludedWellCount}')
      ..writeln()
      ..writeln('References')
      ..writeln(
        'result_unit\tblank_mean\tcontrol_role\tcontrol_raw_mean\tcontrol_corrected_mean\tcontrol_well_count',
      );

    final referenceUnits = {
      ...report.blankMeanByUnit.keys,
      ...report.controlByUnit.keys,
    }.toList()
      ..sort();
    for (final unit in referenceUnits) {
      final control = report.controlByUnit[unit];
      buffer.writeln(
        [
          unit,
          _numberOrEmpty(report.blankMeanByUnit[unit]),
          control?.role.name ?? '',
          _numberOrEmpty(control?.rawMean),
          _numberOrEmpty(control?.correctedMean),
          control?.wellCount.toString() ?? '',
        ].map((value) => _escape(value.toString())).join('\t'),
      );
    }

    buffer
      ..writeln()
      ..writeln('Series')
      ..writeln(
        'group\trole\tconcentration\tconcentration_unit\tresult_unit\treplicates\tincluded_wells\texcluded_count\texcluded_wells\traw_mean\tblank_corrected_mean\tsample_sd\tcv_percent\tnormalized_percent',
      );
    for (final series in report.series) {
      buffer.writeln(
        [
          series.label,
          series.role.name,
          _numberOrEmpty(series.concentrationValue),
          series.concentrationUnit ?? '',
          series.resultUnit,
          series.replicateCount.toString(),
          series.includedWellLabels.join(', '),
          series.excludedCount.toString(),
          series.excludedWellLabels.join(', '),
          _numberOrEmpty(series.rawMean),
          _numberOrEmpty(series.blankCorrectedMean),
          _numberOrEmpty(series.standardDeviation),
          _numberOrEmpty(series.coefficientOfVariation),
          _numberOrEmpty(series.normalizedPercent),
        ].map((value) => _escape(value.toString())).join('\t'),
      );
    }
    return buffer.toString();
  }

  String _numberOrEmpty(double? value) {
    if (value == null) {
      return '';
    }
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _escape(String value) {
    return value.replaceAll('\t', ' ').replaceAll('\n', ' ').trim();
  }
}

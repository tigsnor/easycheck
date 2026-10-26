import 'plate.dart';
import 'plate_analysis_service.dart';

class PlateAnalysisExportService {
  const PlateAnalysisExportService();

  String buildTsv(Plate plate, PlateAnalysisReport report) {
    final buffer = StringBuffer()
      ..writeln('PlateNote analysis export')
      ..writeln('Plate\t${_escape(plate.name)}')
      ..writeln('Experiment ID\t${_escape(plate.experimentId)}')
      ..writeln('Measured wells\t${report.measuredWellCount}')
      ..writeln('Included wells\t${report.includedWellCount}')
      ..writeln('Excluded wells\t${report.excludedWellCount}')
      ..writeln()
      ..writeln('Automatic references (used only for series in automatic mode)')
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
      ..writeln('Applied references by series')
      ..writeln(
          'group_id\tgroup\trole\tconcentration\tconcentration_unit\tresult_unit\tmode\tblank_wells\tcontrol_wells\tblank_mean\tcontrol_raw_mean\tcontrol_corrected_mean\twarnings');
    for (final series in report.series) {
      final ref = series.reference;
      if (ref == null) continue;
      buffer.writeln([
        series.groupId ?? '',
        series.label,
        series.role.name,
        _numberOrEmpty(series.concentrationValue),
        series.concentrationUnit ?? '',
        series.resultUnit,
        ref.manual ? 'manual' : 'automatic',
        ref.blankWellLabels.join(', '),
        ref.controlWellLabels.join(', '),
        _numberOrEmpty(ref.blankMean),
        _numberOrEmpty(ref.controlRawMean),
        _numberOrEmpty(ref.controlCorrectedMean),
        ref.warnings.join(' / '),
      ].map(_escape).join('\t'));
    }

    buffer
      ..writeln()
      ..writeln('Series')
      ..writeln(
        'group_id\tgroup\trole\tconcentration\tconcentration_unit\tresult_unit\treplicates\tincluded_wells\texcluded_count\texcluded_wells\traw_mean\tblank_corrected_mean\tsample_sd\tcv_percent\tnormalized_percent',
      );
    for (final series in report.series) {
      buffer.writeln(
        [
          series.groupId ?? '',
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
    if (value == null || !value.isFinite) {
      return '';
    }
    if (value.abs() < 1e15 && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  String _escape(String value) {
    return value.replaceAll('\t', ' ').replaceAll('\n', ' ').trim();
  }
}

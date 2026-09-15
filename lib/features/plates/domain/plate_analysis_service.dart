import 'dart:math' as math;

import 'plate.dart';
import 'well.dart';
import 'well_group.dart';
import 'well_role.dart';

class PlateAnalysisReport {
  const PlateAnalysisReport({
    required this.series,
    required this.measuredWellCount,
    required this.includedWellCount,
    required this.excludedWellCount,
    required this.blankMeanByUnit,
    required this.controlByUnit,
  });

  final List<PlateAnalysisSeries> series;
  final int measuredWellCount;
  final int includedWellCount;
  final int excludedWellCount;
  final Map<String, double> blankMeanByUnit;
  final Map<String, PlateAnalysisControl> controlByUnit;

  bool get hasResults => measuredWellCount > 0;
}

class PlateAnalysisControl {
  const PlateAnalysisControl({
    required this.role,
    required this.rawMean,
    required this.correctedMean,
    required this.wellCount,
  });

  final WellRole role;
  final double rawMean;
  final double correctedMean;
  final int wellCount;
}

class PlateAnalysisSeries {
  const PlateAnalysisSeries({
    required this.label,
    required this.role,
    required this.concentrationValue,
    required this.concentrationUnit,
    required this.resultUnit,
    required this.includedWellLabels,
    required this.excludedWellLabels,
    required this.rawMean,
    required this.blankCorrectedMean,
    required this.standardDeviation,
    required this.coefficientOfVariation,
    required this.normalizedPercent,
  });

  final String label;
  final WellRole role;
  final double? concentrationValue;
  final String? concentrationUnit;
  final String resultUnit;
  final List<String> includedWellLabels;
  final List<String> excludedWellLabels;
  final double rawMean;
  final double blankCorrectedMean;
  final double? standardDeviation;
  final double? coefficientOfVariation;
  final double? normalizedPercent;

  int get replicateCount => includedWellLabels.length;
  int get excludedCount => excludedWellLabels.length;
}

class PlateAnalysisService {
  const PlateAnalysisService();

  static const _controlPriority = [
    WellRole.vehicleControl,
    WellRole.untreatedControl,
    WellRole.negativeControl,
  ];

  PlateAnalysisReport analyze(Plate plate) {
    final measured = plate.wells
        .where((well) => well.resultValue != null)
        .toList(growable: false);
    final included =
        measured.where((well) => !well.excluded).toList(growable: false);
    final blankMeanByUnit = _blankMeans(included);
    final controlByUnit = _controls(included, blankMeanByUnit);
    final groupsById = {for (final group in plate.groups) group.id: group};
    final buckets = <_SeriesKey, List<Well>>{};
    final excludedBuckets = <_SeriesKey, List<Well>>{};

    for (final well in measured) {
      final key = _seriesKey(well, groupsById);
      (well.excluded ? excludedBuckets : buckets)
          .putIfAbsent(key, () => <Well>[])
          .add(well);
    }

    final keys = {...buckets.keys, ...excludedBuckets.keys}.toList()
      ..sort(_compareKeys);
    final series = <PlateAnalysisSeries>[];
    for (final key in keys) {
      final values = buckets[key] ?? const <Well>[];
      if (values.isEmpty) {
        continue;
      }
      final rawValues = values.map((well) => well.resultValue!).toList();
      final rawMean = _mean(rawValues);
      final blankMean = blankMeanByUnit[key.resultUnit] ?? 0;
      final correctedMean = rawMean - blankMean;
      final standardDeviation = _sampleStandardDeviation(rawValues, rawMean);
      final control = controlByUnit[key.resultUnit];
      final normalizedPercent = control == null || control.correctedMean == 0
          ? null
          : correctedMean / control.correctedMean * 100;
      series.add(
        PlateAnalysisSeries(
          label: key.label,
          role: key.role,
          concentrationValue: key.concentrationValue,
          concentrationUnit: key.concentrationUnit,
          resultUnit: key.resultUnit,
          includedWellLabels: [for (final well in values) well.label],
          excludedWellLabels: [
            for (final well in excludedBuckets[key] ?? const <Well>[])
              well.label,
          ],
          rawMean: rawMean,
          blankCorrectedMean: correctedMean,
          standardDeviation: standardDeviation,
          coefficientOfVariation: standardDeviation == null || rawMean == 0
              ? null
              : standardDeviation.abs() / rawMean.abs() * 100,
          normalizedPercent: normalizedPercent,
        ),
      );
    }

    return PlateAnalysisReport(
      series: series,
      measuredWellCount: measured.length,
      includedWellCount: included.length,
      excludedWellCount: measured.length - included.length,
      blankMeanByUnit: blankMeanByUnit,
      controlByUnit: controlByUnit,
    );
  }

  Map<String, double> _blankMeans(List<Well> wells) {
    final byUnit = <String, List<double>>{};
    for (final well in wells.where((well) => well.role == WellRole.blank)) {
      byUnit
          .putIfAbsent(_resultUnit(well), () => <double>[])
          .add(well.resultValue!);
    }
    return {for (final entry in byUnit.entries) entry.key: _mean(entry.value)};
  }

  Map<String, PlateAnalysisControl> _controls(
    List<Well> wells,
    Map<String, double> blankMeanByUnit,
  ) {
    final units = wells.map(_resultUnit).toSet();
    final controls = <String, PlateAnalysisControl>{};
    for (final unit in units) {
      for (final role in _controlPriority) {
        final matches = wells
            .where((well) => well.role == role && _resultUnit(well) == unit)
            .toList();
        if (matches.isEmpty) {
          continue;
        }
        final rawMean = _mean([for (final well in matches) well.resultValue!]);
        controls[unit] = PlateAnalysisControl(
          role: role,
          rawMean: rawMean,
          correctedMean: rawMean - (blankMeanByUnit[unit] ?? 0),
          wellCount: matches.length,
        );
        break;
      }
    }
    return controls;
  }

  _SeriesKey _seriesKey(Well well, Map<String, WellGroup> groupsById) {
    final group = groupsById[well.groupId];
    return _SeriesKey(
      groupId: group?.id,
      label: group?.name ?? well.role.analysisLabel,
      role: group?.role ?? well.role,
      concentrationValue: well.concentrationValue,
      concentrationUnit: well.concentrationUnit ?? group?.concentrationUnit,
      resultUnit: _resultUnit(well),
    );
  }

  int _compareKeys(_SeriesKey a, _SeriesKey b) {
    final label = a.label.compareTo(b.label);
    if (label != 0) {
      return label;
    }
    final concentrationA = a.concentrationValue ?? double.negativeInfinity;
    final concentrationB = b.concentrationValue ?? double.negativeInfinity;
    return concentrationB.compareTo(concentrationA);
  }

  String _resultUnit(Well well) {
    final unit = well.resultUnit?.trim();
    return unit == null || unit.isEmpty ? '결과값' : unit;
  }

  double _mean(List<double> values) {
    return values.reduce((sum, value) => sum + value) / values.length;
  }

  double? _sampleStandardDeviation(List<double> values, double mean) {
    if (values.length < 2) {
      return null;
    }
    final squaredDifferenceSum = values.fold<double>(
      0,
      (sum, value) => sum + math.pow(value - mean, 2).toDouble(),
    );
    return math.sqrt(squaredDifferenceSum / (values.length - 1));
  }
}

class _SeriesKey {
  const _SeriesKey({
    required this.groupId,
    required this.label,
    required this.role,
    required this.concentrationValue,
    required this.concentrationUnit,
    required this.resultUnit,
  });

  final String? groupId;
  final String label;
  final WellRole role;
  final double? concentrationValue;
  final String? concentrationUnit;
  final String resultUnit;

  @override
  bool operator ==(Object other) {
    return other is _SeriesKey &&
        other.groupId == groupId &&
        other.label == label &&
        other.role == role &&
        other.concentrationValue == concentrationValue &&
        other.concentrationUnit == concentrationUnit &&
        other.resultUnit == resultUnit;
  }

  @override
  int get hashCode => Object.hash(
        groupId,
        label,
        role,
        concentrationValue,
        concentrationUnit,
        resultUnit,
      );
}

extension on WellRole {
  String get analysisLabel {
    return switch (this) {
      WellRole.empty => '그룹 없음',
      WellRole.treatment => '처리군',
      WellRole.sample => 'Sample',
      WellRole.blank => 'Blank',
      WellRole.negativeControl => 'Negative control',
      WellRole.positiveControl => 'Positive control',
      WellRole.vehicleControl => 'Vehicle control',
      WellRole.untreatedControl => 'Untreated control',
      WellRole.standard => 'Standard',
    };
  }
}

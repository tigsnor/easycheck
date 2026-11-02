import 'plate.dart';
import 'plate_analysis_service.dart';

/// Compares current data with a read-only inclusion scenario, not historical
/// measurements. Reusing the analysis service preserves reference safeguards.
class ExclusionComparison {
  ExclusionComparison(Plate plate, {String? wellLabel}) {
    reinstatedLabels = [
      for (final w in plate.wells)
        if (w.excluded && (wellLabel == null || w.label == wellLabel)) w.label
    ];
    current = const PlateAnalysisService().analyze(plate);
    hypothetical = const PlateAnalysisService().analyze(plate.copyWith(wells: [
      for (final w in plate.wells)
        reinstatedLabels.contains(w.label) ? w.copyWith(excluded: false) : w,
    ]));
    final currentByKey = {for (final s in current.series) _key(s): s};
    final hypotheticalByKey = {for (final s in hypothetical.series) _key(s): s};
    rows = [
      for (final key in {...currentByKey.keys, ...hypotheticalByKey.keys})
        (current: currentByKey[key], hypothetical: hypotheticalByKey[key])
    ];
  }

  late final List<String> reinstatedLabels;
  late final PlateAnalysisReport current, hypothetical;
  late final List<
      ({PlateAnalysisSeries? current, PlateAnalysisSeries? hypothetical})> rows;

  Object _key(PlateAnalysisSeries s) => (
        s.groupId,
        s.label,
        s.role,
        s.concentrationValue,
        s.concentrationUnit,
        s.resultUnit,
        s.cellCondition,
        s.assayCondition
      );
}

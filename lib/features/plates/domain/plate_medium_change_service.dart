import '../../../shared/models/well_position.dart';
import '../../dilution/domain/medium_change_plan.dart';
import 'assay_condition.dart';
import 'plate.dart';
import 'well.dart';

class PlateMediumChangeService {
  const PlateMediumChangeService();

  /// Known source values must agree with the calculation. Missing source values
  /// require explicit input in the sheet; they are not inferred as zero.
  void validateSource(Iterable<Well> wells, MediumChangePlan plan) {
    if (plan.mode == MediumChangeMode.replaceAll) return;
    for (final w in wells) {
      final conflicts = <String>[
        if (w.volumeValue != null &&
            (w.volumeUnit != 'µL' || w.volumeValue != plan.initialVolume))
          '부피',
        if (w.concentrationValue != null &&
            (w.concentrationUnit != plan.unit ||
                w.concentrationValue != plan.initialConcentration))
          '농도/단위',
        if (w.assayCondition != null &&
            (w.assayCondition!.vehiclePercent != plan.initialVehiclePercent ||
                (w.assayCondition!.vehiclePercent > 0 &&
                    w.assayCondition!.vehicle != plan.vehicle)))
          '용매/비율',
      ];
      if (conflicts.isNotEmpty) {
        throw FormatException(
            '${w.label}의 기존 ${conflicts.join('·')} 기록과 입력값이 다릅니다. 같은 조건의 well을 선택하거나 기존 기록을 먼저 확인해주세요.');
      }
    }
  }

  Plate apply(
      {required Plate plate,
      required Set<WellPosition> positions,
      required MediumChangePlan plan,
      required String finalMedium}) {
    if (positions.isEmpty ||
        positions.any((p) => !plate.wells.any((w) => w.position == p))) {
      throw const FormatException('적용할 well을 확인해주세요.');
    }
    final selected = plate.wells.where((w) => positions.contains(w.position));
    validateSource(selected, plan);
    final condition = AssayCondition.fromJson({
      'medium': finalMedium,
      'vehicle': plan.vehicle,
      'vehiclePercent': plan.finalVehiclePercent,
    });
    return plate.copyWith(wells: [
      for (final w in plate.wells)
        if (positions.contains(w.position))
          w.copyWith(
            concentrationValue:
                plan.mediumOnly ? null : plan.finalConcentration,
            concentrationUnit: plan.mediumOnly ? null : plan.unit,
            volumeValue: plan.finalVolume,
            volumeUnit: 'µL',
            assayCondition: condition,
          )
        else
          w,
    ]);
  }
}

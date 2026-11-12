import 'cell_condition.dart';

/// Explicit seeding volume, never the well's current medium volume.
abstract final class SeedingConversion {
  static double convert(
      double quantity, String fromUnit, double volumeMicrolitres) {
    if (!quantity.isFinite ||
        quantity < 0 ||
        !CellCondition.units.contains(fromUnit) ||
        !volumeMicrolitres.isFinite ||
        volumeMicrolitres <= 0) {
      throw const FormatException('세포 수치와 0보다 큰 파종 부피를 확인해주세요.');
    }
    final millilitres = volumeMicrolitres / 1000;
    if (millilitres == 0) {
      throw const FormatException('파종 부피가 계산 범위를 벗어났습니다.');
    }
    final result = fromUnit == 'cells/mL'
        ? quantity * millilitres
        : quantity / millilitres;
    if (!result.isFinite || (quantity > 0 && result == 0)) {
      throw const FormatException('환산값이 계산 범위를 벗어났습니다.');
    }
    return result;
  }
}

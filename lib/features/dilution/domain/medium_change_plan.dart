enum MediumChangeMode { add, replacePart, replaceAll }

extension MediumChangeModeLabel on MediumChangeMode {
  String get label => switch (this) {
        MediumChangeMode.add => '추가',
        MediumChangeMode.replacePart => '일부 교체',
        MediumChangeMode.replaceAll => '전체 교체',
      };
}

/// Homogeneous removal, additive volumes, one analyte and one vehicle.
/// All concentrations share one explicit unit; all volumes are microlitres.
class MediumChangePlan {
  MediumChangePlan({
    required this.mode,
    required this.unit,
    required this.incomingVolume,
    required this.incomingConcentration,
    required this.incomingVehiclePercent,
    required this.vehicle,
    required this.initialVolume,
    required this.initialConcentration,
    required this.initialVehiclePercent,
    this.removedVolume = 0,
  }) {
    void nonnegative(double value, String name) {
      if (!value.isFinite || value < 0) {
        throw FormatException('$name 값을 0 이상의 유한한 숫자로 입력해주세요.');
      }
    }

    void percent(double value) {
      nonnegative(value, '용매 비율');
      if (value > 100) throw const FormatException('용매 비율은 0~100% v/v 범위입니다.');
    }

    if (unit.trim().isEmpty || unit != unit.trim()) {
      throw const FormatException('공통 농도 단위를 입력해주세요.');
    }
    if (vehicle != null &&
        (vehicle!.trim().isEmpty || vehicle != vehicle!.trim())) {
      throw const FormatException('용매 이름을 확인해주세요.');
    }
    nonnegative(incomingVolume, '추가 용액 부피');
    if (incomingVolume == 0) {
      throw const FormatException('추가 용액 부피는 0보다 커야 합니다.');
    }
    nonnegative(incomingConcentration, '추가 용액 농도');
    percent(incomingVehiclePercent);
    if (mode != MediumChangeMode.replaceAll) {
      nonnegative(initialVolume, '기존 부피');
      nonnegative(initialConcentration, '기존 농도');
      percent(initialVehiclePercent);
      nonnegative(removedVolume, '제거 부피');
      if (mode == MediumChangeMode.add && removedVolume != 0) {
        throw const FormatException('추가 모드에서는 기존 배지를 제거하지 않습니다.');
      }
      if (mode == MediumChangeMode.replacePart &&
          (removedVolume <= 0 || removedVolume >= initialVolume)) {
        throw const FormatException(
            '제거 부피는 0보다 크고 기존 부피보다 작아야 합니다. 전량 제거는 전체 교체를 선택하세요.');
      }
    }
    if (vehicle == null &&
        (incomingVehiclePercent != 0 ||
            (mode != MediumChangeMode.replaceAll &&
                initialVolume > 0 &&
                initialVehiclePercent != 0))) {
      throw const FormatException('용매 비율이 0이 아니면 같은 용매의 이름을 입력해주세요.');
    }
    if (!finalVolume.isFinite ||
        finalVolume <= 0 ||
        !finalConcentration.isFinite ||
        !finalVehiclePercent.isFinite) {
      throw const FormatException('계산 범위를 벗어났습니다. 입력값의 크기와 단위를 확인해주세요.');
    }
  }

  final MediumChangeMode mode;
  final String unit;
  final String? vehicle;
  final double initialVolume, initialConcentration, initialVehiclePercent;
  final double removedVolume,
      incomingVolume,
      incomingConcentration,
      incomingVehiclePercent;

  double get retainedVolume =>
      mode == MediumChangeMode.replaceAll ? 0 : initialVolume - removedVolume;
  double get finalVolume => retainedVolume + incomingVolume;
  double _mix(double initial, double incoming) => retainedVolume == 0
      ? incoming
      : initial * (retainedVolume / finalVolume) +
          incoming * (incomingVolume / finalVolume);
  double get finalConcentration =>
      _mix(initialConcentration, incomingConcentration);
  double get finalVehiclePercent =>
      _mix(initialVehiclePercent, incomingVehiclePercent)
          .clamp(0, 100)
          .toDouble();
  bool get hasLowDispenseVolume =>
      incomingVolume < 1 ||
      (mode == MediumChangeMode.replacePart && removedVolume < 1);

  String get description => '${mode.label} · 공통 단위 $unit · '
      '${mode == MediumChangeMode.replaceAll ? '기존 배지 전량 제거' : '기존 $initialVolume µL / $initialConcentration $unit / $initialVehiclePercent% v/v, 제거 $removedVolume µL, 잔류 $retainedVolume µL'} · '
      '추가 $incomingVolume µL / $incomingConcentration $unit / $incomingVehiclePercent% v/v · '
      '최종 $finalVolume µL / $finalConcentration $unit / $finalVehiclePercent% v/v · 용매 ${vehicle ?? '없음'}';
}

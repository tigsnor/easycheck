import 'dart:convert';

/// Explicit final well environment. Null on a well means unrecorded, not no vehicle.
class AssayCondition {
  const AssayCondition(
      {required this.medium, required this.vehiclePercent, this.vehicle});
  final String medium;
  final String? vehicle;
  final double vehiclePercent;

  factory AssayCondition.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('배지·용매 조건이 올바르지 않습니다.');
    final medium = value['medium'];
    final vehicle = value['vehicle'];
    final percent = value['vehiclePercent'];
    if (medium is! String ||
        medium.trim().isEmpty ||
        medium.trim() != medium ||
        (vehicle != null &&
            (vehicle is! String ||
                vehicle.trim().isEmpty ||
                vehicle.trim() != vehicle)) ||
        percent is! num ||
        !percent.isFinite ||
        percent < 0 ||
        percent > 100 ||
        (vehicle == null && percent != 0)) {
      throw const FormatException('배지·용매 이름과 최종 용매 비율(0~100% v/v)을 확인해주세요.');
    }
    return AssayCondition(
        medium: medium,
        vehicle: vehicle as String?,
        vehiclePercent: percent.toDouble());
  }

  Map<String, Object?> toJson() =>
      {'medium': medium, 'vehicle': vehicle, 'vehiclePercent': vehiclePercent};
  String get key =>
      jsonEncode([medium, vehicle, vehiclePercent == 0 ? 0.0 : vehiclePercent]);
  String get label => '$medium · ${vehicle ?? '용매 없음'} · $vehiclePercent% v/v';

  @override
  bool operator ==(Object other) =>
      other is AssayCondition &&
      medium == other.medium &&
      vehicle == other.vehicle &&
      vehiclePercent == other.vehiclePercent;
  @override
  int get hashCode => Object.hash(medium, vehicle, vehiclePercent);
}

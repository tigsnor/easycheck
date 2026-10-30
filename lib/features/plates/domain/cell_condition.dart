import 'dart:convert';

/// Seeding conditions, independent of treatment concentration and group.
class CellCondition {
  const CellCondition({required this.name, this.density, this.unit});

  static const units = ['cells/mL', 'cells/well'];
  final String name;
  final double? density;
  final String? unit;

  factory CellCondition.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid cell condition.');
    final name = value['name'];
    final density = value['density'];
    final unit = value['unit'];
    if (name is! String ||
        name.trim().isEmpty ||
        name.trim() != name ||
        (density != null &&
            (density is! num || !density.isFinite || density < 0)) ||
        (density == null ? unit != null : !units.contains(unit))) {
      throw const FormatException('Invalid cell type, density or unit.');
    }
    return CellCondition(
        name: name,
        density: (density as num?)?.toDouble(),
        unit: unit as String?);
  }

  Map<String, Object?> toJson() =>
      {'name': name, 'density': density, 'unit': unit};
  String get key => jsonEncode([name, density, unit]);
  String get label =>
      '$name · ${density == null ? '세포 농도 미지정' : '${_number(density!)} $unit'}';

  static String _number(double n) => n.abs() < 1e15 && n == n.roundToDouble()
      ? n.toInt().toString()
      : n.toString();

  @override
  bool operator ==(Object other) =>
      other is CellCondition &&
      name == other.name &&
      density == other.density &&
      unit == other.unit;
  @override
  int get hashCode => Object.hash(name, density, unit);
}

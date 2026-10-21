import '../../../shared/models/well_position.dart';
import 'well.dart';
import 'well_group.dart';

void validatePlateLayout({
  required int rowCount,
  required int columnCount,
  required List<Well> wells,
  required List<WellGroup> groups,
}) {
  if (rowCount <= 0 ||
      columnCount <= 0 ||
      wells.length != rowCount * columnCount) {
    throw const FormatException(
        'Plate dimensions and well count do not match.');
  }
  final groupIds = <String>{};
  for (final group in groups) {
    if (group.id.trim().isEmpty || !groupIds.add(group.id)) {
      throw const FormatException(
          'Plate group IDs must be nonempty and unique.');
    }
  }
  final positions = <WellPosition>{};
  for (final well in wells) {
    final position = well.position;
    if (position.rowIndex < 0 ||
        position.rowIndex >= rowCount ||
        position.columnIndex < 0 ||
        position.columnIndex >= columnCount ||
        !positions.add(position)) {
      throw const FormatException(
          'Plate contains invalid or duplicate well coordinates.');
    }
    if (well.groupId != null && !groupIds.contains(well.groupId)) {
      throw const FormatException('Well references a missing group.');
    }
    for (final value in [
      well.concentrationValue,
      well.volumeValue,
      well.resultValue
    ]) {
      if (value != null && !value.isFinite) {
        throw const FormatException('Well values must be finite numbers.');
      }
    }
    if ((well.concentrationValue != null && well.concentrationValue! < 0) ||
        (well.volumeValue != null && well.volumeValue! < 0)) {
      throw const FormatException(
          'Concentration and volume cannot be negative.');
    }
  }
}

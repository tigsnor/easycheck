import '../../../shared/models/well_position.dart';
import 'well.dart';
import 'well_group.dart';

class Plate {
  Plate({
    required this.id,
    required this.experimentId,
    required this.name,
    this.rowCount = 8,
    this.columnCount = 12,
    List<Well>? wells,
    this.groups = const [],
    this.notes = '',
  }) : wells = wells ?? _buildEmptyWells(rowCount, columnCount);

  final String id;
  final String experimentId;
  final String name;
  final int rowCount;
  final int columnCount;
  final List<Well> wells;
  final List<WellGroup> groups;
  final String notes;

  static List<Well> _buildEmptyWells(int rowCount, int columnCount) {
    return [
      for (var row = 0; row < rowCount; row++)
        for (var column = 0; column < columnCount; column++)
          Well(position: WellPosition(rowIndex: row, columnIndex: column)),
    ];
  }

  Well wellAt(WellPosition position) {
    return wells.firstWhere((well) => well.position == position);
  }
}

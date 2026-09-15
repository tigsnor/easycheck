import '../../../shared/models/well_position.dart';
import '../../dilution/domain/dilution_direction.dart';
import '../../dilution/domain/dilution_plan.dart';
import '../../dilution/domain/dilution_service.dart';
import 'plate.dart';
import 'well_group.dart';

class PlateDilutionService {
  const PlateDilutionService({this.dilutionService = const DilutionService()});

  final DilutionService dilutionService;

  Plate applySeries({
    required Plate plate,
    required DilutionPlan plan,
    required WellGroup group,
    required int replicateCount,
    double? volumePerWell,
    String volumeUnit = 'µL',
    Set<WellPosition> selectedPositions = const {},
  }) {
    assert(replicateCount > 0);

    final series = dilutionService.buildSeries(plan);
    final positions = _targetPositions(
      plate: plate,
      direction: plan.direction,
      targetCount: series.length * replicateCount,
      selectedPositions: selectedPositions,
    );
    final groups = _upsertGroup(plate.groups, group);
    final updatedWells = plate.wells.map((well) {
      final targetIndex = positions.indexOf(well.position);
      if (targetIndex == -1) {
        return well;
      }

      final concentration = series[targetIndex ~/ replicateCount];
      return well.copyWith(
        groupId: group.id,
        role: group.role,
        concentrationValue: concentration,
        concentrationUnit: group.concentrationUnit,
        replicateIndex: (targetIndex % replicateCount) + 1,
        volumeValue: volumePerWell,
        volumeUnit: volumeUnit,
      );
    }).toList();

    return plate.copyWith(groups: groups, wells: updatedWells);
  }

  List<WellPosition> _targetPositions({
    required Plate plate,
    required DilutionDirection direction,
    required int targetCount,
    required Set<WellPosition> selectedPositions,
  }) {
    final candidates = selectedPositions.isEmpty
        ? plate.wells.map((well) => well.position).toList()
        : selectedPositions.toList();

    candidates.sort((a, b) => _comparePositions(a, b, direction));
    return candidates.take(targetCount).toList();
  }

  int _comparePositions(
    WellPosition a,
    WellPosition b,
    DilutionDirection direction,
  ) {
    return switch (direction) {
      DilutionDirection.topToBottom => _compareByRowThenColumn(
          a,
          b,
          rowAscending: true,
        ),
      DilutionDirection.bottomToTop => _compareByRowThenColumn(
          a,
          b,
          rowAscending: false,
        ),
      DilutionDirection.leftToRight => _compareByColumnThenRow(
          a,
          b,
          columnAscending: true,
        ),
      DilutionDirection.rightToLeft => _compareByColumnThenRow(
          a,
          b,
          columnAscending: false,
        ),
    };
  }

  int _compareByRowThenColumn(
    WellPosition a,
    WellPosition b, {
    required bool rowAscending,
  }) {
    final rowComparison = rowAscending
        ? a.rowIndex.compareTo(b.rowIndex)
        : b.rowIndex.compareTo(a.rowIndex);
    if (rowComparison != 0) {
      return rowComparison;
    }
    return a.columnIndex.compareTo(b.columnIndex);
  }

  int _compareByColumnThenRow(
    WellPosition a,
    WellPosition b, {
    required bool columnAscending,
  }) {
    final columnComparison = columnAscending
        ? a.columnIndex.compareTo(b.columnIndex)
        : b.columnIndex.compareTo(a.columnIndex);
    if (columnComparison != 0) {
      return columnComparison;
    }
    return a.rowIndex.compareTo(b.rowIndex);
  }

  List<WellGroup> _upsertGroup(List<WellGroup> groups, WellGroup group) {
    final updated = [...groups];
    final index = updated.indexWhere((candidate) => candidate.id == group.id);
    if (index == -1) {
      updated.add(group);
    } else {
      updated[index] = group;
    }
    return updated;
  }
}

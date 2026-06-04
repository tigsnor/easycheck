import 'plate.dart';
import 'well.dart';
import 'well_group.dart';

class PlateExportService {
  const PlateExportService();

  String buildTsv(Plate plate) {
    final buffer = StringBuffer()
      ..writeln('EasyCheck plate export')
      ..writeln('Plate\t${_escape(plate.name)}')
      ..writeln('Experiment ID\t${_escape(plate.experimentId)}')
      ..writeln('Rows\t${plate.rowCount}')
      ..writeln('Columns\t${plate.columnCount}')
      ..writeln()
      ..writeln('Groups')
      ..writeln(
          'group_id\tname\tlabel\trole\tunit\twell_count\tconcentrations');

    for (final group in plate.groups) {
      final wells =
          plate.wells.where((well) => well.groupId == group.id).toList();
      if (wells.isEmpty) {
        continue;
      }
      buffer.writeln(
        [
          group.id,
          group.name,
          group.shortLabel,
          group.role.name,
          group.concentrationUnit,
          wells.length.toString(),
          _concentrationSeries(wells, group.concentrationUnit).join(' → '),
        ].map(_escape).join('\t'),
      );
    }

    buffer
      ..writeln()
      ..writeln('Wells')
      ..writeln(
        'well\trow\tcolumn\tgroup\trole\tconcentration\tunit\treplicate\tvolume\tvolume_unit\tnote',
      );

    for (final well in plate.wells) {
      buffer.writeln(_wellRow(well, plate.groups));
    }

    return buffer.toString();
  }

  String _wellRow(Well well, List<WellGroup> groups) {
    final group = groups.cast<WellGroup?>().firstWhere(
          (candidate) => candidate?.id == well.groupId,
          orElse: () => null,
        );
    return [
      well.label,
      well.position.rowLabel,
      well.position.columnNumber.toString(),
      group?.name ?? '',
      well.role.name,
      well.concentrationValue == null
          ? ''
          : _formatNumber(well.concentrationValue!),
      well.concentrationUnit ?? group?.concentrationUnit ?? '',
      well.replicateIndex?.toString() ?? '',
      well.volumeValue == null ? '' : _formatNumber(well.volumeValue!),
      well.volumeUnit,
      well.note,
    ].map(_escape).join('\t');
  }

  List<String> _concentrationSeries(List<Well> wells, String unit) {
    final concentrations = wells
        .map((well) => well.concentrationValue)
        .nonNulls
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return [
      for (final concentration in concentrations)
        '${_formatNumber(concentration)} $unit',
    ];
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  String _escape(String value) {
    return value.replaceAll('\t', ' ').replaceAll('\n', ' ').trim();
  }
}

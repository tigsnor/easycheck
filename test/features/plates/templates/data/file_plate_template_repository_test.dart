import 'dart:io';

import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/templates/data/file_plate_template_repository.dart';
import 'package:easycheck/features/plates/templates/domain/plate_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late FilePlateTemplateRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('easycheck-templates-');
    repository = FilePlateTemplateRepository(rootDirectory: directory.path);
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('persists, updates, sorts, and deletes templates', () async {
    final older = _template('older', 'Older', DateTime.utc(2026, 6, 10));
    final newer = _template('newer', 'Newer', DateTime.utc(2026, 6, 12));
    await repository.saveTemplate(older);
    await repository.saveTemplate(newer);

    expect((await repository.loadTemplates()).map((item) => item.id), [
      'newer',
      'older',
    ]);

    await repository.saveTemplate(
      PlateTemplate(
        id: newer.id,
        name: 'Renamed',
        createdAt: newer.createdAt,
        updatedAt: DateTime.utc(2026, 6, 13),
        rowCount: newer.rowCount,
        columnCount: newer.columnCount,
        wells: newer.wells,
        groups: newer.groups,
      ),
    );
    expect((await repository.loadTemplates()).first.name, 'Renamed');

    await repository.deleteTemplate('older');
    expect((await repository.loadTemplates()).single.id, 'newer');
  });
}

PlateTemplate _template(String id, String name, DateTime date) {
  return PlateTemplate.fromPlate(
    id: id,
    name: name,
    plate: Plate(id: 'plate-$id', experimentId: 'experiment-$id', name: name),
    createdAt: date,
  );
}

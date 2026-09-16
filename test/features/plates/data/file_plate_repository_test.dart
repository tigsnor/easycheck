import 'dart:convert';
import 'dart:io';

import 'package:easycheck/features/plates/data/file_plate_repository.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late FilePlateRepository repository;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('easycheck-plates-');
    repository = FilePlateRepository(rootDirectory: directory.path);
    file = File('${directory.path}/plates/experiment-1.json');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('loads a legacy plate and writes a versioned envelope', () async {
    final legacy = _plate('Legacy');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(legacy.toJson()));

    expect((await repository.loadPlate('experiment-1'))!.name, 'Legacy');
    await repository.savePlate(legacy.copyWith(name: 'Updated'));

    final encoded = jsonDecode(await file.readAsString()) as Map;
    expect(encoded['schemaVersion'], FilePlateRepository.schemaVersion);
    expect((encoded['data'] as Map)['name'], 'Updated');
  });

  test('recovers a plate from the last valid backup', () async {
    await repository.savePlate(_plate('First'));
    await repository.savePlate(_plate('Second'));
    await file.writeAsString('', flush: true);

    expect((await repository.loadPlate('experiment-1'))!.name, 'First');
  });

  test('deleting a plate also removes backup and temporary files', () async {
    await repository.savePlate(_plate('First'));
    await repository.savePlate(_plate('Second'));
    await File('${file.path}.tmp').writeAsString('stale');

    await repository.deletePlate('experiment-1');

    expect(await file.exists(), isFalse);
    expect(await File('${file.path}.bak').exists(), isFalse);
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });
}

Plate _plate(String name) {
  return Plate(id: 'plate-1', experimentId: 'experiment-1', name: name);
}

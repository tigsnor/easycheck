import 'dart:convert';
import 'dart:io';

import 'package:easycheck/shared/data/safe_json_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const store = SafeJsonFileStore();
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('easycheck-json-store-');
    file = File('${directory.path}/data.json');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('rotates the last valid primary file to a backup', () async {
    await store.write(file, {'value': 1});
    await store.write(file, {'value': 2});

    expect(jsonDecode(await file.readAsString()), {'value': 2});
    expect(jsonDecode(await File('${file.path}.bak').readAsString()), {
      'value': 1,
    });
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test('recovers a corrupt primary file from the last valid backup', () async {
    await store.write(file, {'value': 1});
    await store.write(file, {'value': 2});
    await file.writeAsString('{broken', flush: true);

    expect(await store.read(file), {'value': 1});
    expect(jsonDecode(await file.readAsString()), {'value': 1});
  });

  test('does not replace a valid backup with a corrupt primary', () async {
    await store.write(file, {'value': 1});
    await store.write(file, {'value': 2});
    await file.writeAsString('', flush: true);

    await store.write(file, {'value': 3});

    expect(jsonDecode(await file.readAsString()), {'value': 3});
    expect(jsonDecode(await File('${file.path}.bak').readAsString()), {
      'value': 1,
    });
  });

  test('reports corruption when primary and backup are unusable', () async {
    await file.parent.create(recursive: true);
    await file.writeAsString('{broken');
    await File('${file.path}.bak').writeAsString('also broken');

    expect(() => store.read(file), throwsA(isA<JsonFileCorruptionException>()));
  });
}

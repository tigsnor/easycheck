import 'dart:convert';
import 'dart:io';

import 'package:easycheck/shared/data/local_data_recovery_events.dart';
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

  test('recovers a missing primary after an interrupted rotation', () async {
    await File('${file.path}.bak').writeAsString('{"value":1}');
    await File('${file.path}.tmp').writeAsString('{"value":2}');
    expect(await store.read(file), {'value': 1});
    expect(jsonDecode(await file.readAsString()), {'value': 1});
  });

  test('recovers a validated first write from a temporary file', () async {
    await File('${file.path}.tmp').writeAsString('{"value":2}');
    expect(await store.read(file), {'value': 2});
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test('does not treat an invalid pending write as an empty store', () async {
    await File('${file.path}.tmp').writeAsString('{broken');
    await expectLater(
        store.read(file), throwsA(isA<JsonFileCorruptionException>()));
    expect(await File('${file.path}.tmp').readAsString(), '{broken');
  });

  test('preserves a corrupt primary before recovery', () async {
    await file.writeAsString('{broken');
    await File('${file.path}.bak').writeAsString('{"value":1}');
    await store.read(file);
    final preserved = await directory
        .list()
        .where((f) => f.path.contains('.corrupt-'))
        .toList();
    expect(preserved, hasLength(1));
    expect(await File(preserved.single.path).readAsString(), '{broken');
  });

  test('serializes updates from different store instances', () async {
    await store.write(file, {'value': 0});
    await Future.wait(List.generate(
        25,
        (_) => const SafeJsonFileStore().update(
              file,
              (current) => {'value': (current as Map)['value'] + 1},
            )));
    expect(await store.read(file), {'value': 25});
  });

  test('a failed update does not block later writes or replace valid data',
      () async {
    bool valid(Object? value) => value is Map && value['value'] is int;
    await store.write(file, {'value': 1}, validator: valid);
    await expectLater(
        store.update(file, (_) => {'value': 'invalid'}, validator: valid),
        throwsFormatException);
    expect(await store.read(file, validator: valid), {'value': 1});
    await store.update(file, (_) => {'value': 2}, validator: valid);
    expect(await store.read(file, validator: valid), {'value': 2});
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

  test('reports an automatic recovery event', () async {
    LocalDataRecoveryEvent? recoveryEvent;
    final reportingStore = SafeJsonFileStore(
      recoverySink: (event) => recoveryEvent = event,
    );
    await reportingStore.write(file, {'value': 1});
    await reportingStore.write(file, {'value': 2});
    await file.writeAsString('{broken', flush: true);

    await reportingStore.read(file);

    expect(recoveryEvent, isNotNull);
    expect(recoveryEvent!.filePath, file.path);
    expect(recoveryEvent!.backupPath, '${file.path}.bak');
    expect(recoveryEvent!.fileName, 'data.json');
  });

  test('reports corruption when primary and backup are unusable', () async {
    await file.parent.create(recursive: true);
    await file.writeAsString('{broken');
    await File('${file.path}.bak').writeAsString('also broken');

    expect(() => store.read(file), throwsA(isA<JsonFileCorruptionException>()));
  });
}

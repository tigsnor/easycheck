import 'dart:convert';

import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = EasyCheckBackupService();

  test('round-trips experiments and connected plates', () {
    final experiment = Experiment(
      id: 'experiment-1',
      title: 'CCK-8 backup',
      createdAt: DateTime.utc(2026, 6, 8),
      updatedAt: DateTime.utc(2026, 6, 8),
    );
    final plate = Plate(
      id: 'plate-1',
      experimentId: experiment.id,
      name: '96-well Plate',
    );

    final encoded = service.encode(
      experiments: [experiment],
      plates: [plate],
      exportedAt: DateTime.utc(2026, 6, 8, 12),
    );
    final backup = service.decode(encoded);

    expect(backup.schemaVersion, 1);
    expect(backup.exportedAt, DateTime.utc(2026, 6, 8, 12));
    expect(backup.experiments.single.title, 'CCK-8 backup');
    expect(backup.plates.single.experimentId, experiment.id);
    expect(encoded, contains('"format": "easycheck-backup"'));
  });

  test('rejects unsupported future backup versions', () {
    const source = '''
{
  "format": "easycheck-backup",
  "schemaVersion": 999,
  "exportedAt": "2026-06-08T00:00:00.000Z",
  "experiments": [],
  "plates": []
}
''';

    expect(() => service.decode(source), throwsA(isA<FormatException>()));
  });

  test('rejects orphan plates during restore', () {
    final plate = Plate(
      id: 'plate-1',
      experimentId: 'missing-experiment',
      name: '96-well Plate',
    );
    final source = jsonEncode({
      'format': 'easycheck-backup',
      'schemaVersion': 1,
      'exportedAt': '2026-06-08T00:00:00.000Z',
      'experiments': <Object?>[],
      'plates': [plate.toJson()],
    });

    expect(() => service.decode(source), throwsA(isA<FormatException>()));
  });
}

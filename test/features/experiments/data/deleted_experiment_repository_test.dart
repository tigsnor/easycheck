import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easycheck/features/experiments/data/deleted_experiment_repository.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/plates/domain/plate.dart';

void main() {
  test('deletion snapshots survive restart and independent removal', () async {
    final directory =
        await Directory.systemTemp.createTemp('deleted-experiments-');
    addTearDown(() => directory.delete(recursive: true));
    final repository =
        FileDeletedExperimentRepository(rootDirectory: directory.path);
    final now = DateTime.utc(2026, 11, 16);
    for (final id in ['a', 'b']) {
      await repository.save(DeletedExperiment(
          experiment:
              Experiment(id: id, title: id, createdAt: now, updatedAt: now),
          plate: Plate(id: 'plate-$id', experimentId: id, name: '96 well'),
          deletedAt: now));
    }
    final reopened =
        FileDeletedExperimentRepository(rootDirectory: directory.path);
    final records = await reopened.load();
    expect(records.map((e) => e.experiment.id), ['b', 'a']);
    expect(records.first.plate!.experimentId, 'b');
    expect(records.first.deletedAt, now);
    await reopened.remove('a');
    expect((await repository.load()).single.experiment.id, 'b');
  });
}

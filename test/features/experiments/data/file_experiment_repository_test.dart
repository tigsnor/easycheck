import 'dart:convert';
import 'dart:io';

import 'package:easycheck/features/experiments/data/file_experiment_repository.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late FileExperimentRepository repository;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('easycheck-experiments-');
    repository = FileExperimentRepository(rootDirectory: directory.path);
    file = File('${directory.path}/experiments.json');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test(
    'migrates a legacy JSON list to the versioned envelope on save',
    () async {
      final legacy = _experiment(title: 'Legacy');
      await file.writeAsString(jsonEncode([legacy.toJson()]));

      expect((await repository.loadExperiments()).single.title, 'Legacy');
      await repository.saveExperiment(legacy.copyWith(title: 'Updated'));

      final encoded = jsonDecode(await file.readAsString()) as Map;
      expect(encoded['schemaVersion'], FileExperimentRepository.schemaVersion);
      expect((encoded['data'] as List).single['title'], 'Updated');
    },
  );

  test('recovers experiments from the last valid backup', () async {
    await repository.saveExperiment(_experiment(title: 'First'));
    await repository.saveExperiment(_experiment(title: 'Second'));
    await file.writeAsString('{broken', flush: true);

    final experiments = await repository.loadExperiments();

    expect(experiments.single.title, 'First');
    expect(jsonDecode(await file.readAsString()), isA<Map>());
  });

  test('recovers when the primary JSON has an unsupported schema', () async {
    await repository.saveExperiment(_experiment(title: 'First'));
    await repository.saveExperiment(_experiment(title: 'Second'));
    await file.writeAsString(
      jsonEncode({'schemaVersion': 999, 'data': []}),
      flush: true,
    );

    expect((await repository.loadExperiments()).single.title, 'First');
  });
}

Experiment _experiment({required String title}) {
  return Experiment(
    id: 'experiment-1',
    title: title,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
  );
}

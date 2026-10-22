import 'dart:convert';
import 'dart:io';

import 'package:easycheck/features/experiments/application/experiment_duplication_service.dart';
import 'package:easycheck/features/experiments/data/file_experiment_repository.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/plates/data/file_plate_repository.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well_group.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late _ExperimentRepository experiments;
  late _PlateRepository plates;
  late ExperimentDuplicationService service;
  final oldTime = DateTime.utc(2025);
  final newTime = DateTime.utc(2026);
  late Experiment source;
  late Plate sourcePlate;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('design-copy-');
    experiments = _ExperimentRepository(root.path);
    plates = _PlateRepository(root.path);
    source = Experiment(
      id: 'source',
      title: 'Assay',
      createdAt: oldTime,
      updatedAt: oldTime,
      projectName: 'Project',
      experimentType: 'ELISA',
      researcher: 'Researcher',
      cellCountLabel: '100 cells',
      tags: ['tag'],
      status: ExperimentStatus.completed,
      completedAt: oldTime,
      notes: 'Previous observation',
      tasks: [
        ExperimentTask(
            id: 'task',
            title: 'Incubate',
            isCompleted: true,
            startedAt: oldTime,
            completedAt: oldTime)
      ],
      resources: const [
        ExperimentResource(
            id: 'resource',
            type: ExperimentResourceType.reagent,
            name: 'Reagent',
            lotOrSerial: 'lot')
      ],
      revisions: [
        ExperimentRevision(id: 'revision', changedAt: oldTime, summary: 'Done')
      ],
    );
    final base = Plate(
        id: 'plate-source',
        experimentId: 'source',
        name: 'Layout',
        groups: const [
          WellGroup(
              id: 'group', name: 'Drug', shortLabel: 'D', color: Colors.blue)
        ],
        notes: 'Previous plate note');
    sourcePlate = base.copyWith(wells: [
      base.wells.first.copyWith(
          groupId: 'group',
          role: WellRole.treatment,
          concentrationValue: 10,
          concentrationUnit: 'µM',
          volumeValue: 100,
          replicateIndex: 1,
          resultValue: 0.5,
          resultUnit: 'OD',
          excluded: true,
          note: 'Previous well observation'),
      ...base.wells.skip(1),
    ], importHistory: [
      PlateResultImportRecord(
          id: 'import',
          sourceName: 'old.tsv',
          importedAt: oldTime,
          valueCount: 1,
          resultUnit: 'OD')
    ], revisions: [
      PlateRevision(
          id: 'revision',
          changedAt: oldTime,
          summary: 'Old',
          snapshot: PlateSnapshot.fromPlate(base))
    ]);
    await experiments.saveExperiment(source);
    await plates.savePlate(sourcePlate);
    service = ExperimentDuplicationService(
        experimentRepository: experiments,
        plateRepository: plates,
        createId: () => 'copy',
        now: () => newTime);
  });
  tearDown(() => root.delete(recursive: true));

  test('persists only design data and leaves the original unchanged', () async {
    final originalExperiment = jsonEncode(source.toJson());
    final originalPlate = jsonEncode(sourcePlate.toJson());
    final copy = await service.duplicateDesign(source.id);
    final restartedExperiments =
        await FileExperimentRepository(rootDirectory: root.path)
            .loadExperiments();
    final restartedPlate =
        await FilePlateRepository(rootDirectory: root.path).loadPlate(copy.id);
    expect(restartedExperiments, hasLength(2));
    expect(
        jsonEncode(
            restartedExperiments.firstWhere((e) => e.id == 'source').toJson()),
        originalExperiment);
    expect(jsonEncode((await plates.loadPlate('source'))!.toJson()),
        originalPlate);
    expect(copy.id, 'copy');
    expect(copy.status, ExperimentStatus.draft);
    expect(copy.createdAt, newTime);
    expect(copy.updatedAt, newTime);
    expect(copy.completedAt, isNull);
    expect(copy.notes, isEmpty);
    expect(copy.revisions, isEmpty);
    expect(copy.tags, ['tag']);
    expect(copy.projectName, source.projectName);
    expect(copy.experimentType, source.experimentType);
    expect(copy.cellCountLabel, source.cellCountLabel);
    expect(copy.resources.single.lotOrSerial, 'lot');
    expect(copy.tasks.single.title, 'Incubate');
    expect(copy.tasks.single.isCompleted, isFalse);
    expect(copy.tasks.single.startedAt, isNull);
    expect(copy.tasks.single.completedAt, isNull);
    expect(restartedPlate!.id, 'plate-copy');
    expect(restartedPlate.name, 'Layout');
    expect(restartedPlate.groups.single.id, 'group');
    expect(restartedPlate.rowCount, sourcePlate.rowCount);
    expect(restartedPlate.columnCount, sourcePlate.columnCount);
    expect(restartedPlate.wells.first.concentrationValue, 10);
    expect(restartedPlate.wells.first.role, WellRole.treatment);
    expect(restartedPlate.wells.first.volumeValue, 100);
    expect(restartedPlate.wells.first.replicateIndex, 1);
    expect(
        restartedPlate.wells.map((w) => w.resultValue), everyElement(isNull));
    expect(restartedPlate.wells.map((w) => w.resultUnit), everyElement(isNull));
    expect(restartedPlate.wells.map((w) => w.note), everyElement(isEmpty));
    expect(restartedPlate.wells.map((w) => w.excluded), everyElement(isFalse));
    expect(restartedPlate.notes, isEmpty);
    expect(restartedPlate.importHistory, isEmpty);
    expect(restartedPlate.revisions, isEmpty);
  });

  test('duplicates an experiment without a Plate without adding example data',
      () async {
    await plates.deletePlate('source');
    final copy = await service.duplicateDesign('source');
    expect(await plates.loadPlate(copy.id), isNull);
    expect((await experiments.loadExperiments()).length, 2);
  });

  for (final failure in ['plate', 'experiment']) {
    test('cleans up a $failure write that throws after persisting', () async {
      plates.failCopySave = failure == 'plate';
      experiments.failCopySave = failure == 'experiment';
      await expectLater(
          service.duplicateDesign('source'),
          throwsA(isA<ExperimentDuplicationException>()
              .having((e) => e.cleanupErrors, 'cleanup errors', isEmpty)));
      expect(
          (await experiments.loadExperiments()).map((e) => e.id), ['source']);
      expect(await plates.loadPlate('copy'), isNull);
      expect(jsonEncode((await plates.loadPlate('source'))!.toJson()),
          jsonEncode(sourcePlate.toJson()));
    });
  }

  test('reports cleanup failures instead of claiming the copy was removed',
      () async {
    experiments.failCopySave = true;
    plates.failCopyDelete = true;
    await expectLater(
        service.duplicateDesign('source'),
        throwsA(isA<ExperimentDuplicationException>()
            .having((e) => e.cleanupErrors.length, 'cleanup errors', 1)));
    expect((await experiments.loadExperiments()).map((e) => e.id), ['source']);
    expect(await plates.loadPlate('copy'), isNotNull);
    expect(await plates.loadPlate('source'), isNotNull);
  });

  test('a broken source Plate aborts without creating a copy', () async {
    await File('${root.path}/plates/source.json').writeAsString('{broken');
    await expectLater(
        service.duplicateDesign('source'), throwsA(isA<Exception>()));
    expect((await experiments.loadExperiments()).map((e) => e.id), ['source']);
    expect(await plates.loadPlate('copy'), isNull);
  });

  test('does not overwrite an existing destination Plate', () async {
    final existing =
        Plate(id: 'plate-copy', experimentId: 'copy', name: 'Existing');
    await plates.savePlate(existing);
    await expectLater(service.duplicateDesign('source'), throwsStateError);
    expect((await plates.loadPlate('copy'))!.name, 'Existing');
    expect((await experiments.loadExperiments()).map((e) => e.id), ['source']);
  });
}

class _ExperimentRepository extends FileExperimentRepository {
  _ExperimentRepository(String root) : super(rootDirectory: root);
  bool failCopySave = false;
  @override
  Future<void> saveExperiment(Experiment experiment) async {
    await super.saveExperiment(experiment);
    if (experiment.id == 'copy' && failCopySave) {
      throw StateError('experiment write failed');
    }
  }
}

class _PlateRepository extends FilePlateRepository {
  _PlateRepository(String root) : super(rootDirectory: root);
  bool failCopySave = false;
  bool failCopyDelete = false;
  @override
  Future<void> savePlate(Plate plate) async {
    await super.savePlate(plate);
    if (plate.experimentId == 'copy' && failCopySave) {
      throw StateError('plate write failed');
    }
  }

  @override
  Future<void> deletePlate(String experimentId) async {
    if (experimentId == 'copy' && failCopyDelete) {
      throw StateError('cleanup failed');
    }
    await super.deletePlate(experimentId);
  }
}

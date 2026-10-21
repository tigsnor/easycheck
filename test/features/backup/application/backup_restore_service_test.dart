import 'package:easycheck/features/plates/templates/data/plate_template_repository.dart';
import 'package:easycheck/features/plates/templates/domain/plate_template.dart';
import 'package:easycheck/features/backup/application/backup_restore_service.dart';
import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/experiments/data/experiment_repository.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/plates/data/plate_repository.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('merges a validated backup while preserving unrelated data', () async {
    final experiments = _MemoryExperimentRepository([
      _experiment('existing', 'Existing'),
      _experiment('unrelated', 'Unrelated'),
    ]);
    final plates = _MemoryPlateRepository({
      'existing': _plate('existing', 'Old plate'),
      'unrelated': _plate('unrelated', 'Unrelated plate'),
    });
    final service = BackupRestoreService(
      experimentRepository: experiments,
      plateRepository: plates,
    );

    await service.restore(
      _backup(
        experiments: [_experiment('existing', 'Restored')],
        plates: [_plate('existing', 'Restored plate')],
      ),
    );

    expect(experiments.byId('existing')!.title, 'Restored');
    expect(experiments.byId('unrelated')!.title, 'Unrelated');
    expect(plates.byExperimentId('existing')!.name, 'Restored plate');
    expect(plates.byExperimentId('unrelated')!.name, 'Unrelated plate');
  });

  test('rolls back all affected data when a plate save fails', () async {
    final experiments = _MemoryExperimentRepository([
      _experiment('existing', 'Before restore'),
    ]);
    final plates = _MemoryPlateRepository({
      'existing': _plate('existing', 'Before restore plate'),
    })
      ..failNextIncomingSave = true;
    final service = BackupRestoreService(
      experimentRepository: experiments,
      plateRepository: plates,
    );

    await expectLater(
      service.restore(
        _backup(
          experiments: [
            _experiment('existing', 'Incoming'),
            _experiment('new', 'New experiment'),
          ],
          plates: [
            _plate('existing', 'Incoming plate'),
            _plate('new', 'New plate'),
          ],
        ),
      ),
      throwsA(
        isA<BackupRestoreException>().having(
          (error) => error.rollbackCompleted,
          'rollbackCompleted',
          isTrue,
        ),
      ),
    );

    expect(experiments.byId('existing')!.title, 'Before restore');
    expect(experiments.byId('new'), isNull);
    expect(plates.byExperimentId('existing')!.name, 'Before restore plate');
    expect(plates.byExperimentId('new'), isNull);
  });

  test('merges user templates and preserves unrelated templates', () async {
    final templates = _MemoryTemplates(
        [_template('same', 'Old'), _template('other', 'Other')]);
    final service = BackupRestoreService(
        experimentRepository: _MemoryExperimentRepository([]),
        plateRepository: _MemoryPlateRepository({}),
        templateRepository: templates);
    await service.restore(EasyCheckBackup(
        schemaVersion: 2,
        exportedAt: DateTime.now(),
        experiments: [],
        plates: [],
        templates: [_template('same', 'Updated'), _template('new', 'New')]));
    expect(templates.items.map((t) => t.name),
        containsAll(['Updated', 'Other', 'New']));
    await service.restore(_backup(experiments: [], plates: []));
    expect(templates.items, hasLength(3));
  });

  test('template save failure rolls back experiments, plates and templates',
      () async {
    final experiments = _MemoryExperimentRepository([_experiment('e', 'Old')]);
    final plates = _MemoryPlateRepository({'e': _plate('e', 'Old plate')});
    final templates = _MemoryTemplates([_template('old', 'Old template')])
      ..failNext = true;
    await expectLater(
        BackupRestoreService(
                experimentRepository: experiments,
                plateRepository: plates,
                templateRepository: templates)
            .restore(EasyCheckBackup(
                schemaVersion: 2,
                exportedAt: DateTime.now(),
                experiments: [_experiment('e', 'Updated')],
                plates: [_plate('e', 'Updated plate')],
                templates: [_template('new', 'New')])),
        throwsA(isA<BackupRestoreException>()
            .having((e) => e.rollbackCompleted, 'rollback', isTrue)));
    expect(experiments.byId('e')!.title, 'Old');
    expect(plates.byExperimentId('e')!.name, 'Old plate');
    expect(templates.items.single.name, 'Old template');
  });

  test('rejects invalid references before changing repositories', () async {
    final experiments = _MemoryExperimentRepository(const []);
    final plates = _MemoryPlateRepository(const {});
    final service = BackupRestoreService(
      experimentRepository: experiments,
      plateRepository: plates,
    );

    await expectLater(
      service.restore(
        _backup(
          experiments: [_experiment('experiment-1', 'Experiment')],
          plates: [_plate('missing', 'Orphan plate')],
        ),
      ),
      throwsA(isA<FormatException>()),
    );

    expect(experiments.saveCount, 0);
    expect(plates.saveCount, 0);
  });
}

EasyCheckBackup _backup({
  required List<Experiment> experiments,
  required List<Plate> plates,
}) {
  return EasyCheckBackup(
    schemaVersion: 1,
    exportedAt: DateTime.utc(2026, 6, 12),
    experiments: experiments,
    plates: plates,
  );
}

Experiment _experiment(String id, String title) {
  return Experiment(
    id: id,
    title: title,
    createdAt: DateTime.utc(2026, 6, 12),
    updatedAt: DateTime.utc(2026, 6, 12),
  );
}

Plate _plate(String experimentId, String name) {
  return Plate(
    id: 'plate-$experimentId',
    experimentId: experimentId,
    name: name,
  );
}

class _MemoryExperimentRepository implements ExperimentRepository {
  _MemoryExperimentRepository(List<Experiment> experiments)
      : _experiments = [...experiments];

  final List<Experiment> _experiments;
  int saveCount = 0;

  Experiment? byId(String id) {
    for (final experiment in _experiments) {
      if (experiment.id == id) {
        return experiment;
      }
    }
    return null;
  }

  @override
  Future<void> deleteExperiment(String id) async {
    _experiments.removeWhere((experiment) => experiment.id == id);
  }

  @override
  Future<List<Experiment>> loadExperiments() async => [..._experiments];

  @override
  Future<void> saveExperiment(Experiment experiment) async {
    saveCount += 1;
    final index = _experiments.indexWhere((item) => item.id == experiment.id);
    if (index == -1) {
      _experiments.add(experiment);
    } else {
      _experiments[index] = experiment;
    }
  }
}

class _MemoryPlateRepository implements PlateRepository {
  _MemoryPlateRepository(Map<String, Plate> plates) : _plates = {...plates};

  final Map<String, Plate> _plates;
  int saveCount = 0;
  bool failNextIncomingSave = false;

  Plate? byExperimentId(String id) => _plates[id];

  @override
  Future<void> deletePlate(String experimentId) async {
    _plates.remove(experimentId);
  }

  @override
  Future<Plate?> loadPlate(String experimentId) async => _plates[experimentId];

  @override
  Future<void> savePlate(Plate plate) async {
    saveCount += 1;
    if (failNextIncomingSave && plate.name == 'Incoming plate') {
      failNextIncomingSave = false;
      throw StateError('simulated plate write failure');
    }
    _plates[plate.experimentId] = plate;
  }
}

PlateTemplate _template(String id, String name) =>
    PlateTemplate.fromPlate(id: id, name: name, plate: _plate('e', 'Plate'));

class _MemoryTemplates implements PlateTemplateRepository {
  _MemoryTemplates(this.items);
  final List<PlateTemplate> items;
  bool failNext = false;
  @override
  Future<List<PlateTemplate>> loadTemplates() async => [...items];
  @override
  Future<void> deleteTemplate(String id) async =>
      items.removeWhere((t) => t.id == id);
  @override
  Future<void> saveTemplate(PlateTemplate template) async {
    items.removeWhere((t) => t.id == template.id);
    items.add(template);
    if (failNext) {
      failNext = false;
      throw StateError('template write failed');
    }
  }
}

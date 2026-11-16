import 'package:easycheck/features/experiments/data/deleted_experiment_repository.dart';

class FakeDeletedExperimentRepository implements DeletedExperimentRepository {
  final entries = <DeletedExperiment>[];
  bool failSave = false;
  @override
  Future<List<DeletedExperiment>> load() async => List.of(entries);
  @override
  Future<void> save(DeletedExperiment entry) async {
    if (failSave) throw StateError('disk full');
    entries.removeWhere((e) => e.experiment.id == entry.experiment.id);
    entries.add(entry);
  }

  @override
  Future<void> remove(String id) async =>
      entries.removeWhere((e) => e.experiment.id == id);
}

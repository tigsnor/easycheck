import '../domain/experiment.dart';

abstract class ExperimentRepository {
  Future<List<Experiment>> loadExperiments();
  Future<void> saveExperiment(Experiment experiment);
  Future<void> deleteExperiment(String id);
}

import 'experiment.dart';

/// Read-only home projections. Empty project means explicitly unassigned;
/// null means every project. Filtering never changes the stored project name.
class ExperimentHomeOverview {
  static String projectOf(Experiment experiment) =>
      experiment.projectName?.trim() ?? '';

  static List<Experiment> filter(Iterable<Experiment> experiments,
      {String query = '', ExperimentStatus? status, String? project}) {
    final search = query.trim().toLowerCase();
    return experiments.where((experiment) {
      if (status != null && experiment.status != status) return false;
      if (project != null && projectOf(experiment) != project) return false;
      final haystack = [
        experiment.title,
        experiment.projectName ?? '',
        experiment.experimentType,
        experiment.researcher ?? '',
        experiment.cellCountLabel ?? '',
        experiment.notes,
        ...experiment.tags,
      ].join(' ').toLowerCase();
      return search.isEmpty || haystack.contains(search);
    }).toList();
  }

  static Iterable<({Experiment experiment, ExperimentTask task})> timedTasks(
      Iterable<Experiment> experiments) sync* {
    for (final experiment in experiments) {
      // Correction mode represents a review of historical execution records.
      if (experiment.isReadOnly ||
          experiment.status == ExperimentStatus.correcting) {
        continue;
      }
      for (final task in experiment.tasks) {
        if (!task.isFinished && task.dueAt != null) {
          yield (experiment: experiment, task: task);
        }
      }
    }
  }

  static List<({Experiment experiment, ExperimentTask task})> urgentTasks(
      Iterable<Experiment> experiments, DateTime now) {
    final cutoff = now.toUtc().add(const Duration(minutes: 30));
    final tasks = timedTasks(experiments)
        .where((item) => !item.task.dueAt!.isAfter(cutoff))
        .toList();
    tasks.sort((a, b) {
      final due = a.task.dueAt!.compareTo(b.task.dueAt!);
      if (due != 0) return due;
      final experiment = a.experiment.id.compareTo(b.experiment.id);
      return experiment != 0 ? experiment : a.task.id.compareTo(b.task.id);
    });
    return tasks;
  }
}

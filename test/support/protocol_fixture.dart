import 'package:easycheck/features/experiments/domain/experiment.dart';

Experiment protocolExperiment(
        {ExperimentStatus status = ExperimentStatus.planned,
        List<ExperimentTask>? tasks}) =>
    Experiment(
      id: 'e',
      title: 'Assay',
      status: status,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      notes: '기존 메모',
      tasks: tasks ??
          const [
            ExperimentTask(
                id: 'a',
                title: '시료 준비',
                plannedMinutes: 10,
                reminderEnabled: true),
            ExperimentTask(id: 'b', title: '흡광도 측정'),
            ExperimentTask(id: 'c', title: '정리', plannedMinutes: 5),
          ],
    );

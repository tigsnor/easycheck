import 'package:flutter_test/flutter_test.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';

void main() {
  group('Experiment serialization', () {
    test('round-trips all persisted fields', () {
      final experiment = Experiment(
        id: 'experiment-1',
        title: 'Drug A CCK-8',
        projectName: 'Cell viability',
        experimentType: 'CCK-8',
        researcher: 'EasyCheck',
        status: ExperimentStatus.planned,
        createdAt: DateTime.utc(2026, 6, 2, 9),
        updatedAt: DateTime.utc(2026, 6, 2, 10),
        notes: '2-fold dilution',
        cellCountLabel: 'hek293: 1×10^6/ml',
        tags: const ['CCK8', 'DoseResponse'],
      );

      final restored = Experiment.fromJson(experiment.toJson());

      expect(restored.id, experiment.id);
      expect(restored.title, experiment.title);
      expect(restored.projectName, experiment.projectName);
      expect(restored.experimentType, experiment.experimentType);
      expect(restored.researcher, experiment.researcher);
      expect(restored.status, experiment.status);
      expect(restored.createdAt, experiment.createdAt);
      expect(restored.updatedAt, experiment.updatedAt);
      expect(restored.notes, experiment.notes);
      expect(restored.cellCountLabel, experiment.cellCountLabel);
      expect(restored.tags, experiment.tags);
    });

    test('falls back to draft for unknown status names', () {
      final restored = Experiment.fromJson({
        'id': 'experiment-1',
        'title': 'Unknown status',
        'status': 'missing',
        'createdAt': DateTime.utc(2026, 6, 2).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 6, 2).toIso8601String(),
      });

      expect(restored.status, ExperimentStatus.draft);
    });
  });
}

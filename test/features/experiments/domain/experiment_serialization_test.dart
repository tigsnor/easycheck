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
        tasks: [
          ExperimentTask(
            id: 'task-1',
            title: 'Treatment 처리',
            isCompleted: true,
            startedAt: DateTime.utc(2026, 6, 2, 9),
            completedAt: DateTime.utc(2026, 6, 2, 9, 30),
          ),
        ],
        resources: const [
          ExperimentResource(
            id: 'resource-1',
            type: ExperimentResourceType.reagent,
            name: 'CCK-8',
            manufacturer: 'Dojindo',
            catalogOrModel: 'CK04',
            lotOrSerial: 'LOT-123',
            note: '개봉 2026-06-01',
          ),
        ],
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
      expect(restored.tasks, hasLength(1));
      expect(restored.tasks.single.title, 'Treatment 처리');
      expect(restored.tasks.single.isCompleted, isTrue);
      expect(restored.tasks.single.startedAt, DateTime.utc(2026, 6, 2, 9));
      expect(
        restored.tasks.single.completedAt,
        DateTime.utc(2026, 6, 2, 9, 30),
      );
      expect(restored.resources, hasLength(1));
      expect(restored.resources.single.type, ExperimentResourceType.reagent);
      expect(restored.resources.single.name, 'CCK-8');
      expect(restored.resources.single.manufacturer, 'Dojindo');
      expect(restored.resources.single.catalogOrModel, 'CK04');
      expect(restored.resources.single.lotOrSerial, 'LOT-123');
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

    test('migrates cell count labels from legacy notes', () {
      final restored = Experiment.fromJson({
        'id': 'experiment-1',
        'title': 'Legacy cell count',
        'createdAt': DateTime.utc(2026, 6, 2).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 6, 2).toIso8601String(),
        'notes': 'passage 4\n세포수: hek293: 1×10^6/ml',
      });

      expect(restored.cellCountLabel, 'hek293: 1×10^6/ml');
      expect(restored.notesWithoutCellCountLine, 'passage 4');
      expect(restored.tasks, isEmpty);
      expect(restored.resources, isEmpty);
    });
  });
}

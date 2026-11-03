import 'experiment.dart';
import 'protocol_editing.dart';

enum ProtocolPresetMode { keep, replace, append }

/// Editable checklists, not kit-specific SOPs or prescribed reaction times.
abstract final class ProtocolPresets {
  static List<String> titles(String type) => switch (type) {
        'CCK-8' => const [
            '세포 seeding',
            '세포 부착 incubation',
            'Treatment 처리',
            'CCK-8 시약 투입',
            '발색 incubation',
            'Plate reader 측정',
            '결과 파일 가져오기'
          ],
        'MTT' => const [
            '세포 seeding',
            '세포 부착 incubation',
            'Treatment 처리',
            'MTT 시약 투입',
            'Formazan 생성 반응',
            'Formazan 용해',
            'Plate reader 측정',
            '결과 파일 가져오기'
          ],
        'ELISA' => const [
            '시료 및 standard 준비',
            '시료 반응',
            '세척',
            'Detection reagent 반응',
            '기질 반응',
            'Plate reader 측정',
            '결과 파일 가져오기'
          ],
        _ => const ['실험 준비', 'Treatment 처리', '결과 측정', '결과 파일 가져오기'],
      };

  static List<ExperimentTask> initialTasks(String type) => [
        for (var i = 0; i < titles(type).length; i++)
          ExperimentTask(id: 'default-$i', title: titles(type)[i]),
      ];

  static bool canReplace(Experiment experiment) =>
      ProtocolEditing.canEdit(experiment) &&
      !ProtocolEditing.requiresReason(experiment);

  static List<ExperimentTask> apply(Experiment experiment, String type,
      ProtocolPresetMode mode, String idPrefix) {
    if (!ProtocolEditing.canEdit(experiment)) {
      throw const FormatException('완료·보관 실험은 잠금을 해제한 뒤 편집해주세요.');
    }
    if (mode == ProtocolPresetMode.keep) {
      return List.unmodifiable(experiment.tasks);
    }
    if (mode == ProtocolPresetMode.replace && !canReplace(experiment)) {
      throw const FormatException(
          '수행 후에는 기존 단계를 교체할 수 없습니다. 유지 또는 추가를 선택해주세요.');
    }
    final ids = experiment.tasks.map((t) => t.id).toSet();
    final used = <String>{};
    var counter = 0;
    ExperimentTask newTask(String title) {
      String id;
      do {
        id = '$idPrefix-${counter++}';
      } while (ids.contains(id));
      ids.add(id);
      return ExperimentTask(id: id, title: title);
    }

    final result = mode == ProtocolPresetMode.append
        ? [...experiment.tasks]
        : <ExperimentTask>[];
    for (final title in titles(type)) {
      final match = experiment.tasks
          .where((t) => t.title.trim() == title && !used.contains(t.id))
          .firstOrNull;
      if (match != null) {
        used.add(match.id);
        if (mode == ProtocolPresetMode.replace) result.add(match);
      } else {
        result.add(newTask(title));
      }
    }
    return ProtocolEditing.validate(experiment, result);
  }
}

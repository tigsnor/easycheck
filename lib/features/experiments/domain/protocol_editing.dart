import 'dart:convert';

import 'experiment.dart';

abstract final class ProtocolEditing {
  static bool hasExecution(ExperimentTask task) =>
      task.isCompleted ||
      task.startedAt != null ||
      task.completedAt != null ||
      task.executionHistory.isNotEmpty ||
      task.executionMetadata.toJson().values.any((value) => value != null);

  static bool canEdit(Experiment experiment) =>
      [ExperimentStatus.draft, ExperimentStatus.planned]
          .contains(experiment.status) &&
      !experiment.tasks.any(hasExecution);

  static List<ExperimentTask> validate(
      Experiment before, List<ExperimentTask> draft) {
    if (!canEdit(before)) {
      throw const FormatException('수행 기록이 없는 초안·계획 실험에서만 단계 구성을 편집할 수 있습니다.');
    }
    if (draft.isEmpty) throw const FormatException('단계는 최소 1개 유지해주세요.');
    final ids = <String>{};
    final original = {for (final task in before.tasks) task.id: task};
    for (final task in draft) {
      if (task.id.trim().isEmpty ||
          !ids.add(task.id) ||
          task.title.trim().isEmpty ||
          (task.title != task.title.trim() &&
              task.title != original[task.id]?.title) ||
          hasExecution(task)) {
        throw const FormatException('단계 이름·ID·실행 기록을 확인해주세요.');
      }
      ExperimentTask.fromJson(task.toJson());
      final old = original[task.id];
      if (old != null &&
          jsonEncode(old.copyWith(title: task.title).toJson()) !=
              jsonEncode(task.toJson())) {
        throw const FormatException('구성 편집에서는 기존 단계의 시간·알림 설정을 변경할 수 없습니다.');
      }
    }
    return List.unmodifiable(draft);
  }

  /// Existing task renames, removals or reorders must be saved before executing.
  /// A newly added task retains the existing immediate task-save workflow.
  static bool changesSavedDefinition(
      List<ExperimentTask> saved, List<ExperimentTask> draft) {
    final ids = saved.map((t) => t.id).toSet();
    return jsonEncode([
          for (final t in saved) [t.id, t.title]
        ]) !=
        jsonEncode([
          for (final t in draft)
            if (ids.contains(t.id)) [t.id, t.title]
        ]);
  }
}

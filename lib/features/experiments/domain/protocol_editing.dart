import 'dart:convert';

import 'experiment.dart';

abstract final class ProtocolEditing {
  static bool hasExecution(ExperimentTask task) =>
      task.isCompleted ||
      task.startedAt != null ||
      task.completedAt != null ||
      task.executionHistory.isNotEmpty ||
      task.executionMetadata.toJson().values.any((value) => value != null);

  static bool canEdit(Experiment experiment) => !experiment.isReadOnly;

  static bool requiresReason(Experiment experiment) =>
      experiment.status == ExperimentStatus.inProgress ||
      experiment.status == ExperimentStatus.correcting ||
      experiment.tasks.any(hasExecution);

  static List<ExperimentTask> validate(
      Experiment before, List<ExperimentTask> draft,
      {bool preserveSettings = true}) {
    if (!canEdit(before)) {
      throw const FormatException('완료·보관 실험은 잠금을 해제한 뒤 편집해주세요.');
    }
    if (draft.isEmpty) throw const FormatException('단계는 최소 1개 유지해주세요.');
    final ids = <String>{};
    final original = {for (final task in before.tasks) task.id: task};
    for (final task in draft) {
      final old = original[task.id];
      if (task.id.trim().isEmpty ||
          !ids.add(task.id) ||
          task.title.trim().isEmpty ||
          (task.title != task.title.trim() && task.title != old?.title) ||
          (old == null && hasExecution(task))) {
        throw const FormatException('단계 이름·ID·실행 기록을 확인해주세요.');
      }
      ExperimentTask.fromJson(task.toJson());
      if (old != null) {
        final allowed = preserveSettings
            ? old.copyWith(title: task.title)
            : old.copyWith(
                title: task.title,
                plannedMinutes: task.plannedMinutes,
                reminderEnabled: task.reminderEnabled);
        if (jsonEncode(allowed.toJson()) != jsonEncode(task.toJson())) {
          throw const FormatException('단계 구성 편집으로 기존 수행 기록을 바꿀 수 없습니다.');
        }
      }
    }
    if (before.tasks.any((t) => hasExecution(t) && !ids.contains(t.id))) {
      throw const FormatException('수행 기록이 있는 단계는 삭제할 수 없습니다. 단계 생략을 사용해주세요.');
    }
    return List.unmodifiable(draft);
  }

  /// New-only drafts retain immediate task saves before execution begins.
  static bool changesSavedDefinition(
      List<ExperimentTask> saved, List<ExperimentTask> draft,
      {bool includeAdditions = false}) {
    final ids = saved.map((t) => t.id).toSet();
    return jsonEncode([
          for (final t in saved) [t.id, t.title]
        ]) !=
        jsonEncode([
          for (final t in draft)
            if (includeAdditions || ids.contains(t.id)) [t.id, t.title]
        ]);
  }

  static ExperimentRevision revision(Experiment before,
      List<ExperimentTask> after, String reason, DateTime at) {
    final validated = validate(before, after, preserveSettings: false);
    if (reason.trim().isEmpty ||
        !changesSavedDefinition(before.tasks, after, includeAdditions: true)) {
      throw const FormatException('변경 내용과 사유가 필요합니다.');
    }
    return ExperimentRevision(
        id: 'protocol-${at.microsecondsSinceEpoch}-${before.revisions.length}',
        changedAt: at.toUtc(),
        summary: '단계 구성 변경',
        reason: reason.trim(),
        before: before.copyWith(revisions: []),
        protocolAfterTasks: validated);
  }

  static List<String> describe(
          List<ExperimentTask> before, List<ExperimentTask> after) =>
      [
        '변경 전 순서',
        for (var i = 0; i < before.length; i++) '${i + 1}. ${before[i].title}',
        '변경 후 순서',
        for (var i = 0; i < after.length; i++) '${i + 1}. ${after[i].title}',
        for (final task in before)
          if (!after.any((t) => t.id == task.id)) '삭제: ${task.title}',
        for (final task in after)
          if (!before.any((t) => t.id == task.id))
            '추가: ${task.title}'
          else if (before.firstWhere((t) => t.id == task.id).title !=
              task.title)
            '이름 변경: ${before.firstWhere((t) => t.id == task.id).title} → ${task.title}',
      ];
}

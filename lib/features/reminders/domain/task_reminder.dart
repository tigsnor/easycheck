import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../experiments/domain/experiment.dart';

const taskReminderPrefix = 'platenote-task:';
String taskReminderKey(String experimentId, String taskId) =>
    jsonEncode([experimentId, taskId]);

class TaskReminder {
  const TaskReminder(
      {required this.id,
      required this.key,
      required this.dueAt,
      required this.title,
      required this.body});
  final int id;
  final String key;
  final DateTime dueAt;
  final String title;
  final String body;
  String get payload => '$taskReminderPrefix${jsonEncode([
            key,
            dueAt.toUtc().toIso8601String(),
            title,
            body
          ])}';
}

/// Absolute UTC deadlines avoid DST/device-timezone reinterpretation.
List<TaskReminder> buildTaskReminders(
    List<Experiment> experiments, DateTime now,
    {bool includePast = false}) {
  final candidates = <(String, DateTime, String, String)>[];
  final keys = <String>{};
  for (final experiment in experiments) {
    if (experiment.status == ExperimentStatus.completed ||
        experiment.status == ExperimentStatus.archived) {
      continue;
    }
    for (final task in experiment.tasks) {
      final due = task.dueAt;
      if (!task.reminderEnabled ||
          task.isCompleted ||
          due == null ||
          (!includePast && !due.isAfter(now))) {
        continue;
      }
      final key = taskReminderKey(experiment.id, task.id);
      if (!keys.add(key)) {
        throw const FormatException('중복 단계 ID로 알림을 예약할 수 없습니다.');
      }
      candidates
          .add((key, due, experiment.title, '${task.title} 예정 시간이 되었습니다.'));
    }
  }
  candidates.sort((a, b) => a.$1.compareTo(b.$1));
  final ids = <int>{};
  final result = <TaskReminder>[];
  for (final c in candidates) {
    final bytes = sha256.convert(utf8.encode(c.$1)).bytes;
    var id =
        ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) &
            0x7fffffff;
    while (!ids.add(id)) {
      id = (id + 1) & 0x7fffffff;
    }
    result.add(
        TaskReminder(id: id, key: c.$1, dueAt: c.$2, title: c.$3, body: c.$4));
  }
  result.sort((a, b) {
    final date = a.dueAt.compareTo(b.dueAt);
    return date == 0 ? a.key.compareTo(b.key) : date;
  });
  return result;
}

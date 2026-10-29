import 'dart:convert';
import '../../experiments/domain/experiment.dart';
import 'task_reminder.dart';

/// Reads the existing notification format. A payload identifies a destination;
/// it never supplies experiment data or authorizes a state change.
class TaskReminderTarget {
  const TaskReminderTarget(
      {required this.experimentId,
      required this.taskId,
      required this.dueAt,
      required this.title,
      required this.body});
  final String experimentId;
  final String taskId;
  final DateTime dueAt;
  final String title;
  final String body;

  String get identity => jsonEncode(
      [experimentId, taskId, dueAt.toUtc().toIso8601String(), title, body]);

  static TaskReminderTarget? parse(String? payload) {
    if (payload == null ||
        payload.length > 32768 ||
        !payload.startsWith(taskReminderPrefix)) {
      return null;
    }
    try {
      final data = jsonDecode(payload.substring(taskReminderPrefix.length));
      if (data is! List ||
          data.length != 4 ||
          data.any((value) => value is! String)) {
        return null;
      }
      final key = jsonDecode(data[0] as String);
      if (key is! List ||
          key.length != 2 ||
          key.any((value) => value is! String || value.trim().isEmpty)) {
        return null;
      }
      final timestamp = data[1] as String;
      if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(timestamp)) return null;
      final due = DateTime.tryParse(timestamp);
      if (due == null) {
        return null;
      }
      return TaskReminderTarget(
          experimentId: key[0] as String,
          taskId: key[1] as String,
          dueAt: due.toUtc(),
          title: data[2] as String,
          body: data[3] as String);
    } on FormatException {
      return null;
    }
  }

  String message(Experiment experiment) {
    final task =
        experiment.tasks.where((task) => task.id == taskId).firstOrNull;
    if (task == null) {
      return '알림의 단계가 현재 노트에 없습니다. 현재 단계 목록을 확인하세요.';
    }
    if (experiment.isReadOnly) {
      return '완료·보관된 노트의 알림입니다. 현재 기록을 읽기 전용으로 표시합니다.';
    }
    if (experiment.status == ExperimentStatus.correcting) {
      return '정정 중인 노트의 이전 알림입니다. 현재 기록을 확인하세요.';
    }
    if (task.isCompleted) {
      return '이미 완료된 단계의 알림입니다. 저장된 완료 기록을 표시합니다.';
    }
    if (!task.reminderEnabled ||
        task.dueAt == null ||
        !task.dueAt!.isAtSameMomentAs(dueAt) ||
        experiment.title != title ||
        '${task.title} 예정 시간이 되었습니다.' != body) {
      return '알림 이후 단계나 예정 시간이 변경되었습니다. 현재 저장된 기록을 확인하세요.';
    }
    return '알림에서 연 단계입니다. 현재 기록을 확인한 뒤 완료 여부를 기록하세요.';
  }
}

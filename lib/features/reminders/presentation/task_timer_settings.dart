import 'package:flutter/material.dart';
import '../../experiments/domain/experiment.dart';

class TaskTimerSettings extends StatefulWidget {
  const TaskTimerSettings({super.key, required this.task});
  final ExperimentTask task;
  @override
  State<TaskTimerSettings> createState() => _TaskTimerSettingsState();
}

class _TaskTimerSettingsState extends State<TaskTimerSettings> {
  late final TextEditingController _minutes;
  late bool _reminder;
  String? _error;
  @override
  void initState() {
    super.initState();
    _minutes = TextEditingController(
        text: widget.task.plannedMinutes?.toString() ?? '');
    _reminder = widget.task.reminderEnabled;
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  void _apply() {
    final text = _minutes.text.trim();
    final value = int.tryParse(text);
    if ((text.isNotEmpty && (value == null || value < 1 || value > 43200)) ||
        (_reminder && value == null)) {
      setState(() => _error = '1~43200분의 정수를 입력하세요. 알림에는 예정 시간이 필요합니다.');
      return;
    }
    Navigator.pop(
        context,
        widget.task
            .copyWith(plannedMinutes: value, reminderEnabled: _reminder));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${widget.task.title} 예정 시간'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              key: const ValueKey('task-planned-minutes'),
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: '예정 시간 (분)',
                  hintText: '예: 30, 60, 1440',
                  errorText: _error)),
          SwitchListTile(
              key: const ValueKey('task-reminder-enabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('종료 알림'),
              value: _reminder,
              onChanged: (value) => setState(() => _reminder = value)),
          const Text(
              '적용 후 상단 저장 또는 이 단계의 시작·완료 저장을 해야 예약에 반영됩니다. 알림 권한은 실행 화면에서 허용하세요. Android 절전·집중 모드 등으로 알림이 지연되거나 소리가 나지 않을 수 있습니다.'),
          if (widget.task.startedAt != null)
            const Text(
                '진행 중인 단계는 기존 시작 시각을 기준으로 예정 시각이 바뀝니다. 이미 지난 시각은 다시 알리지 않습니다.'),
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(
                  context,
                  widget.task
                      .copyWith(plannedMinutes: null, reminderEnabled: false)),
              child: const Text('예정 시간 해제')),
          FilledButton(
              key: const ValueKey('apply-task-timer'),
              onPressed: _apply,
              child: const Text('적용')),
        ],
      );
}

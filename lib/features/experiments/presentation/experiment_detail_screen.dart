import 'package:flutter/material.dart';

import '../../plates/presentation/plate_editor_screen.dart';
import '../domain/experiment.dart';

class ExperimentDetailScreen extends StatefulWidget {
  const ExperimentDetailScreen({
    required this.experiment,
    required this.onChanged,
    super.key,
  });

  final Experiment experiment;
  final Future<void> Function(Experiment experiment) onChanged;

  @override
  State<ExperimentDetailScreen> createState() => _ExperimentDetailScreenState();
}

class _ExperimentDetailScreenState extends State<ExperimentDetailScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _projectController;
  late final TextEditingController _cellCountController;
  late final TextEditingController _notesController;
  late ExperimentStatus _status;
  late String _experimentType;
  late List<ExperimentTask> _tasks;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.experiment.title);
    _projectController = TextEditingController(
      text: widget.experiment.projectName ?? '',
    );
    _cellCountController = TextEditingController(
      text: widget.experiment.cellCountLabel ?? '',
    );
    _notesController = TextEditingController(
      text: widget.experiment.notesWithoutCellCountLine,
    );
    _status = widget.experiment.status;
    _experimentType = widget.experiment.experimentType;
    _tasks = widget.experiment.tasks.isEmpty
        ? _defaultTasks(widget.experiment.experimentType)
        : [...widget.experiment.tasks];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _projectController.dispose();
    _cellCountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('실험 노트'),
        actions: [TextButton(onPressed: _save, child: const Text('저장'))],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _titleController,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '실험 제목',
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _experimentType,
                      decoration: const InputDecoration(labelText: '실험 유형'),
                      items: const [
                        DropdownMenuItem(value: 'CCK-8', child: Text('CCK-8')),
                        DropdownMenuItem(value: 'MTT', child: Text('MTT')),
                        DropdownMenuItem(value: 'ELISA', child: Text('ELISA')),
                        DropdownMenuItem(
                          value: 'Dose-response',
                          child: Text('Dose-response'),
                        ),
                        DropdownMenuItem(
                          value: 'Custom',
                          child: Text('Custom'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _experimentType = value ?? 'Custom'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ExperimentStatus>(
                      initialValue: _status,
                      decoration: const InputDecoration(labelText: '상태'),
                      items: const [
                        DropdownMenuItem(
                          value: ExperimentStatus.draft,
                          child: Text('초안'),
                        ),
                        DropdownMenuItem(
                          value: ExperimentStatus.planned,
                          child: Text('계획됨'),
                        ),
                        DropdownMenuItem(
                          value: ExperimentStatus.inProgress,
                          child: Text('진행 중'),
                        ),
                        DropdownMenuItem(
                          value: ExperimentStatus.completed,
                          child: Text('완료'),
                        ),
                        DropdownMenuItem(
                          value: ExperimentStatus.archived,
                          child: Text('보관됨'),
                        ),
                      ],
                      onChanged: (value) => setState(
                        () => _status = value ?? ExperimentStatus.draft,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _projectController,
                      decoration: const InputDecoration(labelText: '프로젝트'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cellCountController,
                      decoration: const InputDecoration(
                        labelText: '세포수',
                        hintText: '예: hek293: 1×10^6/ml',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ExperimentChecklistCard(
              tasks: _tasks,
              onChanged: (tasks) => setState(() => _tasks = tasks),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: TextField(
                  controller: _notesController,
                  minLines: 8,
                  maxLines: 16,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '실험 조건, 세포주, 처리 시간, 관찰 내용을 메모하세요.',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saveAndOpenPlate,
              icon: const Icon(Icons.grid_on_rounded),
              label: const Text('96-well Plate 열기'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAndOpenPlate() async {
    if (!await _save(showMessage: false)) {
      return;
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlateEditorScreen(
          experimentId: widget.experiment.id,
          experimentTitle: _titleController.text.trim(),
        ),
      ),
    );
  }

  Future<bool> _save({bool showMessage = true}) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('실험 제목을 입력해주세요.')));
      return false;
    }

    await widget.onChanged(
      widget.experiment.copyWith(
        title: title,
        projectName: _projectController.text.trim().isEmpty
            ? null
            : _projectController.text.trim(),
        experimentType: _experimentType,
        status: _status,
        updatedAt: DateTime.now(),
        cellCountLabel: _cellCountController.text.trim().isEmpty
            ? null
            : _cellCountController.text.trim(),
        notes: _notesController.text.trim(),
        tasks: _tasks,
      ),
    );

    if (!mounted) {
      return true;
    }

    if (showMessage) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('실험 노트를 저장했습니다.')));
    }

    return true;
  }

  List<ExperimentTask> _defaultTasks(String experimentType) {
    final titles = switch (experimentType) {
      'CCK-8' || 'MTT' => const [
          '세포 seeding',
          '세포 부착 incubation',
          'Treatment 처리',
          'Assay reagent 투입',
          '발색 incubation',
          'Plate reader 측정',
          '결과 파일 가져오기',
        ],
      'ELISA' => const [
          '시료 및 standard 준비',
          '시료 반응',
          '세척',
          'Detection reagent 반응',
          '기질 반응',
          'Plate reader 측정',
          '결과 파일 가져오기',
        ],
      _ => const ['실험 준비', 'Treatment 처리', '결과 측정', '결과 파일 가져오기'],
    };
    return [
      for (var index = 0; index < titles.length; index++)
        ExperimentTask(id: 'default-$index', title: titles[index]),
    ];
  }
}

class _ExperimentChecklistCard extends StatelessWidget {
  const _ExperimentChecklistCard({
    required this.tasks,
    required this.onChanged,
  });

  final List<ExperimentTask> tasks;
  final ValueChanged<List<ExperimentTask>> onChanged;

  @override
  Widget build(BuildContext context) {
    final completedCount = tasks.where((task) => task.isCompleted).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '실험 실행 체크리스트',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  Text('$completedCount/${tasks.length} 완료'),
                ],
              ),
            ),
            const SizedBox(height: 4),
            for (var index = 0; index < tasks.length; index++)
              CheckboxListTile(
                key: ValueKey('experiment-task-${tasks[index].id}'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  tasks[index].title,
                  style: TextStyle(
                    decoration: tasks[index].isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                subtitle: tasks[index].completedAt == null
                    ? null
                    : Text(_completedAtLabel(tasks[index].completedAt!)),
                value: tasks[index].isCompleted,
                onChanged: (value) {
                  final updated = [...tasks];
                  updated[index] = tasks[index].copyWith(
                    isCompleted: value ?? false,
                    completedAt: value == true ? DateTime.now() : null,
                  );
                  onChanged(updated);
                },
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _addTask(context),
                icon: const Icon(Icons.add),
                label: const Text('단계 추가'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addTask(BuildContext context) async {
    var draftTitle = '';
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('실험 단계 추가'),
        content: TextField(
          key: const ValueKey('new-experiment-task-field'),
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: '예: 450 nm 흡광도 측정'),
          onChanged: (value) => draftTitle = value,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(context).pop(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              if (draftTitle.trim().isNotEmpty) {
                Navigator.of(context).pop(draftTitle.trim());
              }
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
    if (title == null || !context.mounted) return;
    onChanged([
      ...tasks,
      ExperimentTask(
        id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
      ),
    ]);
  }

  String _completedAtLabel(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}.${twoDigits(value.month)}.${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)} 완료';
  }
}

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
  final ValueChanged<Experiment> onChanged;

  @override
  State<ExperimentDetailScreen> createState() => _ExperimentDetailScreenState();
}

class _ExperimentDetailScreenState extends State<ExperimentDetailScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _projectController;
  late final TextEditingController _notesController;
  late ExperimentStatus _status;
  late String _experimentType;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.experiment.title);
    _projectController =
        TextEditingController(text: widget.experiment.projectName ?? '');
    _notesController = TextEditingController(text: widget.experiment.notes);
    _status = widget.experiment.status;
    _experimentType = widget.experiment.experimentType;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _projectController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('실험 노트'),
        actions: [
          TextButton(
            onPressed: () => _save(),
            child: const Text('저장'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _titleController,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
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
                            child: Text('Dose-response')),
                        DropdownMenuItem(
                            value: 'Custom', child: Text('Custom')),
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
                            value: ExperimentStatus.draft, child: Text('초안')),
                        DropdownMenuItem(
                            value: ExperimentStatus.planned,
                            child: Text('계획됨')),
                        DropdownMenuItem(
                            value: ExperimentStatus.inProgress,
                            child: Text('진행 중')),
                        DropdownMenuItem(
                            value: ExperimentStatus.completed,
                            child: Text('완료')),
                        DropdownMenuItem(
                            value: ExperimentStatus.archived,
                            child: Text('보관됨')),
                      ],
                      onChanged: (value) => setState(
                          () => _status = value ?? ExperimentStatus.draft),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _projectController,
                      decoration: const InputDecoration(labelText: '프로젝트'),
                    ),
                  ],
                ),
              ),
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

  void _saveAndOpenPlate() {
    if (!_save(showMessage: false)) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlateEditorScreen(
          experimentTitle: _titleController.text.trim(),
        ),
      ),
    );
  }

  bool _save({bool showMessage = true}) {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('실험 제목을 입력해주세요.')),
      );
      return false;
    }

    widget.onChanged(
      widget.experiment.copyWith(
        title: title,
        projectName: _projectController.text.trim().isEmpty
            ? null
            : _projectController.text.trim(),
        experimentType: _experimentType,
        status: _status,
        notes: _notesController.text.trim(),
      ),
    );

    if (showMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('실험 노트를 저장했습니다.')),
      );
    }

    return true;
  }
}

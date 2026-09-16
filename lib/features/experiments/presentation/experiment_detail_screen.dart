import 'dart:async';
import 'dart:convert';

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
  late final TextEditingController _researcherController;
  late final TextEditingController _notesController;
  late ExperimentStatus _status;
  late String _experimentType;
  late List<ExperimentTask> _tasks;
  late List<ExperimentResource> _resources;
  late Experiment _persistedExperiment;
  late bool _isLocked;
  String? _editReason;
  late String _savedFingerprint;
  bool _isSaving = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _persistedExperiment = widget.experiment;
    _isLocked = widget.experiment.status == ExperimentStatus.completed;
    _titleController = TextEditingController(text: widget.experiment.title);
    _projectController = TextEditingController(
      text: widget.experiment.projectName ?? '',
    );
    _cellCountController = TextEditingController(
      text: widget.experiment.cellCountLabel ?? '',
    );
    _researcherController = TextEditingController(
      text: widget.experiment.researcher ?? '',
    );
    _notesController = TextEditingController(
      text: widget.experiment.notesWithoutCellCountLine,
    );
    _status = widget.experiment.status;
    _experimentType = widget.experiment.experimentType;
    _tasks = widget.experiment.tasks.isEmpty
        ? _defaultTasks(widget.experiment.experimentType)
        : [...widget.experiment.tasks];
    _resources = [...widget.experiment.resources];
    for (final controller in [
      _titleController,
      _projectController,
      _cellCountController,
      _researcherController,
      _notesController,
    ]) {
      controller.addListener(_onFormChanged);
    }
    _savedFingerprint = _fingerprint();
  }

  @override
  void dispose() {
    for (final controller in [
      _titleController,
      _projectController,
      _cellCountController,
      _researcherController,
      _notesController,
    ]) {
      controller.removeListener(_onFormChanged);
    }
    _titleController.dispose();
    _projectController.dispose();
    _cellCountController.dispose();
    _researcherController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop || (!_hasUnsavedChanges && !_isSaving),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isSaving) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('실험 노트'),
          actions: [
            if (_isLocked)
              TextButton(
                onPressed: _requestUnlock,
                child: const Text('수정 잠금 해제'),
              )
            else
              TextButton(
                onPressed: _isSaving ? null : _save,
                child: Text(_isSaving ? '저장 중…' : '저장'),
              ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_hasUnsavedChanges) ...[
                const _UnsavedChangesBanner(),
                const SizedBox(height: 12),
              ],
              if (_isLocked) ...[
                const _CompletionLockBanner(),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _titleController,
                enabled: !_isLocked,
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
                          DropdownMenuItem(
                            value: 'CCK-8',
                            child: Text('CCK-8'),
                          ),
                          DropdownMenuItem(value: 'MTT', child: Text('MTT')),
                          DropdownMenuItem(
                            value: 'ELISA',
                            child: Text('ELISA'),
                          ),
                          DropdownMenuItem(
                            value: 'Dose-response',
                            child: Text('Dose-response'),
                          ),
                          DropdownMenuItem(
                            value: 'Custom',
                            child: Text('Custom'),
                          ),
                        ],
                        onChanged: _isLocked
                            ? null
                            : (value) => setState(
                                () => _experimentType = value ?? 'Custom',
                              ),
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
                        onChanged: _isLocked
                            ? null
                            : (value) => setState(
                                () => _status = value ?? ExperimentStatus.draft,
                              ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _projectController,
                        enabled: !_isLocked,
                        decoration: const InputDecoration(labelText: '프로젝트'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _researcherController,
                        enabled: !_isLocked,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '담당자',
                          hintText: '예: 홍길동',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _cellCountController,
                        enabled: !_isLocked,
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
                enabled: !_isLocked,
                onChanged: (tasks) => setState(() => _tasks = tasks),
              ),
              const SizedBox(height: 16),
              _ExperimentResourcesCard(
                resources: _resources,
                enabled: !_isLocked,
                onChanged: (resources) =>
                    setState(() => _resources = resources),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: TextField(
                    controller: _notesController,
                    enabled: !_isLocked,
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
              if (_persistedExperiment.completedAt != null ||
                  _persistedExperiment.revisions.isNotEmpty) ...[
                _ExperimentHistoryCard(experiment: _persistedExperiment),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                onPressed: _isLocked
                    ? () => _openPlate(readOnly: true)
                    : _saveAndOpenPlate,
                icon: const Icon(Icons.grid_on_rounded),
                label: Text(
                  _isLocked ? '96-well Plate 보기' : '96-well Plate 열기',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasUnsavedChanges =>
      !_isLocked &&
      (_editReason != null || _fingerprint() != _savedFingerprint);

  String _fingerprint() => jsonEncode({
    'title': _titleController.text.trim(),
    'project': _projectController.text.trim(),
    'cellCount': _cellCountController.text.trim(),
    'researcher': _researcherController.text.trim(),
    'notes': _notesController.text.trim(),
    'status': _status.name,
    'experimentType': _experimentType,
    'tasks': _tasks.map((task) => task.toJson()).toList(),
    'resources': _resources.map((resource) => resource.toJson()).toList(),
  });

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmExit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final action = await showDialog<_ExperimentExitAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('저장하지 않은 변경이 있습니다'),
        content: const Text('저장한 뒤 나가거나, 변경 내용을 버리고 나갈 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('계속 편집'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _ExperimentExitAction.discard),
            child: const Text('저장하지 않고 나가기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _ExperimentExitAction.save),
            child: const Text('저장 후 나가기'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == _ExperimentExitAction.save &&
        !await _save(showMessage: false)) {
      return;
    }
    if (mounted) {
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    }
  }

  Future<void> _saveAndOpenPlate() async {
    if (!await _save(showMessage: false)) {
      return;
    }

    if (!mounted) {
      return;
    }

    await _openPlate(readOnly: false);
  }

  Future<void> _openPlate({required bool readOnly}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlateEditorScreen(
          experimentId: widget.experiment.id,
          experimentTitle: _titleController.text.trim(),
          readOnly: readOnly,
        ),
      ),
    );
  }

  Future<bool> _save({bool showMessage = true}) async {
    if (_isSaving) return false;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('실험 제목을 입력해주세요.')));
      return false;
    }

    setState(() => _isSaving = true);
    final now = DateTime.now();
    final revisions = [..._persistedExperiment.revisions];
    DateTime? completedAt = _persistedExperiment.completedAt;
    if (_persistedExperiment.status != ExperimentStatus.completed &&
        _status == ExperimentStatus.completed) {
      completedAt ??= now;
      revisions.add(
        ExperimentRevision(
          id: 'revision-${now.microsecondsSinceEpoch}',
          changedAt: now,
          summary: '실험 완료',
        ),
      );
    }
    if (_editReason != null) {
      revisions.add(
        ExperimentRevision(
          id: 'revision-${now.microsecondsSinceEpoch}-edit',
          changedAt: now,
          summary: '완료 후 수정',
          reason: _editReason!,
        ),
      );
    }
    final updated = _persistedExperiment.copyWith(
      title: title,
      projectName: _projectController.text.trim().isEmpty
          ? null
          : _projectController.text.trim(),
      experimentType: _experimentType,
      status: _status,
      updatedAt: now,
      researcher: _researcherController.text.trim().isEmpty
          ? null
          : _researcherController.text.trim(),
      cellCountLabel: _cellCountController.text.trim().isEmpty
          ? null
          : _cellCountController.text.trim(),
      notes: _notesController.text.trim(),
      tasks: _tasks,
      resources: _resources,
      completedAt: completedAt,
      revisions: revisions,
    );
    try {
      await widget.onChanged(updated);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('실험 노트를 저장하지 못했습니다: $error')));
      }
      return false;
    }
    _persistedExperiment = updated;
    _editReason = null;
    _savedFingerprint = _fingerprint();
    if (mounted) {
      setState(() {
        _isSaving = false;
        if (_status == ExperimentStatus.completed) _isLocked = true;
      });
    }

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

  Future<void> _requestUnlock() async {
    final controller = TextEditingController();
    String? errorText;
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('완료 노트 수정'),
          content: TextField(
            key: const ValueKey('completion-edit-reason-field'),
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '수정 사유',
              hintText: '예: 시약 Lot 번호 정정',
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(() => errorText = '수정 사유를 입력해주세요.');
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('수정 시작'),
            ),
          ],
        ),
      ),
    );
    if (reason != null && mounted) {
      setState(() {
        _isLocked = false;
        _editReason = reason;
      });
    }
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

enum _ExperimentExitAction { save, discard }

class _UnsavedChangesBanner extends StatelessWidget {
  const _UnsavedChangesBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('unsaved-experiment-changes'),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.edit_note_outlined),
            SizedBox(width: 8),
            Expanded(child: Text('저장하지 않은 변경이 있습니다.')),
          ],
        ),
      ),
    );
  }
}

class _CompletionLockBanner extends StatelessWidget {
  const _CompletionLockBanner();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: const ListTile(
        leading: Icon(Icons.lock_outline),
        title: Text('완료된 실험 노트입니다'),
        subtitle: Text('내용 변경과 Plate 편집을 시작하려면 수정 사유를 남기고 잠금을 해제하세요.'),
      ),
    );
  }
}

class _ExperimentHistoryCard extends StatelessWidget {
  const _ExperimentHistoryCard({required this.experiment});

  final Experiment experiment;

  @override
  Widget build(BuildContext context) {
    final revisions = experiment.revisions.reversed.toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '변경 이력',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (experiment.completedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('최초 완료: ${_historyDate(experiment.completedAt!)}'),
              ),
            for (final revision in revisions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: Text(revision.summary),
                subtitle: Text(
                  revision.reason.isEmpty
                      ? _historyDate(revision.changedAt)
                      : '${_historyDate(revision.changedAt)} · ${revision.reason}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _historyDate(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}.${twoDigits(value.month)}.${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
  }
}

class _ExperimentChecklistCard extends StatefulWidget {
  const _ExperimentChecklistCard({
    required this.tasks,
    required this.onChanged,
    required this.enabled,
  });

  final List<ExperimentTask> tasks;
  final ValueChanged<List<ExperimentTask>> onChanged;
  final bool enabled;

  @override
  State<_ExperimentChecklistCard> createState() =>
      _ExperimentChecklistCardState();
}

class _ExperimentResourcesCard extends StatelessWidget {
  const _ExperimentResourcesCard({
    required this.resources,
    required this.onChanged,
    required this.enabled,
  });

  final List<ExperimentResource> resources;
  final ValueChanged<List<ExperimentResource>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '시약 및 장비',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (resources.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Lot 번호와 사용 장비를 기록하면 결과 차이를 추적하기 쉬워집니다.'),
              ),
            for (var index = 0; index < resources.length; index++)
              ListTile(
                key: ValueKey('experiment-resource-${resources[index].id}'),
                leading: Icon(
                  resources[index].type == ExperimentResourceType.reagent
                      ? Icons.science_outlined
                      : Icons.precision_manufacturing_outlined,
                ),
                title: Text(resources[index].name),
                subtitle: Text(_resourceDetails(resources[index])),
                trailing: IconButton(
                  tooltip: '기록 삭제',
                  onPressed: enabled
                      ? () {
                          final updated = [...resources]..removeAt(index);
                          onChanged(updated);
                        }
                      : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: enabled ? () => _addResource(context) : null,
                icon: const Icon(Icons.add),
                label: const Text('시약·장비 추가'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _resourceDetails(ExperimentResource resource) {
    final details = <String>[
      resource.type == ExperimentResourceType.reagent ? '시약' : '장비',
      if (resource.manufacturer.isNotEmpty) resource.manufacturer,
      if (resource.catalogOrModel.isNotEmpty)
        '${resource.type == ExperimentResourceType.reagent ? 'Cat.' : 'Model'} ${resource.catalogOrModel}',
      if (resource.lotOrSerial.isNotEmpty)
        '${resource.type == ExperimentResourceType.reagent ? 'Lot' : 'S/N'} ${resource.lotOrSerial}',
      if (resource.note.isNotEmpty) resource.note,
    ];
    return details.join(' · ');
  }

  Future<void> _addResource(BuildContext context) async {
    final resource = await showDialog<ExperimentResource>(
      context: context,
      builder: (_) => const _ResourceEditorDialog(),
    );
    if (resource == null || !context.mounted) return;
    onChanged([...resources, resource]);
  }
}

class _ResourceEditorDialog extends StatefulWidget {
  const _ResourceEditorDialog();

  @override
  State<_ResourceEditorDialog> createState() => _ResourceEditorDialogState();
}

class _ResourceEditorDialogState extends State<_ResourceEditorDialog> {
  final _nameController = TextEditingController();
  final _manufacturerController = TextEditingController();
  final _catalogController = TextEditingController();
  final _lotController = TextEditingController();
  final _noteController = TextEditingController();
  ExperimentResourceType _type = ExperimentResourceType.reagent;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _manufacturerController.dispose();
    _catalogController.dispose();
    _lotController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReagent = _type == ExperimentResourceType.reagent;
    return AlertDialog(
      title: const Text('시약·장비 기록'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<ExperimentResourceType>(
              segments: const [
                ButtonSegment(
                  value: ExperimentResourceType.reagent,
                  label: Text('시약'),
                  icon: Icon(Icons.science_outlined),
                ),
                ButtonSegment(
                  value: ExperimentResourceType.equipment,
                  label: Text('장비'),
                  icon: Icon(Icons.precision_manufacturing_outlined),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (values) =>
                  setState(() => _type = values.single),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('resource-name-field'),
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: isReagent ? '시약명' : '장비명',
                errorText: _errorText,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _manufacturerController,
              decoration: const InputDecoration(labelText: '제조사'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _catalogController,
              decoration: InputDecoration(
                labelText: isReagent ? 'Catalog number' : 'Model',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('resource-lot-field'),
              controller: _lotController,
              decoration: InputDecoration(
                labelText: isReagent ? 'Lot number' : 'Serial number',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: '메모'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _save, child: const Text('추가')),
      ],
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = '이름을 입력해주세요.');
      return;
    }
    Navigator.of(context).pop(
      ExperimentResource(
        id: 'resource-${DateTime.now().microsecondsSinceEpoch}',
        type: _type,
        name: name,
        manufacturer: _manufacturerController.text.trim(),
        catalogOrModel: _catalogController.text.trim(),
        lotOrSerial: _lotController.text.trim(),
        note: _noteController.text.trim(),
      ),
    );
  }
}

class _ExperimentChecklistCardState extends State<_ExperimentChecklistCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _ExperimentChecklistCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    final hasRunningTask = widget.tasks.any(
      (task) => task.startedAt != null && !task.isCompleted,
    );
    if (hasRunningTask && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!hasRunningTask && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.tasks;
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
                    ? _runningLabel(tasks[index])
                    : Text(_completedLabel(tasks[index])),
                secondary: _TaskTimerButton(
                  task: tasks[index],
                  onPressed: widget.enabled ? () => _toggleTimer(index) : null,
                ),
                value: tasks[index].isCompleted,
                onChanged: widget.enabled
                    ? (value) {
                        final updated = [...tasks];
                        final now = DateTime.now();
                        updated[index] = tasks[index].copyWith(
                          isCompleted: value ?? false,
                          startedAt: value == true
                              ? tasks[index].startedAt ?? now
                              : tasks[index].startedAt,
                          completedAt: value == true ? now : null,
                        );
                        widget.onChanged(updated);
                      }
                    : null,
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.enabled ? () => _addTask(context) : null,
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
    widget.onChanged([
      ...widget.tasks,
      ExperimentTask(
        id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
      ),
    ]);
  }

  void _toggleTimer(int index) {
    final task = widget.tasks[index];
    final now = DateTime.now();
    final updated = [...widget.tasks];
    updated[index] = task.startedAt == null
        ? task.copyWith(startedAt: now)
        : task.copyWith(isCompleted: true, completedAt: now);
    widget.onChanged(updated);
  }

  Widget? _runningLabel(ExperimentTask task) {
    final startedAt = task.startedAt;
    if (startedAt == null) return null;
    return Text(
      '${_dateTimeLabel(startedAt)} 시작 · ${_durationLabel(DateTime.now().difference(startedAt))} 경과',
    );
  }

  String _completedLabel(ExperimentTask task) {
    final completedAt = task.completedAt!;
    final startedAt = task.startedAt;
    if (startedAt == null) return '${_dateTimeLabel(completedAt)} 완료';
    return '${_dateTimeLabel(completedAt)} 완료 · ${_durationLabel(completedAt.difference(startedAt))}';
  }

  String _dateTimeLabel(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}.${twoDigits(value.month)}.${twoDigits(value.day)} ${twoDigits(value.hour)}:${twoDigits(value.minute)}';
  }

  String _durationLabel(Duration duration) {
    final safeSeconds = duration.isNegative ? 0 : duration.inSeconds;
    final hours = safeSeconds ~/ 3600;
    final minutes = (safeSeconds % 3600) ~/ 60;
    final seconds = safeSeconds % 60;
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}'
        : '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}

class _TaskTimerButton extends StatelessWidget {
  const _TaskTimerButton({required this.task, required this.onPressed});

  final ExperimentTask task;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (task.isCompleted) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    return TextButton(
      key: ValueKey('experiment-task-timer-${task.id}'),
      onPressed: onPressed,
      child: Text(task.startedAt == null ? '시작' : '완료'),
    );
  }
}

import '../../reminders/application/task_reminder_coordinator.dart';
import '../../reminders/presentation/reminder_status_card.dart';
import '../../reminders/presentation/task_timer_settings.dart';
import 'widgets/experiment_result_summary.dart';
import 'widgets/experiment_revision_screen.dart';
import '../../../shared/models/well_position.dart';
import 'experiment_completion_screen.dart';
import '../../attachments/data/attachment_file_store.dart';
import '../../attachments/data/attachment_exchange_service.dart';
import '../../attachments/presentation/experiment_attachments_screen.dart';
import '../../plates/data/file_plate_repository.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../shared/presentation/save_status_indicator.dart';
import '../../../shared/services/document_exchange_service.dart';
import '../../plates/data/plate_repository.dart';
import '../../plates/templates/data/plate_template_repository.dart';
import '../../plates/presentation/plate_editor_screen.dart';
import '../domain/experiment.dart';

class ExperimentDetailScreen extends StatefulWidget {
  const ExperimentDetailScreen({
    required this.experiment,
    required this.onChanged,
    this.plateRepository,
    this.reminders,
    this.plateTemplateRepository,
    this.documentExchangeService,
    this.attachmentFileStore = const FileAttachmentFileStore(),
    this.attachmentExchange = const PlatformAttachmentExchangeService(),
    super.key,
  });

  final Experiment experiment;
  final Future<void> Function(Experiment experiment) onChanged;
  final PlateRepository? plateRepository;
  final TaskReminderCoordinator? reminders;
  final PlateTemplateRepository? plateTemplateRepository;
  final DocumentExchangeService? documentExchangeService;
  final AttachmentFileStore attachmentFileStore;
  final AttachmentExchangeService attachmentExchange;

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
  String _pendingCorrectionReason = '';
  bool get _isCorrecting =>
      _persistedExperiment.status == ExperimentStatus.correcting;
  bool get _editingEnabled =>
      !_isLocked &&
      !(_isSaving &&
          (_isCorrecting ||
              _status == ExperimentStatus.completed ||
              _status == ExperimentStatus.archived));
  late String _savedFingerprint;
  bool _isSaving = false;
  bool _allowPop = false;
  DateTime? _lastSavedAt;
  Object? _saveError;
  String? _titleError;
  String _completionReviewNote = '';
  late int _section;
  int _resultSummaryVersion = 0;

  @override
  void initState() {
    super.initState();
    _section = switch (widget.experiment.status) {
      ExperimentStatus.inProgress => 1,
      ExperimentStatus.completed ||
      ExperimentStatus.archived ||
      ExperimentStatus.correcting =>
        2,
      _ => 0,
    };
    _persistedExperiment = widget.experiment;
    _lastSavedAt = widget.experiment.updatedAt;
    _isLocked = widget.experiment.isReadOnly;
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
    _tasks = widget.experiment.tasks.isEmpty &&
            !widget.experiment.isReadOnly &&
            widget.experiment.status != ExperimentStatus.correcting
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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('실험 노트', maxLines: 1, overflow: TextOverflow.ellipsis),
              SaveStatusIndicator(
                status: _saveStatus,
                savedAt: _lastSavedAt,
                compact: true,
              ),
            ],
          ),
          actions: [
            IconButton(
                key: const ValueKey('open-experiment-attachments'),
                tooltip:
                    '사진·원본 파일 (${_persistedExperiment.attachments.length})',
                onPressed: _isSaving ? null : _openAttachments,
                icon: const Icon(Icons.attach_file)),
            if (_isLocked)
              TextButton(
                onPressed: _isSaving
                    ? null
                    : _persistedExperiment.status == ExperimentStatus.archived
                        ? _restoreArchive
                        : _requestUnlock,
                child: Text(_isSaving
                    ? '저장 중…'
                    : _persistedExperiment.status == ExperimentStatus.archived
                        ? '보관 해제'
                        : '수정 잠금 해제'),
              )
            else
              TextButton(
                onPressed: _isSaving ? null : _save,
                child: Text(_isSaving ? '저장 중…' : '저장'),
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _section,
          onDestinationSelected: _isSaving ? null : _selectSection,
          destinations: const [
            NavigationDestination(
                key: ValueKey('experiment-section-design'),
                icon: Icon(Icons.edit_note),
                label: '설계'),
            NavigationDestination(
                key: ValueKey('experiment-section-execution'),
                icon: Icon(Icons.play_circle_outline),
                label: '실행'),
            NavigationDestination(
                key: ValueKey('experiment-section-results'),
                icon: Icon(Icons.analytics_outlined),
                label: '결과'),
          ],
        ),
        body: SafeArea(
          child: ListView(
            key: PageStorageKey('experiment-section-$_section'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(20),
            children: [
              if (_hasUnsavedChanges || _saveError != null) ...[
                SaveStatusIndicator(
                  status: _saveStatus,
                  savedAt: _lastSavedAt,
                  onRetry: _saveError == null ? null : () => _save(),
                ),
                const SizedBox(height: 12),
              ],
              if (_isLocked) ...[
                _CompletionLockBanner(
                    archived: _persistedExperiment.status ==
                        ExperimentStatus.archived),
                const SizedBox(height: 12),
              ],
              if (_isCorrecting) ...[
                const Card(
                    child: ListTile(
                        leading: Icon(Icons.edit_note),
                        title: Text('정정 중 · 재검토 필요'),
                        subtitle: Text(
                            '저장 후에도 정정을 이어갈 수 있습니다. 결과 탭에서 재검토 후 완료하세요. 정정 중에는 단계 종료 알림을 예약하지 않습니다. 새 실험은 복사본에서 시작하세요.'))),
                const SizedBox(height: 12),
              ],
              if (_section != 0) ...[
                Text(_titleController.text,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
              ],
              ...switch (_section) {
                0 => _designContent(),
                1 => _executionContent(),
                _ => _resultsContent(),
              },
            ],
          ),
        ),
      ),
    );
  }

  void _selectSection(int index) {
    if (_isSaving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _section = index);
  }

  List<Widget> _designContent() => [
        TextField(
          controller: _titleController,
          enabled: _editingEnabled,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: '실험 제목',
            errorText: _titleError,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
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
                  onChanged: !_editingEnabled
                      ? null
                      : (value) => setState(
                            () => _experimentType = value ?? 'Custom',
                          ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ExperimentStatus>(
                  key: ValueKey('experiment-status-${_status.name}'),
                  isExpanded: true,
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: '상태'),
                  items: [
                    if (_isCorrecting)
                      const DropdownMenuItem(
                          value: ExperimentStatus.correcting,
                          child: Text('정정 중 · 재검토 필요')),
                    const DropdownMenuItem(
                      value: ExperimentStatus.draft,
                      child: Text('초안'),
                    ),
                    const DropdownMenuItem(
                      value: ExperimentStatus.planned,
                      child: Text('계획됨'),
                    ),
                    const DropdownMenuItem(
                      value: ExperimentStatus.inProgress,
                      child: Text('진행 중'),
                    ),
                    const DropdownMenuItem(
                      value: ExperimentStatus.completed,
                      child: Text('완료'),
                    ),
                    const DropdownMenuItem(
                      value: ExperimentStatus.archived,
                      child: Text('보관됨'),
                    ),
                  ],
                  onChanged: (_isLocked || _isSaving || _isCorrecting)
                      ? null
                      : (value) => setState(
                            () => _status = value ?? ExperimentStatus.draft,
                          ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _projectController,
                  enabled: _editingEnabled,
                  decoration: const InputDecoration(labelText: '프로젝트'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _researcherController,
                  enabled: _editingEnabled,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '담당자',
                    hintText: '예: 홍길동',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cellCountController,
                  enabled: _editingEnabled,
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
        _ExperimentResourcesCard(
          resources: _resources,
          enabled: _editingEnabled,
          onChanged: (resources) => setState(() => _resources = resources),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed:
              _isLocked ? () => _openPlate(readOnly: true) : _saveAndOpenPlate,
          icon: const Icon(Icons.grid_on_rounded),
          label: Text(
            _isLocked ? '96-well Plate 보기' : '96-well Plate 열기',
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: () => _selectSection(1),
            icon: const Icon(Icons.play_arrow),
            label: const Text('실행 단계로 이동')),
      ];

  List<Widget> _executionContent() => [
        _ExperimentChecklistCard(
          tasks: _tasks,
          enabled: _editingEnabled && !_isSaving,
          onChanged: (tasks) => setState(() => _tasks = tasks),
        ),
        const SizedBox(height: 16),
        if (widget.reminders != null) ...[
          ReminderStatusCard(coordinator: widget.reminders!),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: TextField(
              controller: _notesController,
              enabled: _editingEnabled,
              minLines: 8,
              maxLines: 16,
              decoration: const InputDecoration(
                border: InputBorder.none,
                labelText: '실행·관찰 메모',
                hintText: '실험 조건, 세포주, 처리 시간, 관찰 내용을 메모하세요.',
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
            onPressed: () => _selectSection(2),
            icon: const Icon(Icons.analytics_outlined),
            label: const Text('결과 확인으로 이동')),
      ];

  List<Widget> _resultsContent() => [
        ExperimentResultSummary(
          key: ValueKey('result-summary-$_resultSummaryVersion'),
          experimentId: widget.experiment.id,
          repository: widget.plateRepository ?? const FilePlateRepository(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('open-result-plate'),
          onPressed: _isSaving ? null : () => _saveAndOpenPlate(results: true),
          icon: const Icon(Icons.grid_on),
          label: Text(_isLocked ? '결과 Plate 보기' : '결과 입력·가져오기'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('open-result-analysis'),
          onPressed: _isSaving
              ? null
              : () => _saveAndOpenPlate(analysis: true, results: true),
          icon: const Icon(Icons.analytics_outlined),
          label: const Text('분석·내보내기'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: _isSaving ? null : _openAttachments,
            icon: const Icon(Icons.attach_file),
            label:
                Text('사진·원본 파일 (${_persistedExperiment.attachments.length})')),
        const SizedBox(height: 12),
        if (!_isLocked)
          FilledButton.icon(
            key: const ValueKey('complete-experiment'),
            onPressed: _isSaving
                ? null
                : () async {
                    final previousStatus =
                        _isCorrecting ? ExperimentStatus.correcting : _status;
                    setState(() => _status = ExperimentStatus.completed);
                    final saved = await _save();
                    if (!saved && mounted && _saveError == null) {
                      setState(() => _status = previousStatus);
                    }
                  },
            icon: const Icon(Icons.task_alt),
            label: Text(_isCorrecting ? '정정 내용 재검토 후 완료' : '완료 전 점검'),
          ),
        if (_persistedExperiment.status == ExperimentStatus.completed)
          OutlinedButton.icon(
              onPressed: _isSaving ? null : _archive,
              icon: const Icon(Icons.archive_outlined),
              label: const Text('노트 보관')),
        const SizedBox(height: 16),
        if (_persistedExperiment.completedAt != null ||
            _persistedExperiment.revisions.isNotEmpty) ...[
          _ExperimentHistoryCard(experiment: _persistedExperiment),
          const SizedBox(height: 16),
        ],
      ];

  bool get _hasUnsavedChanges =>
      !_isLocked && _fingerprint() != _savedFingerprint;

  SaveStatus get _saveStatus {
    if (_isSaving) return SaveStatus.saving;
    if (_saveError != null) return SaveStatus.failed;
    if (_hasUnsavedChanges) return SaveStatus.unsaved;
    return SaveStatus.saved;
  }

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
    if (mounted) {
      setState(() {
        if (_titleController.text.trim().isNotEmpty) _titleError = null;
      });
    }
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
    if (action == _ExperimentExitAction.save && _hasUnsavedChanges) return;
    if (mounted) {
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    }
  }

  Future<void> _saveAndOpenPlate(
      {bool results = false, bool analysis = false}) async {
    if (_isSaving) return;
    if (!_isLocked && !await _save(showMessage: false)) {
      return;
    }
    if (_hasUnsavedChanges) return;

    if (!mounted) {
      return;
    }

    await _openPlate(
        readOnly: _persistedExperiment.isReadOnly,
        results: results,
        analysis: analysis);
  }

  Future<void> _openAttachments() async {
    if (_isSaving) return;
    if (!_isLocked && !await _save(showMessage: false)) return;
    try {
      final plate =
          await (widget.plateRepository ?? const FilePlateRepository())
              .loadPlate(widget.experiment.id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ExperimentAttachmentsScreen(
                experiment: _persistedExperiment,
                plate: plate,
                readOnly: _persistedExperiment.isReadOnly,
                fileStore: widget.attachmentFileStore,
                exchange: widget.attachmentExchange,
                onChanged: (updated) async {
                  await widget.onChanged(updated);
                  if (mounted) {
                    setState(() {
                      _persistedExperiment = updated;
                      _lastSavedAt = updated.updatedAt;
                    });
                  }
                },
              )));
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('첨부 화면을 열지 못했습니다: $error')));
      }
    }
  }

  Future<void> _openPlate(
      {required bool readOnly,
      WellPosition? initialPosition,
      bool results = false,
      bool analysis = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlateEditorScreen(
          experimentId: widget.experiment.id,
          experimentTitle: _titleController.text.trim(),
          readOnly: readOnly,
          initialPosition: initialPosition,
          initialResultsView: results,
          openAnalysisOnLoad: analysis,
          repository: widget.plateRepository,
          templateRepository: widget.plateTemplateRepository,
          documentExchangeService: widget.documentExchangeService,
        ),
      ),
    );
    if (mounted) setState(() => _resultSummaryVersion++);
  }

  Future<bool> _save({bool showMessage = true}) async {
    if (_isSaving || _isLocked) return false;
    if (_isCorrecting && !_hasUnsavedChanges) return true;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() {
        _titleError = '실험 제목을 입력해주세요.';
        _section = 0;
      });
      return false;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    String? completionRecord;
    if (_persistedExperiment.status != ExperimentStatus.completed &&
        _status == ExperimentStatus.completed) {
      completionRecord = await Navigator.of(context).push<String>(
        MaterialPageRoute(
            builder: (_) => ExperimentCompletionScreen(
                  experiment: _persistedExperiment.copyWith(tasks: [..._tasks]),
                  repository:
                      widget.plateRepository ?? const FilePlateRepository(),
                  initialNote: _completionReviewNote,
                  onNoteChanged: (value) => _completionReviewNote = value,
                  onOpenWell: (label) => _openPlate(
                      readOnly: false,
                      initialPosition: WellPosition.fromLabel(label)),
                )),
      );
      if (!mounted) return false;
      if (completionRecord == null) {
        setState(() {
          _isSaving = false;
          if (_isCorrecting) _status = ExperimentStatus.correcting;
        });
        return false;
      }
    }
    final now = DateTime.now();
    final revisions = [..._persistedExperiment.revisions];
    DateTime? completedAt = _persistedExperiment.completedAt;
    if (_persistedExperiment.status != ExperimentStatus.completed &&
        _status == ExperimentStatus.completed) {
      if (!_isCorrecting) completedAt ??= now;
      revisions.add(
        ExperimentRevision(
          id: 'revision-${now.microsecondsSinceEpoch}',
          changedAt: now,
          summary: _isCorrecting ? '정정 후 재검토 완료' : '실험 완료',
          reason: completionRecord ?? '',
          before: _isCorrecting
              ? _persistedExperiment.copyWith(revisions: [])
              : null,
        ),
      );
    }
    if (_isCorrecting &&
        _status == ExperimentStatus.correcting &&
        _fingerprint() != _savedFingerprint) {
      revisions.add(ExperimentRevision(
          id: 'revision-${now.microsecondsSinceEpoch}-edit',
          changedAt: now,
          summary: '정정 내용 저장',
          before: _persistedExperiment.copyWith(revisions: [])));
    }
    if (_status == ExperimentStatus.archived &&
        _persistedExperiment.status != ExperimentStatus.archived) {
      revisions.add(ExperimentRevision(
          id: 'revision-${now.microsecondsSinceEpoch}-archive',
          changedAt: now,
          summary: '노트 보관',
          before: _persistedExperiment.copyWith(revisions: [])));
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
    final savingFingerprint = _fingerprint();
    try {
      await widget.onChanged(updated);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saveError = error;
        });
      }
      return false;
    }
    _persistedExperiment = updated;
    _savedFingerprint = savingFingerprint;
    if (mounted) {
      setState(() {
        _isSaving = false;
        _lastSavedAt = now;
        _saveError = null;
        _isLocked = updated.isReadOnly && _fingerprint() == savingFingerprint;
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
    if (_isSaving ||
        _persistedExperiment.status != ExperimentStatus.completed) {
      return;
    }
    final controller = TextEditingController(text: _pendingCorrectionReason);
    String? errorText;
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('완료 노트 정정 시작'),
          content: TextField(
            key: const ValueKey('completion-edit-reason-field'),
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '수정 사유',
              hintText: '예: 시약 Lot 번호 정정',
              helperText: '사유와 정정 전 노트를 저장한 뒤 편집합니다. 완료 상태로 돌아가려면 재검토가 필요합니다.',
              helperMaxLines: 4,
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
    // Wait for the dialog route to finish before disposing its controller.
    await WidgetsBinding.instance.endOfFrame;
    controller.dispose();
    if (reason == null || !mounted) return;
    _pendingCorrectionReason = reason;
    if (await _persistTransition(
        _persistedExperiment.beginCorrection(reason, DateTime.now()))) {
      _pendingCorrectionReason = '';
    }
  }

  Future<bool> _persistTransition(Experiment updated) async {
    if (_isSaving) return false;
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      await widget.onChanged(updated);
      if (!mounted) return true;
      setState(() {
        _persistedExperiment = updated;
        _status = updated.status;
        _isLocked = updated.isReadOnly;
        _lastSavedAt = updated.updatedAt;
        _savedFingerprint = _fingerprint();
        _isSaving = false;
      });
      return true;
    } on Object {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('상태를 저장하지 못했습니다. 다시 시도해주세요.')));
      }
      return false;
    }
  }

  Future<void> _archive() async {
    if (_isSaving ||
        _persistedExperiment.status != ExperimentStatus.completed) {
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('완료 노트를 보관할까요?'),
                content: const Text('보관 중에는 노트·Plate·첨부를 읽기 전용으로 열 수 있습니다.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('보관'))
                ]));
    if (confirmed != true || !mounted) return;
    await _changeArchiveStatus(ExperimentStatus.archived, '노트 보관');
  }

  Future<void> _restoreArchive() async {
    if (_isSaving || _persistedExperiment.status != ExperimentStatus.archived) {
      return;
    }
    final wasCompleted = _persistedExperiment.completedAt != null ||
        _persistedExperiment.revisions.any((r) =>
            r.summary == '노트 보관' &&
            r.before?.status == ExperimentStatus.completed);
    final target =
        wasCompleted ? ExperimentStatus.completed : ExperimentStatus.draft;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('보관을 해제할까요?'),
                content: Text(target == ExperimentStatus.completed
                    ? '완료 상태로 돌아갑니다. 내용을 정정하려면 수정 사유를 남기고 시작하세요.'
                    : '최초 완료 기록이 없어 초안 상태로 돌아갑니다.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('보관 해제'))
                ]));
    if (confirmed != true || !mounted) return;
    await _changeArchiveStatus(target, '보관 해제');
  }

  Future<void> _changeArchiveStatus(
      ExperimentStatus status, String summary) async {
    final now = DateTime.now();
    await _persistTransition(_persistedExperiment
        .copyWith(status: status, updatedAt: now, revisions: [
      ..._persistedExperiment.revisions,
      ExperimentRevision(
          id: 'revision-${now.microsecondsSinceEpoch}',
          changedAt: now,
          summary: summary,
          before: _persistedExperiment.copyWith(revisions: []))
    ]));
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

class _CompletionLockBanner extends StatelessWidget {
  const _CompletionLockBanner({required this.archived});
  final bool archived;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        leading: const Icon(Icons.lock_outline),
        title: Text(archived ? '보관된 실험 노트입니다' : '완료된 실험 노트입니다'),
        subtitle: Text(archived
            ? '노트·Plate·첨부는 읽기 전용입니다. 편집하려면 먼저 보관을 해제하세요.'
            : '내용 변경과 Plate 편집을 시작하려면 수정 사유를 남기고 잠금을 해제하세요.'),
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
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) =>
                        ExperimentRevisionScreen(revision: revision))),
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
            const SizedBox(height: 12),
            ..._focusedTasks(),
            ExpansionTile(
              key: const PageStorageKey('all-experiment-tasks'),
              title: const Text('전체 단계 확인'),
              children: [
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
                    subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (tasks[index].isCompleted)
                            Text(_completedLabel(tasks[index]))
                          else if (tasks[index].startedAt != null)
                            _runningLabel(tasks[index])!,
                          _deadlineLabel(tasks[index]),
                          TextButton(
                              key: ValueKey('task-time-${tasks[index].id}'),
                              onPressed: widget.enabled
                                  ? () => _configureTimer(index)
                                  : null,
                              child: const Text('예정 시간 설정')),
                        ]),
                    secondary: _TaskTimerButton(
                      task: tasks[index],
                      onPressed:
                          widget.enabled ? () => _toggleTimer(index) : null,
                    ),
                    value: tasks[index].isCompleted,
                    onChanged: widget.enabled
                        ? (value) {
                            final updated = [...tasks];
                            final now = DateTime.now();
                            updated[index] = tasks[index].copyWith(
                              isCompleted: value ?? false,
                              completedAt: value == true ? now : null,
                            );
                            widget.onChanged(updated);
                          }
                        : null,
                  ),
              ],
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

  List<Widget> _focusedTasks() {
    final running = [
      for (var i = 0; i < widget.tasks.length; i++)
        if (widget.tasks[i].startedAt != null && !widget.tasks[i].isCompleted) i
    ];
    final next = widget.tasks.indexWhere((task) => !task.isCompleted);
    if (next < 0) {
      return [
        const Padding(
            padding: EdgeInsets.all(8),
            child: Text('모든 단계가 완료되었습니다. 결과를 확인하세요.'))
      ];
    }
    final focused = running.isEmpty ? [next] : running;
    return [
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(running.isEmpty ? '다음 단계' : '진행 중 ${running.length}개 단계',
              style: Theme.of(context).textTheme.titleMedium)),
      for (final index in focused)
        Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.tasks[index].title,
                      style: Theme.of(context).textTheme.titleLarge),
                  _deadlineLabel(widget.tasks[index]),
                  TextButton(
                      key: ValueKey(
                          'focused-task-time-${widget.tasks[index].id}'),
                      onPressed:
                          widget.enabled ? () => _configureTimer(index) : null,
                      child: const Text('예정 시간 설정')),
                  if (widget.tasks[index].startedAt != null)
                    _runningLabel(widget.tasks[index])!,
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: ValueKey('focused-task-${widget.tasks[index].id}'),
                    onPressed:
                        widget.enabled ? () => _toggleTimer(index) : null,
                    icon:
                        Icon(running.isEmpty ? Icons.play_arrow : Icons.check),
                    label: Text(running.isEmpty ? '이 단계 시작' : '단계 완료'),
                  ),
                ])),
      const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
              '단계 변경·예정 시간·메모는 상단 저장을 눌러 보관하세요. 종료 알림은 저장한 시작 시각과 예정 시간을 기준으로 예약합니다.')),
    ];
  }

  Future<void> _configureTimer(int index) async {
    final updated = await showDialog<ExperimentTask>(
        context: context,
        builder: (_) => TaskTimerSettings(task: widget.tasks[index]));
    if (updated == null || !mounted) return;
    final tasks = [...widget.tasks];
    tasks[index] = updated;
    widget.onChanged(tasks);
  }

  Widget _deadlineLabel(ExperimentTask task) {
    final minutes = task.plannedMinutes;
    if (minutes == null) return const Text('예정 시간 없음');
    final due = task.dueAt;
    final remaining = due?.difference(DateTime.now());
    final text = due == null || task.isCompleted
        ? '예정 $minutes분'
        : '${_dateTimeLabel(due.toLocal())} 예정 · ${remaining!.isNegative ? '${_durationLabel(-remaining)} 초과' : '${_durationLabel(remaining)} 남음'}';
    return Text('$text · ${task.reminderEnabled ? '알림 설정' : '알림 꺼짐'}',
        style: TextStyle(
            color: !task.isCompleted && (remaining?.isNegative ?? false)
                ? Theme.of(context).colorScheme.error
                : null));
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
    final completedAt = task.completedAt;
    final startedAt = task.startedAt;
    final completed =
        completedAt == null ? '완료 시각 미기록' : '${_dateTimeLabel(completedAt)} 완료';
    if (startedAt == null) return '$completed · 시작 시각 미기록';
    if (completedAt == null) {
      return '$completed · ${_dateTimeLabel(startedAt)} 시작';
    }
    return '${_dateTimeLabel(completedAt)} 완료 · ${_durationLabel(completedAt.difference(startedAt))}';
  }

  String _dateTimeLabel(DateTime timestamp) {
    final value = timestamp.toLocal();
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

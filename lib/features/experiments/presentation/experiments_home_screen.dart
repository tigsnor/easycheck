import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/services/document_exchange_service.dart';
import '../../backup/application/backup_restore_service.dart';
import '../../backup/domain/easycheck_backup_service.dart';
import '../../plates/data/file_plate_repository.dart';
import '../../plates/data/plate_repository.dart';
import '../../plates/domain/plate.dart';
import '../../plates/presentation/plate_editor_screen.dart';
import '../../plates/templates/data/file_plate_template_repository.dart';
import '../../plates/templates/data/plate_template_repository.dart';
import '../../plates/templates/domain/default_plate_templates.dart';
import '../../plates/templates/domain/plate_template.dart';
import '../data/file_experiment_repository.dart';
import '../data/experiment_repository.dart';
import '../domain/experiment.dart';
import 'experiment_detail_screen.dart';

class ExperimentsHomeScreen extends StatefulWidget {
  const ExperimentsHomeScreen({
    ExperimentRepository? repository,
    PlateRepository? plateRepository,
    DocumentExchangeService? documentExchangeService,
    PlateTemplateRepository? plateTemplateRepository,
    super.key,
  })  : repository = repository ?? const FileExperimentRepository(),
        plateRepository = plateRepository ?? const FilePlateRepository(),
        documentExchangeService =
            documentExchangeService ?? const PlatformDocumentExchangeService(),
        plateTemplateRepository =
            plateTemplateRepository ?? const FilePlateTemplateRepository();

  final ExperimentRepository repository;
  final PlateRepository plateRepository;
  final DocumentExchangeService documentExchangeService;
  final PlateTemplateRepository plateTemplateRepository;

  @override
  State<ExperimentsHomeScreen> createState() => _ExperimentsHomeScreenState();
}

class _ExperimentsHomeScreenState extends State<ExperimentsHomeScreen> {
  static const _uuid = Uuid();
  static const _backupService = EasyCheckBackupService();

  final _searchController = TextEditingController();
  List<Experiment> _experiments = const [];
  String _query = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    _loadExperiments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Experiment> get _filteredExperiments {
    if (_query.isEmpty) {
      return _experiments;
    }

    return _experiments.where((experiment) {
      final haystack = [
        experiment.title,
        experiment.projectName ?? '',
        experiment.experimentType,
        experiment.researcher ?? '',
        experiment.cellCountLabel ?? '',
        experiment.notes,
        ...experiment.tags,
      ].join(' ').toLowerCase();
      return haystack.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final experiments = _filteredExperiments;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PlateNote'),
        actions: [
          IconButton(
            tooltip: '전체 데이터 백업 및 복원',
            onPressed: _showBackupSheet,
            icon: const Icon(Icons.settings_backup_restore),
          ),
          IconButton(
            tooltip: '새 실험',
            onPressed: _showCreateExperimentSheet,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
          children: [
            Text(
              '실험 노트',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            SearchBar(
              controller: _searchController,
              hintText: '제목, 태그, 실험 유형 검색',
              leading: const Icon(Icons.search),
              trailing: [
                if (_query.isNotEmpty)
                  IconButton(
                    tooltip: '검색어 지우기',
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _QuickActionsCard(onCreate: _showCreateExperimentSheet),
            const SizedBox(height: 18),
            Text(
              '최근 실험',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (_isLoading)
              const _LoadingExperimentCard()
            else if (experiments.isEmpty)
              _EmptyExperimentCard(
                message: _query.isEmpty ? '아직 실험 노트가 없습니다.' : '검색 결과가 없습니다.',
                actionLabel: _query.isEmpty ? '첫 실험 만들기' : null,
                onAction: _query.isEmpty ? _showCreateExperimentSheet : null,
              )
            else
              for (final experiment in experiments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ExperimentCard(
                    experiment: experiment,
                    onOpen: () => _openExperiment(experiment),
                    onOpenPlate: () => _openPlate(experiment),
                    onDuplicate: () => _duplicateExperiment(experiment),
                    onDelete: () => _deleteExperiment(experiment),
                  ),
                ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateExperimentSheet,
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('새 실험'),
      ),
    );
  }

  Future<void> _loadExperiments() async {
    setState(() => _isLoading = true);

    try {
      final experiments = await widget.repository.loadExperiments();
      if (!mounted) {
        return;
      }
      setState(() {
        _experiments = experiments;
        _isLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      _showError('실험 노트를 불러오지 못했습니다: $error');
    }
  }

  void _openExperiment(Experiment experiment) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExperimentDetailScreen(
          experiment: experiment,
          onChanged: _saveExperiment,
        ),
      ),
    );
  }

  void _openPlate(Experiment experiment) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlateEditorScreen(
          experimentId: experiment.id,
          experimentTitle: experiment.title,
          repository: widget.plateRepository,
          templateRepository: widget.plateTemplateRepository,
        ),
      ),
    );
  }

  Future<void> _saveExperiment(Experiment experiment) async {
    final saved = experiment.copyWith(updatedAt: DateTime.now());
    await widget.repository.saveExperiment(saved);
    if (!mounted) {
      return;
    }
    setState(() => _upsertLocalExperiment(saved));
  }

  Future<void> _duplicateExperiment(Experiment experiment) async {
    final now = DateTime.now();
    final copy = experiment.copyWith(
      id: _uuid.v4(),
      title: '${experiment.title} 복사본',
      status: ExperimentStatus.draft,
      createdAt: now,
      updatedAt: now,
    );

    await _saveExperiment(copy);
  }

  Future<void> _deleteExperiment(Experiment experiment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('실험을 삭제할까요?'),
        content: Text(
          '“${experiment.title}” 실험 노트와 연결된 Plate 데이터를 삭제합니다. 삭제 직후에는 실행 취소할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-experiment-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    Plate? deletedPlate;
    try {
      deletedPlate = await widget.plateRepository.loadPlate(experiment.id);
      await widget.repository.deleteExperiment(experiment.id);
      await widget.plateRepository.deletePlate(experiment.id);
    } on Object catch (error) {
      try {
        await widget.repository.saveExperiment(experiment);
        if (deletedPlate != null) {
          await widget.plateRepository.savePlate(deletedPlate);
        }
      } on Object {
        // The original failure is shown below. Backup/export will provide a
        // stronger recovery path in the next milestone.
      }
      if (mounted) {
        _showError('실험을 삭제하지 못했습니다: $error');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _experiments =
          _experiments.where((item) => item.id != experiment.id).toList();
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('“${experiment.title}”을 삭제했습니다.'),
          action: SnackBarAction(
            label: '실행 취소',
            onPressed: () => _restoreDeletedExperiment(
              experiment: experiment,
              plate: deletedPlate,
            ),
          ),
        ),
      );
  }

  Future<void> _restoreDeletedExperiment({
    required Experiment experiment,
    required Plate? plate,
  }) async {
    try {
      await widget.repository.saveExperiment(experiment);
      if (plate != null) {
        await widget.plateRepository.savePlate(plate);
      }
    } on Object catch (error) {
      if (mounted) {
        _showError('삭제를 취소하지 못했습니다: $error');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _upsertLocalExperiment(experiment));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('실험과 Plate 데이터를 복원했습니다.')));
  }

  Future<void> _showBackupSheet() async {
    try {
      final experiments = await widget.repository.loadExperiments();
      final plates = <Plate>[];
      for (final experiment in experiments) {
        final plate = await widget.plateRepository.loadPlate(experiment.id);
        if (plate != null) {
          plates.add(plate);
        }
      }
      final exportText = _backupService.encode(
        experiments: experiments,
        plates: plates,
      );
      if (!mounted) {
        return;
      }
      final backup = await showModalBottomSheet<EasyCheckBackup>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _BackupRestoreSheet(
          exportText: exportText,
          service: _backupService,
          documentExchangeService: widget.documentExchangeService,
        ),
      );
      if (backup != null) {
        await _confirmAndRestoreBackup(backup);
      }
    } on Object catch (error) {
      if (mounted) {
        _showError('백업 데이터를 준비하지 못했습니다: $error');
      }
    }
  }

  Future<void> _confirmAndRestoreBackup(EasyCheckBackup backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('백업을 복원할까요?'),
        content: Text(
          '실험 ${backup.experiments.length}개와 Plate ${backup.plates.length}개를 검증한 뒤 병합합니다. 같은 ID의 데이터는 백업 내용으로 덮어쓰고 다른 데이터는 유지합니다. 저장에 실패하면 복원 시작 전 상태로 되돌립니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('confirm-restore-backup-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('복원'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    try {
      final restoreService = BackupRestoreService(
        experimentRepository: widget.repository,
        plateRepository: widget.plateRepository,
      );
      await restoreService.restore(backup);
      await _loadExperiments();
    } on Object catch (error) {
      if (mounted) {
        _showError('백업을 복원하지 못했습니다: $error');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '실험 ${backup.experiments.length}개와 Plate ${backup.plates.length}개를 복원했습니다.',
        ),
      ),
    );
  }

  Future<void> _showCreateExperimentSheet() async {
    final List<PlateTemplate> templates;
    try {
      templates = DefaultPlateTemplates.mergeWithSaved(
        await widget.plateTemplateRepository.loadTemplates(),
      );
    } on Object catch (error) {
      if (mounted) {
        _showError('Plate 템플릿을 불러오지 못했습니다: $error');
      }
      return;
    }
    if (!mounted) {
      return;
    }

    final draft = await showModalBottomSheet<_CreateExperimentDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CreateExperimentSheet(templates: templates),
    );

    if (draft == null) {
      return;
    }

    await _createExperiment(draft);
  }

  Future<void> _createExperiment(_CreateExperimentDraft draft) async {
    final experiment = draft.experiment.copyWith(updatedAt: DateTime.now());
    try {
      await widget.repository.saveExperiment(experiment);
      final template = draft.template;
      if (template != null) {
        await widget.plateRepository.savePlate(
          template.instantiate(
            plateId: 'plate-${experiment.id}',
            experimentId: experiment.id,
          ),
        );
      }
    } on Object catch (error) {
      try {
        await widget.plateRepository.deletePlate(experiment.id);
        await widget.repository.deleteExperiment(experiment.id);
      } on Object {
        // Preserve the original creation error for the user.
      }
      if (mounted) {
        _showError('실험을 생성하지 못했습니다: $error');
      }
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() => _upsertLocalExperiment(experiment));
    final message = draft.template == null
        ? '새 실험을 생성했습니다.'
        : '새 실험에 “${draft.template!.name}” 템플릿을 적용했습니다.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _upsertLocalExperiment(Experiment experiment) {
    final experiments = [..._experiments];
    final index = experiments.indexWhere((item) => item.id == experiment.id);

    if (index == -1) {
      experiments.insert(0, experiment);
    } else {
      experiments[index] = experiment;
    }

    experiments.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _experiments = experiments;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _BackupRestoreSheet extends StatefulWidget {
  const _BackupRestoreSheet({
    required this.exportText,
    required this.service,
    required this.documentExchangeService,
  });

  final String exportText;
  final EasyCheckBackupService service;
  final DocumentExchangeService documentExchangeService;

  @override
  State<_BackupRestoreSheet> createState() => _BackupRestoreSheetState();
}

class _BackupRestoreSheetState extends State<_BackupRestoreSheet> {
  final _restoreController = TextEditingController();
  EasyCheckBackup? _preview;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restoreController.addListener(_validateRestoreText);
  }

  @override
  void dispose() {
    _restoreController
      ..removeListener(_validateRestoreText)
      ..dispose();
    super.dispose();
  }

  void _validateRestoreText() {
    final text = _restoreController.text;
    if (text.trim().isEmpty) {
      setState(() {
        _preview = null;
        _error = null;
      });
      return;
    }
    try {
      final backup = widget.service.decode(text);
      setState(() {
        _preview = backup;
        _error = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _preview = null;
        _error = error.message;
      });
    }
  }

  Future<void> _copyBackup() async {
    await Clipboard.setData(ClipboardData(text: widget.exportText));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('전체 백업 JSON을 복사했습니다.')));
  }

  Future<void> _pasteBackup() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) {
      return;
    }
    _restoreController.text = data!.text!;
  }

  Future<void> _shareBackupFile(BuildContext shareContext) async {
    try {
      final status = await widget.documentExchangeService.shareTextDocument(
        content: widget.exportText,
        fileName: _backupFileName(DateTime.now()),
        mimeType: 'application/json',
        subject: 'PlateNote 전체 데이터 백업',
        sharePositionOrigin: _sharePositionOrigin(shareContext),
      );
      if (!mounted || status == DocumentShareStatus.dismissed) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == DocumentShareStatus.success
                ? '백업 파일을 공유했습니다.'
                : '이 기기에서는 파일 공유를 사용할 수 없습니다.',
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('백업 파일을 공유하지 못했습니다: $error')));
      }
    }
  }

  Future<void> _pickBackupFile() async {
    try {
      final document = await widget.documentExchangeService.pickTextDocument(
        allowedExtensions: const ['json'],
      );
      if (!mounted || document == null) {
        return;
      }
      _restoreController.text = document.content;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${document.name} 파일을 불러왔습니다.')));
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('백업 파일을 읽지 못했습니다: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final preview = _preview;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '전체 데이터 백업 · 복원',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text('실험 노트와 연결 Plate를 하나의 버전형 JSON으로 보관합니다.'),
          const SizedBox(height: 18),
          Text(
            '백업 내보내기',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 130),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                widget.exportText,
                key: const ValueKey('backup-export-text'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _copyBackup,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('JSON 복사'),
                ),
                Builder(
                  builder: (shareContext) => FilledButton.tonalIcon(
                    key: const ValueKey('share-backup-file-button'),
                    onPressed: () => _shareBackupFile(shareContext),
                    icon: const Icon(Icons.ios_share_outlined),
                    label: const Text('파일 공유'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          Text(
            '백업 복원',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text('기존 데이터는 유지하며 같은 ID만 백업 내용으로 덮어씁니다.'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('pick-backup-file-button'),
            onPressed: _pickBackupFile,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('백업 파일 선택'),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('backup-restore-field'),
            controller: _restoreController,
            minLines: 5,
            maxLines: 9,
            decoration: InputDecoration(
              labelText: '백업 JSON',
              alignLabelWithHint: true,
              errorText: _error,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: _pasteBackup,
                icon: const Icon(Icons.content_paste),
                label: const Text('클립보드 붙여넣기'),
              ),
              const Spacer(),
              if (preview != null)
                Text(
                  '실험 ${preview.experiments.length} · Plate ${preview.plates.length}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('restore-backup-button'),
              onPressed: preview == null
                  ? null
                  : () => Navigator.of(context).pop(preview),
              icon: const Icon(Icons.restore),
              label: const Text('백업 병합 복원'),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '오늘 할 일',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.science_outlined, size: 18),
                  label: const Text('CCK-8 노트'),
                  onPressed: onCreate,
                ),
                ActionChip(
                  avatar: const Icon(Icons.grid_view_rounded, size: 18),
                  label: const Text('96-well plate'),
                  onPressed: onCreate,
                ),
                ActionChip(
                  avatar: const Icon(Icons.water_drop_outlined, size: 18),
                  label: const Text('2배 희석'),
                  onPressed: onCreate,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExperimentCard extends StatelessWidget {
  const _ExperimentCard({
    required this.experiment,
    required this.onOpen,
    required this.onOpenPlate,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Experiment experiment;
  final VoidCallback onOpen;
  final VoidCallback onOpenPlate;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          experiment.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${experiment.experimentType} · ${experiment.status.label}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_ExperimentAction>(
                    onSelected: (action) {
                      switch (action) {
                        case _ExperimentAction.duplicate:
                          onDuplicate();
                          break;
                        case _ExperimentAction.delete:
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _ExperimentAction.duplicate,
                        child: Text('복제'),
                      ),
                      PopupMenuItem(
                        value: _ExperimentAction.delete,
                        child: Text('삭제'),
                      ),
                    ],
                  ),
                ],
              ),
              if (experiment.notesWithoutCellCountLine.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  experiment.notesWithoutCellCountLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (experiment.cellCountLabel?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  '세포수 · ${experiment.cellCountLabel}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in experiment.tags)
                    Chip(
                      label: Text('#$tag'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpenPlate,
                  icon: const Icon(Icons.grid_on_rounded),
                  label: const Text('Plate 열기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingExperimentCard extends StatelessWidget {
  const _LoadingExperimentCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _EmptyExperimentCard extends StatelessWidget {
  const _EmptyExperimentCard({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 42,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 12),
            Text(message),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.note_add_outlined),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateExperimentDraft {
  const _CreateExperimentDraft({required this.experiment, this.template});

  final Experiment experiment;
  final PlateTemplate? template;
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final isKeyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (isKeyboardVisible)
          IconButton(
            tooltip: '키보드 내리기',
            onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
            icon: const Icon(Icons.keyboard_hide_outlined),
          ),
        IconButton(
          tooltip: '닫기',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _CreateExperimentSheet extends StatefulWidget {
  const _CreateExperimentSheet({required this.templates});

  final List<PlateTemplate> templates;

  @override
  State<_CreateExperimentSheet> createState() => _CreateExperimentSheetState();
}

class _CreateExperimentSheetState extends State<_CreateExperimentSheet> {
  static const _uuid = Uuid();

  final _titleController = TextEditingController();
  final _projectController = TextEditingController(text: 'Cell viability');
  final _notesController = TextEditingController();
  final _cellNameController = TextEditingController();
  final _cellCountController = TextEditingController();
  final _cellExponentController = TextEditingController(text: '6');
  String _experimentType = 'CCK-8';
  String _cellCountUnit = 'ml';
  String? _templateId;

  @override
  void dispose() {
    _titleController.dispose();
    _projectController.dispose();
    _notesController.dispose();
    _cellNameController.dispose();
    _cellCountController.dispose();
    _cellExponentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SheetHeader(title: '새 실험 노트'),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _titleController,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '실험 제목',
                      hintText: '예: Drug A CCK-8 2배 희석',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
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
                      DropdownMenuItem(value: 'Custom', child: Text('Custom')),
                    ],
                    onChanged: (value) =>
                        setState(() => _experimentType = value ?? 'Custom'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _projectController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '프로젝트'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '메모',
                      hintText: '세포주, 처리 시간, 주의사항 등을 적어두세요.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '세포수 (선택)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _cellNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '세포 이름',
                      hintText: '예: hek293',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _cellCountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '세포수',
                            hintText: '예: 1',
                            prefixText: '× ',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _cellExponentController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '10^n',
                            hintText: '6',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          onTap: () =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          initialValue: _cellCountUnit,
                          decoration: const InputDecoration(labelText: '단위'),
                          items: const [
                            DropdownMenuItem(value: 'ml', child: Text('ml')),
                            DropdownMenuItem(
                              value: 'well',
                              child: Text('well'),
                            ),
                            DropdownMenuItem(
                              value: 'plate',
                              child: Text('plate'),
                            ),
                            DropdownMenuItem(value: 'etc', child: Text('etc')),
                          ],
                          onChanged: (value) =>
                              setState(() => _cellCountUnit = value ?? 'ml'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '예: hek293: 1×10^6/ml',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    key: const ValueKey('new-experiment-template-field'),
                    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                    initialValue: _templateId,
                    decoration: const InputDecoration(
                      labelText: 'Plate 템플릿',
                      helperText: '선택하면 실험 생성과 동시에 Plate 설정을 적용합니다.',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('사용하지 않음'),
                      ),
                      for (final template in widget.templates)
                        DropdownMenuItem<String?>(
                          value: template.id,
                          child: Text(template.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _templateId = value),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _createExperiment,
                      icon: const Icon(Icons.check),
                      label: const Text('생성'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _createExperiment() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('실험 제목을 입력해주세요.')));
      return;
    }

    final now = DateTime.now();
    final cellCountLabel = _cellCountLabel();
    PlateTemplate? selectedTemplate;
    for (final template in widget.templates) {
      if (template.id == _templateId) {
        selectedTemplate = template;
        break;
      }
    }
    Navigator.of(context).pop(
      _CreateExperimentDraft(
        experiment: Experiment(
          id: _uuid.v4(),
          title: title,
          projectName: _projectController.text.trim().isEmpty
              ? null
              : _projectController.text.trim(),
          experimentType: _experimentType,
          status: ExperimentStatus.draft,
          createdAt: now,
          updatedAt: now,
          notes: _notesController.text.trim(),
          cellCountLabel: cellCountLabel,
          tags: [_experimentType.replaceAll('-', '')],
        ),
        template: selectedTemplate,
      ),
    );
  }

  String? _cellCountLabel() {
    final cellName = _cellNameController.text.trim();
    final cellCount = _cellCountController.text.trim();
    final exponent = _cellExponentController.text.trim();
    if (cellName.isEmpty && cellCount.isEmpty && exponent.isEmpty) {
      return null;
    }

    final normalizedCellName = cellName.isEmpty ? 'cell' : cellName;
    final normalizedCellCount = cellCount.isEmpty ? '1' : cellCount;
    final normalizedExponent = exponent.isEmpty ? '6' : exponent;
    return '$normalizedCellName: $normalizedCellCount×10^$normalizedExponent/$_cellCountUnit';
  }
}

enum _ExperimentAction { duplicate, delete }

extension _ExperimentStatusLabel on ExperimentStatus {
  String get label {
    switch (this) {
      case ExperimentStatus.draft:
        return '초안';
      case ExperimentStatus.planned:
        return '계획됨';
      case ExperimentStatus.inProgress:
        return '진행 중';
      case ExperimentStatus.completed:
        return '완료';
      case ExperimentStatus.archived:
        return '보관됨';
    }
  }
}

String _backupFileName(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return 'platenote-backup-${value.year}${twoDigits(value.month)}${twoDigits(value.day)}-${twoDigits(value.hour)}${twoDigits(value.minute)}.json';
}

Rect _sharePositionOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  return const Rect.fromLTWH(0, 0, 1, 1);
}

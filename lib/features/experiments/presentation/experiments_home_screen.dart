import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../plates/presentation/plate_editor_screen.dart';
import '../data/file_experiment_repository.dart';
import '../data/experiment_repository.dart';
import '../domain/experiment.dart';
import 'experiment_detail_screen.dart';

class ExperimentsHomeScreen extends StatefulWidget {
  const ExperimentsHomeScreen({ExperimentRepository? repository, super.key})
      : repository = repository ?? const FileExperimentRepository();

  final ExperimentRepository repository;

  @override
  State<ExperimentsHomeScreen> createState() => _ExperimentsHomeScreenState();
}

class _ExperimentsHomeScreenState extends State<ExperimentsHomeScreen> {
  static const _uuid = Uuid();

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
        title: const Text('EasyCheck'),
        actions: [
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
    await widget.repository.deleteExperiment(experiment.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _experiments =
          _experiments.where((item) => item.id != experiment.id).toList();
    });
  }

  Future<void> _showCreateExperimentSheet() async {
    final created = await showModalBottomSheet<Experiment>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CreateExperimentSheet(),
    );

    if (created == null) {
      return;
    }

    await _saveExperiment(created);
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
              if (experiment.notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  experiment.notes,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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

class _CreateExperimentSheet extends StatefulWidget {
  const _CreateExperimentSheet();

  @override
  State<_CreateExperimentSheet> createState() => _CreateExperimentSheetState();
}

class _CreateExperimentSheetState extends State<_CreateExperimentSheet> {
  static const _uuid = Uuid();

  final _titleController = TextEditingController();
  final _projectController = TextEditingController(text: 'Cell viability');
  final _notesController = TextEditingController();
  String _experimentType = 'CCK-8';

  @override
  void dispose() {
    _titleController.dispose();
    _projectController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '새 실험 노트',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _titleController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '실험 제목',
              hintText: '예: Drug A CCK-8 2배 희석',
            ),
          ),
          const SizedBox(height: 12),
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
              DropdownMenuItem(value: 'Custom', child: Text('Custom')),
            ],
            onChanged: (value) =>
                setState(() => _experimentType = value ?? 'Custom'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _projectController,
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
    Navigator.of(context).pop(
      Experiment(
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
        tags: [_experimentType.replaceAll('-', '')],
      ),
    );
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

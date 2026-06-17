import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/models/well_position.dart';
import '../../../shared/services/document_exchange_service.dart';
import '../../dilution/domain/dilution_direction.dart';
import '../../dilution/domain/dilution_plan.dart';
import '../../dilution/domain/dilution_service.dart';
import '../../dilution/domain/pipetting_plan_service.dart';
import '../data/file_plate_repository.dart';
import '../data/plate_repository.dart';
import '../domain/plate.dart';
import '../domain/plate_analysis_export_service.dart';
import '../domain/plate_analysis_service.dart';
import '../domain/plate_dilution_service.dart';
import '../domain/plate_export_service.dart';
import '../domain/plate_result_import_service.dart';
import '../domain/plate_validation_service.dart';
import '../domain/well.dart';
import '../domain/well_group.dart';
import '../domain/well_role.dart';
import '../templates/data/file_plate_template_repository.dart';
import '../templates/data/plate_template_repository.dart';
import '../templates/domain/default_plate_templates.dart';
import '../templates/domain/plate_template.dart';

enum _TemplateAction { save, apply, manage }

class PlateEditorScreen extends StatefulWidget {
  const PlateEditorScreen({
    required this.experimentId,
    this.experimentTitle = 'CCK-8 2배 희석 실험 초안',
    PlateRepository? repository,
    DocumentExchangeService? documentExchangeService,
    PlateTemplateRepository? templateRepository,
    super.key,
  })  : repository = repository ?? const FilePlateRepository(),
        templateRepository =
            templateRepository ?? const FilePlateTemplateRepository(),
        documentExchangeService =
            documentExchangeService ?? const PlatformDocumentExchangeService();

  final String experimentId;
  final String experimentTitle;
  final PlateRepository repository;
  final DocumentExchangeService documentExchangeService;
  final PlateTemplateRepository templateRepository;

  @override
  State<PlateEditorScreen> createState() => _PlateEditorScreenState();
}

class _PlateEditorScreenState extends State<PlateEditorScreen> {
  static const _groupColors = [
    Color(0xFFE6D9FF),
    Color(0xFFFFD7D7),
    Color(0xFFD5F5E3),
    Color(0xFFD6EAF8),
    Color(0xFFFFF2CC),
  ];

  final _dilutionService = const DilutionService();
  final _plateDilutionService = const PlateDilutionService();
  final _plateExportService = const PlateExportService();
  final _plateResultImportService = const PlateResultImportService();
  final _plateValidationService = const PlateValidationService();
  final _plateAnalysisService = const PlateAnalysisService();
  final _plateAnalysisExportService = const PlateAnalysisExportService();
  late final List<double> _demoConcentrations;
  Plate? _plate;
  WellPosition? _selectedPosition;
  Set<WellPosition> _selectedPositions = const {};
  WellPosition? _rangeAnchor;
  bool _isLoading = true;
  bool _isSaving = false;
  DateTime? _lastSavedAt;
  final List<Plate> _undoHistory = [];
  double? _plateCellSize;

  @override
  void initState() {
    super.initState();
    _demoConcentrations = _dilutionService.buildSeries(
      const DilutionPlan(
        startConcentration: 1000,
        dilutionFactor: 2,
        steps: 6,
        includeZeroControl: true,
      ),
    );
    _loadPlate();
  }

  @override
  Widget build(BuildContext context) {
    final plate = _plate;

    return Scaffold(
      appBar: AppBar(
        title: const Text('EasyCheck'),
        actions: [
          IconButton(
            tooltip: '마지막 Plate 변경 실행 취소',
            onPressed:
                _undoHistory.isEmpty || _isSaving ? null : _undoLastChange,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: '선택 영역 그룹 지정',
            onPressed: plate == null || _selectedPositions.isEmpty
                ? null
                : _assignGroupToSelection,
            icon: const Icon(Icons.palette_outlined),
          ),
          IconButton(
            tooltip: '희석 계산 적용',
            onPressed: plate == null ? null : _openDilutionBuilder,
            icon: const Icon(Icons.water_drop_outlined),
          ),
          IconButton(
            tooltip: 'Plate 내보내기',
            onPressed: plate == null ? null : _showPlateExport,
            icon: const Icon(Icons.ios_share_outlined),
          ),
          PopupMenuButton<_TemplateAction>(
            tooltip: 'Plate 템플릿',
            enabled: plate != null && !_isSaving,
            onSelected: (action) {
              switch (action) {
                case _TemplateAction.save:
                  _saveCurrentPlateAsTemplate();
                  return;
                case _TemplateAction.apply:
                  _chooseAndApplyTemplate();
                  return;
                case _TemplateAction.manage:
                  _managePlateTemplates();
                  return;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _TemplateAction.save,
                child: ListTile(
                  leading: Icon(Icons.bookmark_add_outlined),
                  title: Text('현재 Plate를 템플릿으로 저장'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _TemplateAction.apply,
                child: ListTile(
                  leading: Icon(Icons.library_add_check_outlined),
                  title: Text('저장된 템플릿 적용'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _TemplateAction.manage,
                child: ListTile(
                  leading: Icon(Icons.tune_outlined),
                  title: Text('템플릿 관리'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: plate == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('bulk-result-import-button'),
              onPressed: _openBulkResultImport,
              icon: const Icon(Icons.table_view_outlined),
              label: const Text('결과 일괄 입력'),
            ),
      body: SafeArea(
        child: _isLoading || plate == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
                children: [
                  _ExperimentHeaderCard(
                    title: widget.experimentTitle,
                    series: _demoConcentrations,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plate.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            _PlateSaveStatus(
                              isSaving: _isSaving,
                              lastSavedAt: _lastSavedAt,
                            ),
                          ],
                        ),
                      ),
                      if (_selectedPositions.isNotEmpty)
                        TextButton(
                          onPressed: _clearSelection,
                          child: const Text('선택 해제'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _PlateGrid(
                    plate: plate,
                    selectedPositions: _selectedPositions,
                    requestedCellSize: _plateCellSize,
                    onZoomOut: _canZoomPlateOut ? _zoomPlateOut : null,
                    onFit: _plateCellSize == null ? null : _fitPlateToScreen,
                    onZoomIn: _canZoomPlateIn ? _zoomPlateIn : null,
                    onSelected: _selectSingleWell,
                    onRangeSelected: _selectRangeTo,
                    onRowSelected: _selectRow,
                    onColumnSelected: _selectColumn,
                  ),
                  const SizedBox(height: 18),
                  _PlateSummaryCard(plate: plate),
                  const SizedBox(height: 12),
                  _PlateValidationCard(
                    report: _plateValidationService.validate(plate),
                  ),
                  const SizedBox(height: 12),
                  _PlateAnalysisCard(
                    report: _plateAnalysisService.analyze(plate),
                    onCopy: () => _copyAnalysisExport(plate),
                    onShare: (shareContext) =>
                        _shareAnalysisExport(plate, shareContext),
                  ),
                  const SizedBox(height: 12),
                  _SelectionSummaryCard(
                    selectedCount: _selectedPositions.length,
                    rangeAnchor: _rangeAnchor,
                    onStartRange: _selectedPosition == null
                        ? null
                        : () =>
                            setState(() => _rangeAnchor = _selectedPosition),
                    onAssignGroup: _selectedPositions.isEmpty
                        ? null
                        : _assignGroupToSelection,
                    onApplyDilution: _openDilutionBuilder,
                  ),
                  const SizedBox(height: 12),
                  _WellDetailCard(
                    well: _selectedWell,
                    group: _selectedGroup,
                    onEdit: _selectedWell == null ? null : _editSelectedWell,
                  ),
                ],
              ),
      ),
    );
  }

  Well? get _selectedWell {
    final plate = _plate;
    final position = _selectedPosition;
    if (plate == null || position == null) {
      return null;
    }
    return plate.wellAt(position);
  }

  WellGroup? get _selectedGroup {
    final plate = _plate;
    final groupId = _selectedWell?.groupId;
    if (plate == null || groupId == null) {
      return null;
    }
    return plate.groups.cast<WellGroup?>().firstWhere(
          (group) => group?.id == groupId,
          orElse: () => null,
        );
  }

  Future<void> _loadPlate() async {
    try {
      final stored = await widget.repository.loadPlate(widget.experimentId);
      final plate = stored ?? _buildDefaultPlate();
      if (stored == null) {
        await widget.repository.savePlate(plate);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _plate = plate;
        _isLoading = false;
        _lastSavedAt = DateTime.now();
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('plate를 불러오지 못했습니다: $error')));
    }
  }

  Plate _buildDefaultPlate() {
    final emptyPlate = Plate(
      id: 'plate-${widget.experimentId}',
      experimentId: widget.experimentId,
      name: '96-well Plate',
    );
    return _plateWithDemoDilution(emptyPlate);
  }

  bool get _canZoomPlateOut => _plateCellSize == null || _plateCellSize! > 32;

  bool get _canZoomPlateIn => _plateCellSize == null || _plateCellSize! < 64;

  void _zoomPlateOut() {
    setState(() {
      final current = _plateCellSize ?? 40;
      _plateCellSize = (current - 8).clamp(32, 64).toDouble();
    });
  }

  void _zoomPlateIn() {
    setState(() {
      final current = _plateCellSize ?? 32;
      _plateCellSize = (current + 8).clamp(32, 64).toDouble();
    });
  }

  void _fitPlateToScreen() {
    setState(() => _plateCellSize = null);
  }

  void _selectSingleWell(WellPosition position) {
    setState(() {
      _selectedPosition = position;
      if (_rangeAnchor == null) {
        _selectedPositions = {position};
      } else {
        _selectedPositions = _rectangle(_rangeAnchor!, position).toSet();
        _rangeAnchor = null;
      }
    });
  }

  void _selectRangeTo(WellPosition position) {
    final anchor = _selectedPosition ?? _rangeAnchor ?? position;
    setState(() {
      _selectedPosition = position;
      _selectedPositions = _rectangle(anchor, position).toSet();
      _rangeAnchor = null;
    });
  }

  void _selectRow(int rowIndex) {
    final plate = _plate;
    if (plate == null) {
      return;
    }
    setState(() {
      _selectedPosition = WellPosition(rowIndex: rowIndex, columnIndex: 0);
      _selectedPositions = {
        for (var column = 0; column < plate.columnCount; column++)
          WellPosition(rowIndex: rowIndex, columnIndex: column),
      };
      _rangeAnchor = null;
    });
  }

  void _selectColumn(int columnIndex) {
    final plate = _plate;
    if (plate == null) {
      return;
    }
    setState(() {
      _selectedPosition = WellPosition(rowIndex: 0, columnIndex: columnIndex);
      _selectedPositions = {
        for (var row = 0; row < plate.rowCount; row++)
          WellPosition(rowIndex: row, columnIndex: columnIndex),
      };
      _rangeAnchor = null;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedPosition = null;
      _selectedPositions = const {};
      _rangeAnchor = null;
    });
  }

  Iterable<WellPosition> _rectangle(
    WellPosition start,
    WellPosition end,
  ) sync* {
    final rowStart =
        start.rowIndex < end.rowIndex ? start.rowIndex : end.rowIndex;
    final rowEnd =
        start.rowIndex > end.rowIndex ? start.rowIndex : end.rowIndex;
    final columnStart = start.columnIndex < end.columnIndex
        ? start.columnIndex
        : end.columnIndex;
    final columnEnd = start.columnIndex > end.columnIndex
        ? start.columnIndex
        : end.columnIndex;

    for (var row = rowStart; row <= rowEnd; row++) {
      for (var column = columnStart; column <= columnEnd; column++) {
        yield WellPosition(rowIndex: row, columnIndex: column);
      }
    }
  }

  Future<void> _saveCurrentPlateAsTemplate() async {
    final plate = _plate;
    if (plate == null) {
      return;
    }
    var templateName = '${plate.name} 템플릿';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Plate 템플릿 저장'),
        content: TextFormField(
          key: const ValueKey('plate-template-name-field'),
          initialValue: templateName,
          autofocus: true,
          onChanged: (value) => templateName = value,
          decoration: const InputDecoration(
            labelText: '템플릿 이름',
            hintText: '예: CCK-8 2배 희석 3반복',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('confirm-save-plate-template'),
            onPressed: () => Navigator.of(context).pop(templateName.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) {
      return;
    }

    final now = DateTime.now().toUtc();
    final template = PlateTemplate.fromPlate(
      id: 'template-${now.microsecondsSinceEpoch}',
      name: name,
      plate: plate,
      createdAt: now,
    );
    try {
      await widget.templateRepository.saveTemplate(template);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('템플릿을 저장하지 못했습니다: $error')));
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('“$name” 템플릿을 저장했습니다.')));
    }
  }

  Future<void> _chooseAndApplyTemplate() async {
    final plate = _plate;
    if (plate == null) {
      return;
    }
    final templates = await _loadPlateTemplatesForAction();
    if (templates == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (templates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('저장된 Plate 템플릿이 없습니다.')));
      return;
    }

    final selected = await showDialog<PlateTemplate>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('적용할 Plate 템플릿'),
        children: [
          for (final template in templates)
            SimpleDialogOption(
              key: ValueKey('plate-template-${template.id}'),
              onPressed: () => Navigator.of(context).pop(template),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.view_module_outlined),
                title: Text(template.name),
                subtitle: Text(
                  '${template.rowCount} × ${template.columnCount} · 결과값은 포함하지 않음',
                ),
              ),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('“${selected.name}”을 적용할까요?'),
        content: const Text(
          '현재 Plate의 그룹, 농도, 역할, 부피와 메모가 템플릿 내용으로 교체됩니다. 측정 결과와 분석 제외 상태는 템플릿에 포함되지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('confirm-apply-plate-template'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('적용'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final updated = selected.instantiate(
      plateId: plate.id,
      experimentId: plate.experimentId,
      plateName: plate.name,
    );
    final saved = await _savePlate(
      updated,
      successMessage: '“${selected.name}” 템플릿을 적용했습니다.',
    );
    if (saved && mounted) {
      _clearSelection();
    }
  }

  Future<void> _managePlateTemplates() async {
    final templates = await _loadPlateTemplatesForAction();
    if (templates == null || !mounted) {
      return;
    }
    if (templates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('관리할 Plate 템플릿이 없습니다.')));
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => _PlateTemplateManagementDialog(
        initialTemplates: templates,
        repository: widget.templateRepository,
        onMessage: (message) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        },
      ),
    );
  }

  Future<List<PlateTemplate>?> _loadPlateTemplatesForAction() async {
    try {
      return DefaultPlateTemplates.mergeWithSaved(
        await widget.templateRepository.loadTemplates(),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('템플릿을 불러오지 못했습니다: $error')));
      }
      return null;
    }
  }

  Future<void> _showPlateExport() async {
    final plate = _plate;
    if (plate == null) {
      return;
    }

    final exportText = _plateExportService.buildTsv(plate);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PlateExportSheet(
        exportText: exportText,
        fileName: _plateExportFileName(plate.name),
        documentExchangeService: widget.documentExchangeService,
      ),
    );
  }

  Future<void> _copyAnalysisExport(Plate plate) async {
    final report = _plateAnalysisService.analyze(plate);
    final exportText = _plateAnalysisExportService.buildTsv(plate, report);
    await Clipboard.setData(ClipboardData(text: exportText));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('분석 TSV를 클립보드에 복사했습니다.')));
  }

  Future<void> _shareAnalysisExport(
    Plate plate,
    BuildContext shareContext,
  ) async {
    final report = _plateAnalysisService.analyze(plate);
    final exportText = _plateAnalysisExportService.buildTsv(plate, report);
    final status = await widget.documentExchangeService.shareTextDocument(
      content: exportText,
      fileName: _plateAnalysisFileName(plate.name),
      mimeType: 'text/tab-separated-values',
      subject: '${plate.name} 기본 분석',
      sharePositionOrigin: _sharePositionOrigin(shareContext),
    );
    if (!mounted || status == DocumentShareStatus.dismissed) {
      return;
    }
    final message = status == DocumentShareStatus.success
        ? '분석 TSV 공유를 완료했습니다.'
        : '이 기기에서는 파일 공유를 사용할 수 없습니다.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openBulkResultImport() async {
    final plate = _plate;
    if (plate == null) {
      return;
    }

    final draft = await showModalBottomSheet<_BulkResultImportDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BulkResultImportSheet(
        plate: plate,
        service: _plateResultImportService,
        documentExchangeService: widget.documentExchangeService,
      ),
    );
    if (draft == null) {
      return;
    }

    final updated = _plateResultImportService.apply(
      plate: plate,
      preview: draft.preview,
      resultUnit: draft.resultUnit,
    );
    await _savePlate(
      updated,
      successMessage: '${draft.preview.valueCount}개 well 결과를 입력했습니다.',
    );
  }

  Future<void> _openDilutionBuilder() async {
    final plate = _plate;
    if (plate == null) {
      return;
    }

    final draft = await showModalBottomSheet<_DilutionDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DilutionBuilderSheet(
        selectedCount: _selectedPositions.length,
        suggestedColor: _groupColors[plate.groups.length % _groupColors.length],
      ),
    );

    if (draft == null) {
      return;
    }

    final group = WellGroup(
      id: 'dilution-${DateTime.now().microsecondsSinceEpoch}',
      name: draft.groupName,
      shortLabel: draft.shortLabel,
      color: draft.color,
      role: WellRole.treatment,
      concentrationUnit: draft.unit,
    );
    final updated = _plateDilutionService.applySeries(
      plate: plate,
      plan: draft.plan,
      group: group,
      replicateCount: draft.replicateCount,
      volumePerWell: draft.volumePerWell,
      volumeUnit: draft.volumeUnit,
      selectedPositions: _selectedPositions,
    );
    await _savePlate(updated);
  }

  Plate _plateWithDemoDilution(Plate plate) {
    final group = WellGroup(
      id: 'drug-a-demo',
      name: 'Drug A',
      shortLabel: 'A',
      color: _groupColors.first,
      role: WellRole.treatment,
      concentrationUnit: 'µM',
    );
    final groups = _upsertGroup(plate.groups, group);
    final updatedWells = plate.wells.map((well) {
      final row = well.position.rowIndex;
      final column = well.position.columnIndex;
      if (column < 2 && row < _demoConcentrations.length) {
        return well.copyWith(
          groupId: group.id,
          concentrationValue: _demoConcentrations[row],
          concentrationUnit: group.concentrationUnit,
          role: _demoConcentrations[row] == 0
              ? WellRole.vehicleControl
              : WellRole.treatment,
        );
      }
      return well;
    }).toList();

    return plate.copyWith(groups: groups, wells: updatedWells);
  }

  Future<void> _assignGroupToSelection() async {
    final plate = _plate;
    if (plate == null || _selectedPositions.isEmpty) {
      return;
    }

    final result = await showModalBottomSheet<_GroupDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _GroupEditorSheet(
        selectedCount: _selectedPositions.length,
        suggestedColor: _groupColors[plate.groups.length % _groupColors.length],
      ),
    );

    if (result == null) {
      return;
    }

    final group = WellGroup(
      id: 'group-${DateTime.now().microsecondsSinceEpoch}',
      name: result.name,
      shortLabel: result.shortLabel,
      color: result.color,
      role: result.role,
      concentrationUnit: result.concentrationUnit,
    );
    final updatedWells = plate.wells.map((well) {
      if (!_selectedPositions.contains(well.position)) {
        return well;
      }
      return well.copyWith(
        groupId: group.id,
        role: group.role,
        concentrationUnit: group.concentrationUnit,
      );
    }).toList();

    await _savePlate(
      plate.copyWith(groups: [...plate.groups, group], wells: updatedWells),
    );
  }

  Future<void> _editSelectedWell() async {
    final well = _selectedWell;
    final plate = _plate;
    if (well == null || plate == null) {
      return;
    }

    final updated = await showModalBottomSheet<Well>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _WellRecordSheet(well: well),
    );

    if (updated == null) {
      return;
    }

    final updatedWells = plate.wells
        .map(
          (candidate) =>
              candidate.position == updated.position ? updated : candidate,
        )
        .toList();
    await _savePlate(plate.copyWith(wells: updatedWells));
  }

  Future<bool> _savePlate(
    Plate plate, {
    String successMessage = 'plate layout을 저장했습니다.',
    bool recordHistory = true,
  }) async {
    final previous = _plate;
    setState(() => _isSaving = true);
    try {
      await widget.repository.savePlate(plate);
    } on Object catch (error) {
      if (!mounted) {
        return false;
      }
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Plate를 저장하지 못했습니다: $error')));
      return false;
    }
    if (!mounted) {
      return false;
    }
    setState(() {
      if (recordHistory && previous != null) {
        _undoHistory.add(previous);
        if (_undoHistory.length > 20) {
          _undoHistory.removeAt(0);
        }
      }
      _plate = plate;
      _isSaving = false;
      _lastSavedAt = DateTime.now();
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(successMessage),
          action: recordHistory
              ? SnackBarAction(label: '실행 취소', onPressed: _undoLastChange)
              : null,
        ),
      );
    return true;
  }

  Future<void> _undoLastChange() async {
    if (_undoHistory.isEmpty || _isSaving) {
      return;
    }
    final previous = _undoHistory.removeLast();
    final restored = await _savePlate(
      previous,
      successMessage: '마지막 Plate 변경을 취소했습니다.',
      recordHistory: false,
    );
    if (!restored && mounted) {
      setState(() => _undoHistory.add(previous));
    }
  }

  List<WellGroup> _upsertGroup(List<WellGroup> groups, WellGroup group) {
    final updated = [...groups];
    final index = updated.indexWhere((candidate) => candidate.id == group.id);
    if (index == -1) {
      updated.add(group);
    } else {
      updated[index] = group;
    }
    return updated;
  }
}

class _PlateSaveStatus extends StatelessWidget {
  const _PlateSaveStatus({required this.isSaving, required this.lastSavedAt});

  final bool isSaving;
  final DateTime? lastSavedAt;

  @override
  Widget build(BuildContext context) {
    final time = lastSavedAt;
    final label = isSaving
        ? '저장 중…'
        : time == null
            ? '아직 저장되지 않음'
            : '저장됨 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isSaving ? Icons.sync : Icons.cloud_done_outlined,
          size: 14,
          color: Colors.black54,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          key: const ValueKey('plate-save-status'),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }
}

class _ExperimentHeaderCard extends StatelessWidget {
  const _ExperimentHeaderCard({required this.title, required this.series});

  final String title;
  final List<double> series;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'A/B열 기준으로 ${series.join(' → ')} µM 농도 패턴을 저장합니다.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlateGrid extends StatelessWidget {
  const _PlateGrid({
    required this.plate,
    required this.selectedPositions,
    required this.requestedCellSize,
    required this.onZoomOut,
    required this.onFit,
    required this.onZoomIn,
    required this.onSelected,
    required this.onRangeSelected,
    required this.onRowSelected,
    required this.onColumnSelected,
  });

  static const _spacing = 6.0;
  static const _cardPadding = 14.0;

  final Plate plate;
  final Set<WellPosition> selectedPositions;
  final double? requestedCellSize;
  final VoidCallback? onZoomOut;
  final VoidCallback? onFit;
  final VoidCallback? onZoomIn;
  final ValueChanged<WellPosition> onSelected;
  final ValueChanged<WellPosition> onRangeSelected;
  final ValueChanged<int> onRowSelected;
  final ValueChanged<int> onColumnSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    requestedCellSize == null
                        ? 'Plate 화면 맞춤'
                        : 'Plate ${requestedCellSize!.round()}px',
                    key: const ValueKey('plate-zoom-label'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('plate-zoom-out-button'),
                  tooltip: 'Plate 축소',
                  onPressed: onZoomOut,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                IconButton(
                  key: const ValueKey('plate-fit-button'),
                  tooltip: 'Plate 화면 맞춤',
                  onPressed: onFit,
                  icon: const Icon(Icons.fit_screen_outlined),
                ),
                IconButton(
                  key: const ValueKey('plate-zoom-in-button'),
                  tooltip: 'Plate 확대',
                  onPressed: onZoomIn,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            if (requestedCellSize != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '좌우로 밀어 숨겨진 well을 확인하세요.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                final gridColumnCount = plate.columnCount + 1;
                final gridRowCount = plate.rowCount + 1;
                final fitCellSize =
                    (constraints.maxWidth - _spacing * (gridColumnCount - 1)) /
                        gridColumnCount;
                final cellSize = requestedCellSize ?? fitCellSize;
                final gridWidth = cellSize * gridColumnCount +
                    _spacing * (gridColumnCount - 1);
                final gridHeight =
                    cellSize * gridRowCount + _spacing * (gridRowCount - 1);

                return Scrollbar(
                  child: SingleChildScrollView(
                    key: const ValueKey('plate-horizontal-scroll'),
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: gridWidth,
                      height: gridHeight,
                      child: GridView.builder(
                        key: const ValueKey('plate-grid'),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: gridRowCount * gridColumnCount,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: gridColumnCount,
                          mainAxisSpacing: _spacing,
                          crossAxisSpacing: _spacing,
                        ),
                        itemBuilder: (context, index) =>
                            _buildCell(context, index, gridColumnCount),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(BuildContext context, int index, int gridColumnCount) {
    final row = index ~/ gridColumnCount;
    final column = index % gridColumnCount;

    if (row == 0 && column == 0) {
      return const SizedBox.shrink();
    }
    if (row == 0) {
      final columnIndex = column - 1;
      return _HeaderCell(
        key: ValueKey('column-header-${columnIndex + 1}'),
        label: '${columnIndex + 1}',
        semanticLabel: '${columnIndex + 1}열 전체 선택',
        onTap: () => onColumnSelected(columnIndex),
      );
    }
    if (column == 0) {
      final rowIndex = row - 1;
      final rowLabel = String.fromCharCode('A'.codeUnitAt(0) + rowIndex);
      return _HeaderCell(
        key: ValueKey('row-header-$rowLabel'),
        label: rowLabel,
        semanticLabel: '$rowLabel행 전체 선택',
        onTap: () => onRowSelected(rowIndex),
      );
    }

    final position = WellPosition(rowIndex: row - 1, columnIndex: column - 1);
    final well = plate.wellAt(position);
    final group = well.groupId == null
        ? null
        : plate.groups.cast<WellGroup?>().firstWhere(
              (candidate) => candidate?.id == well.groupId,
              orElse: () => null,
            );

    return _WellCell(
      key: ValueKey('well-${well.label}'),
      well: well,
      group: group,
      selected: selectedPositions.contains(position),
      onTap: () => onSelected(position),
      onLongPress: () => onRangeSelected(position),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    super.key,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7D6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class _WellCell extends StatelessWidget {
  const _WellCell({
    required this.well,
    required this.group,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final Well well;
  final WellGroup? group;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final hasDose = well.concentrationValue != null;
    final background = group?.color ??
        (hasDose ? const Color(0xFFE6D9FF) : const Color(0xFFF2F2F7));
    final borderColor = selected ? Colors.black : Colors.transparent;
    final label = group?.shortLabel.isNotEmpty == true ? group!.shortLabel : '';

    final concentrationLabel = hasDose
        ? ', 농도 ${_formatDose(well.concentrationValue!)} ${well.concentrationUnit}'
        : '';
    final groupLabel = group == null ? '' : ', 그룹 ${group!.name}';

    return Semantics(
      label: '${well.label} well$concentrationLabel$groupLabel',
      hint: '탭하여 선택, 길게 눌러 범위 선택',
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Text(
            hasDose
                ? '${label.isEmpty ? '' : '$label\n'}${_formatDose(well.concentrationValue!)}'
                : label.isEmpty
                    ? well.label
                    : label,
            maxLines: 2,
            overflow: TextOverflow.fade,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: hasDose ? 8 : 7,
              height: 0.9,
              fontWeight: hasDose || label.isNotEmpty
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: hasDose || label.isNotEmpty
                  ? const Color(0xFF4B208C)
                  : const Color(0xFF8E8E93),
            ),
          ),
        ),
      ),
    );
  }
}

class _BulkResultImportSheet extends StatefulWidget {
  const _BulkResultImportSheet({
    required this.plate,
    required this.service,
    required this.documentExchangeService,
  });

  final Plate plate;
  final PlateResultImportService service;
  final DocumentExchangeService documentExchangeService;

  @override
  State<_BulkResultImportSheet> createState() => _BulkResultImportSheetState();
}

class _BulkResultImportSheetState extends State<_BulkResultImportSheet> {
  final _matrixController = TextEditingController();
  final _unitController = TextEditingController(text: 'OD450');
  late PlateResultImportPreview _preview;

  @override
  void initState() {
    super.initState();
    _preview = widget.service.parseMatrix(text: '');
    _matrixController.addListener(_updatePreview);
  }

  @override
  void dispose() {
    _matrixController
      ..removeListener(_updatePreview)
      ..dispose();
    _unitController.dispose();
    super.dispose();
  }

  void _updatePreview() {
    setState(() {
      _preview = widget.service.parseMatrix(
        text: _matrixController.text,
        rowCount: widget.plate.rowCount,
        columnCount: widget.plate.columnCount,
      );
    });
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) {
      return;
    }
    _matrixController.text = data!.text!;
  }

  Future<void> _pickResultFile() async {
    final document = await widget.documentExchangeService.pickTextDocument(
      allowedExtensions: const ['csv', 'tsv', 'txt'],
    );
    if (!mounted || document == null) {
      return;
    }
    _matrixController.text = document.content;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('“${document.name}” 결과 파일을 불러왔습니다.')),
    );
  }

  int get _overwriteCount => _preview.values.keys
      .where((position) => widget.plate.wellAt(position).resultValue != null)
      .length;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Plate 결과 일괄 입력',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Excel이나 Plate reader에서 복사한 행렬을 붙여넣거나 CSV/TSV/TXT 파일을 선택하세요. 첫 행의 1–12와 첫 열의 A–H 좌표는 자동으로 인식합니다.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('bulk-result-matrix-field'),
            controller: _matrixController,
            minLines: 7,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: '결과 행렬',
              alignLabelWithHint: true,
              hintText: r'\t1\t2\t3\nA\t0.82\t0.79\t0.85\nB\t0.80\t0.81\t0.83',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                key: const ValueKey('pick-bulk-result-file-button'),
                onPressed: _pickResultFile,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('파일 선택'),
              ),
              TextButton.icon(
                onPressed: _pasteClipboard,
                icon: const Icon(Icons.content_paste),
                label: const Text('클립보드 붙여넣기'),
              ),
            ],
          ),
          TextField(
            key: const ValueKey('bulk-result-unit-field'),
            controller: _unitController,
            decoration: const InputDecoration(
              labelText: '결과 단위',
              hintText: '예: OD450',
            ),
          ),
          const SizedBox(height: 14),
          _BulkResultImportPreviewCard(
            preview: _preview,
            overwriteCount: _overwriteCount,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('apply-bulk-results-button'),
              onPressed: _preview.canApply
                  ? () => Navigator.of(context).pop(
                        _BulkResultImportDraft(
                          preview: _preview,
                          resultUnit: _unitController.text.trim(),
                        ),
                      )
                  : null,
              icon: const Icon(Icons.check),
              label: Text('${_preview.valueCount}개 결과 적용'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulkResultImportPreviewCard extends StatelessWidget {
  const _BulkResultImportPreviewCard({
    required this.preview,
    required this.overwriteCount,
  });

  final PlateResultImportPreview preview;
  final int overwriteCount;

  @override
  Widget build(BuildContext context) {
    final hasIssues = preview.issues.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasIssues
            ? Theme.of(context).colorScheme.errorContainer
            : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            preview.valueCount == 0
                ? '붙여넣을 데이터를 기다리고 있습니다.'
                : '${preview.detectedRowCount}행 × ${preview.detectedColumnCount}열 · 숫자 ${preview.valueCount}개 인식',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (preview.values.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              preview.values.entries
                  .take(6)
                  .map(
                    (entry) => '${entry.key.label}=${_formatDose(entry.value)}',
                  )
                  .join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (overwriteCount > 0) ...[
            const SizedBox(height: 6),
            Text('기존 결과 $overwriteCount개를 덮어씁니다.'),
          ],
          if (hasIssues) ...[
            const SizedBox(height: 8),
            for (final issue in preview.issues.take(4))
              Text(
                '${issue.rowNumber}행 ${issue.columnNumber}열 “${issue.value}”: ${issue.message}',
              ),
            if (preview.issues.length > 4)
              Text('그 외 ${preview.issues.length - 4}개 오류'),
          ],
        ],
      ),
    );
  }
}

class _BulkResultImportDraft {
  const _BulkResultImportDraft({
    required this.preview,
    required this.resultUnit,
  });

  final PlateResultImportPreview preview;
  final String resultUnit;
}

class _PlateExportSheet extends StatelessWidget {
  const _PlateExportSheet({
    required this.exportText,
    required this.fileName,
    required this.documentExchangeService,
  });

  final String exportText;
  final String fileName;
  final DocumentExchangeService documentExchangeService;

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
            'Plate 내보내기',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text('TSV를 복사하거나 파일로 공유해 메모, 엑셀, 구글시트에서 열 수 있습니다.'),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 280),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(18),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                exportText,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: exportText));
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Plate 내보내기 텍스트를 복사했습니다.')),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('복사하기'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Builder(
                  builder: (shareContext) => FilledButton.icon(
                    key: const ValueKey('share-plate-file-button'),
                    onPressed: () async {
                      try {
                        final status =
                            await documentExchangeService.shareTextDocument(
                          content: exportText,
                          fileName: fileName,
                          mimeType: 'text/tab-separated-values',
                          subject: 'EasyCheck Plate 내보내기',
                          sharePositionOrigin: _sharePositionOrigin(
                            shareContext,
                          ),
                        );
                        if (!context.mounted ||
                            status == DocumentShareStatus.dismissed) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              status == DocumentShareStatus.success
                                  ? 'Plate TSV 파일을 공유했습니다.'
                                  : '이 기기에서는 파일 공유를 사용할 수 없습니다.',
                            ),
                          ),
                        );
                      } on Object catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Plate 파일을 공유하지 못했습니다: $error'),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.ios_share_outlined),
                    label: const Text('파일 공유'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlateSummaryCard extends StatelessWidget {
  const _PlateSummaryCard({required this.plate});

  final Plate plate;

  @override
  Widget build(BuildContext context) {
    final summaries = _buildSummaries();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '실험군 · 농도 요약',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (summaries.isEmpty)
              const Text('아직 지정된 실험군이 없습니다. 그룹 지정 또는 희석 계산을 먼저 적용하세요.')
            else
              for (final summary in summaries) ...[
                _GroupSummaryRow(summary: summary),
                if (summary != summaries.last) const Divider(height: 20),
              ],
          ],
        ),
      ),
    );
  }

  List<_GroupSummary> _buildSummaries() {
    return [
      for (final group in plate.groups)
        _GroupSummary.from(
          group: group,
          wells: plate.wells.where((well) => well.groupId == group.id).toList(),
        ),
    ].where((summary) => summary.wellCount > 0).toList();
  }
}

class _GroupSummaryRow extends StatelessWidget {
  const _GroupSummaryRow({required this.summary});

  final _GroupSummary summary;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(
            color: summary.color,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${summary.name} (${summary.shortLabel})',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text('${summary.wellCount} wells · ${summary.role.label}'),
              if (summary.concentrationLabels.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  summary.concentrationLabels.join(' → '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupSummary {
  const _GroupSummary({
    required this.name,
    required this.shortLabel,
    required this.color,
    required this.role,
    required this.wellCount,
    required this.concentrationLabels,
  });

  factory _GroupSummary.from({
    required WellGroup group,
    required List<Well> wells,
  }) {
    final concentrations = wells
        .map((well) => well.concentrationValue)
        .nonNulls
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return _GroupSummary(
      name: group.name,
      shortLabel: group.shortLabel,
      color: group.color,
      role: group.role,
      wellCount: wells.length,
      concentrationLabels: [
        for (final concentration in concentrations)
          '${_formatDose(concentration)} ${group.concentrationUnit}',
      ],
    );
  }

  final String name;
  final String shortLabel;
  final Color color;
  final WellRole role;
  final int wellCount;
  final List<String> concentrationLabels;
}

class _PlateAnalysisCard extends StatelessWidget {
  const _PlateAnalysisCard({
    required this.report,
    required this.onCopy,
    required this.onShare,
  });

  final PlateAnalysisReport report;
  final Future<void> Function() onCopy;
  final Future<void> Function(BuildContext context) onShare;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('plate-analysis-card'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '기본 결과 분석',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (report.hasResults)
                  Text(
                    '사용 ${report.includedWellCount} · 제외 ${report.excludedWellCount}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!report.hasResults)
              const Text('측정 결과를 입력하면 실험군·농도별 평균과 반복 오차를 계산합니다.')
            else ...[
              Text(
                '분석 제외 well은 계산에서 빼고, 같은 실험군·농도·결과 단위를 반복 측정으로 묶습니다. 정규화 기준은 Vehicle → Untreated → Negative control 순으로 선택합니다.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              _AnalysisReferenceSummary(report: report),
              const SizedBox(height: 12),
              _AnalysisConcentrationCharts(report: report),
              const SizedBox(height: 12),
              for (final series in report.series) ...[
                _AnalysisSeriesRow(series: series),
                if (series != report.series.last) const Divider(height: 20),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('copy-analysis-tsv-button'),
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('분석 TSV 복사'),
                  ),
                  Builder(
                    builder: (shareContext) => FilledButton.icon(
                      key: const ValueKey('share-analysis-file-button'),
                      onPressed: () => onShare(shareContext),
                      icon: const Icon(Icons.ios_share_outlined),
                      label: const Text('분석 파일 공유'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnalysisConcentrationCharts extends StatelessWidget {
  const _AnalysisConcentrationCharts({required this.report});

  final PlateAnalysisReport report;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<PlateAnalysisSeries>>{};
    for (final series in report.series.where(_isChartSeries)) {
      final key = [
        series.label,
        series.concentrationUnit ?? '',
        series.resultUnit,
      ].join('\u0000');
      groups.putIfAbsent(key, () => []).add(series);
    }
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '농도별 차트',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '기초 확인용 기술 통계입니다. 곡선 적합이나 IC50 계산은 포함하지 않습니다.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        for (final entry in groups.entries) ...[
          _AnalysisConcentrationChart(series: entry.value),
          if (entry.key != groups.keys.last) const SizedBox(height: 12),
        ],
      ],
    );
  }

  static bool _isChartSeries(PlateAnalysisSeries series) {
    return series.concentrationValue != null &&
        switch (series.role) {
          WellRole.treatment || WellRole.sample || WellRole.standard => true,
          _ => false,
        };
  }
}

class _AnalysisConcentrationChart extends StatelessWidget {
  const _AnalysisConcentrationChart({required this.series});

  final List<PlateAnalysisSeries> series;

  @override
  Widget build(BuildContext context) {
    final points = [...series]
      ..sort((a, b) => a.concentrationValue!.compareTo(b.concentrationValue!));
    final useNormalized = points.every(
      (point) => point.normalizedPercent != null,
    );
    final values = [
      for (final point in points)
        useNormalized ? point.normalizedPercent! : point.blankCorrectedMean,
    ];
    final minimum = values.fold<double>(
      0,
      (current, value) => value < current ? value : current,
    );
    final maximum = values.fold<double>(
      0,
      (current, value) => value > current ? value : current,
    );
    final range = maximum - minimum;
    final zeroFraction = range == 0 ? 0.0 : (0 - minimum) / range;
    final first = points.first;
    final unit = first.concentrationUnit ?? '';

    return Container(
      key: ValueKey('analysis-chart-${first.label}-${first.resultUnit}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${first.label} · ${first.resultUnit}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            useNormalized ? 'Control 대비 (%)' : 'Blank 보정 결과',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < points.length; index++) ...[
            _AnalysisBarRow(
              label: '${_formatDose(points[index].concentrationValue!)} $unit',
              value: values[index],
              minimum: minimum,
              maximum: maximum,
              zeroFraction: zeroFraction,
            ),
            if (index != points.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _AnalysisBarRow extends StatelessWidget {
  const _AnalysisBarRow({
    required this.label,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.zeroFraction,
  });

  final String label;
  final double value;
  final double minimum;
  final double maximum;
  final double zeroFraction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(
          child: SizedBox(
            height: 22,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final range = maximum - minimum;
                final valueFraction =
                    range == 0 ? 0.0 : (value - minimum) / range;
                final zeroX = width * zeroFraction;
                final valueX = width * valueFraction;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    Positioned(
                      left: zeroX.clamp(0, width),
                      top: 0,
                      bottom: 0,
                      child: Container(width: 1, color: Colors.black26),
                    ),
                    Positioned(
                      left: valueX < zeroX ? valueX : zeroX,
                      width: (valueX - zeroX).abs().clamp(2, width),
                      top: 3,
                      bottom: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: value < 0
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 54,
          child: Text(
            _formatAnalysisNumber(value),
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _AnalysisReferenceSummary extends StatelessWidget {
  const _AnalysisReferenceSummary({required this.report});

  final PlateAnalysisReport report;

  @override
  Widget build(BuildContext context) {
    final units = {
      ...report.blankMeanByUnit.keys,
      ...report.controlByUnit.keys,
    }.toList()
      ..sort();
    if (units.isEmpty) {
      return Text(
        'Blank 또는 normalization control이 없어 raw 결과만 표시합니다.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final unit in units)
          Chip(
            label: Text(_referenceLabel(unit)),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  String _referenceLabel(String unit) {
    final blank = report.blankMeanByUnit[unit];
    final control = report.controlByUnit[unit];
    final parts = <String>[
      unit,
      if (blank != null) 'Blank ${_formatAnalysisNumber(blank)}',
      if (control != null)
        '${control.role.label} ${_formatAnalysisNumber(control.rawMean)}',
    ];
    return parts.join(' · ');
  }
}

class _AnalysisSeriesRow extends StatelessWidget {
  const _AnalysisSeriesRow({required this.series});

  final PlateAnalysisSeries series;

  @override
  Widget build(BuildContext context) {
    final concentration = series.concentrationValue == null
        ? '농도 미지정'
        : '${_formatDose(series.concentrationValue!)} ${series.concentrationUnit ?? ''}';
    return Column(
      key: ValueKey(
        'analysis-${series.label}-${series.concentrationValue}-${series.resultUnit}',
      ),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${series.label} · $concentration',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          '${series.resultUnit} · n=${series.replicateCount} · ${series.includedWellLabels.join(', ')}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _AnalysisMetric(
              label: '평균',
              value: _formatAnalysisNumber(series.rawMean),
            ),
            _AnalysisMetric(
              label: 'Blank 보정',
              value: _formatAnalysisNumber(series.blankCorrectedMean),
            ),
            _AnalysisMetric(
              label: 'SD',
              value: series.standardDeviation == null
                  ? 'n 부족'
                  : _formatAnalysisNumber(series.standardDeviation!),
            ),
            _AnalysisMetric(
              label: 'CV',
              value: series.coefficientOfVariation == null
                  ? '계산 불가'
                  : '${_formatAnalysisNumber(series.coefficientOfVariation!)}%',
            ),
            _AnalysisMetric(
              label: 'Control 대비',
              value: series.normalizedPercent == null
                  ? '기준 없음'
                  : '${_formatAnalysisNumber(series.normalizedPercent!)}%',
            ),
          ],
        ),
        if (series.excludedCount > 0) ...[
          const SizedBox(height: 6),
          Text(
            '분석 제외 ${series.excludedCount}개 · ${series.excludedWellLabels.join(', ')}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ],
    );
  }
}

class _AnalysisMetric extends StatelessWidget {
  const _AnalysisMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$label · $value'),
    );
  }
}

String _formatAnalysisNumber(double value) {
  if (!value.isFinite) {
    return '-';
  }
  final absolute = value.abs();
  if (absolute != 0 && (absolute >= 10000 || absolute < 0.001)) {
    return value.toStringAsExponential(3);
  }
  final fixed = value.toStringAsFixed(3);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

class _PlateValidationCard extends StatelessWidget {
  const _PlateValidationCard({required this.report});

  final PlateValidationReport report;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasWarnings = report.warningCount > 0;
    return Card(
      key: const ValueKey('plate-validation-card'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasWarnings
                      ? Icons.warning_amber_rounded
                      : Icons.task_alt_rounded,
                  color: hasWarnings ? colorScheme.error : Colors.green,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '실험 준비 점검',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Text(
                  hasWarnings ? '경고 ${report.warningCount}' : '필수 경고 없음',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: hasWarnings ? colorScheme.error : Colors.green,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (report.issues.isEmpty)
              const Text('현재 layout에서 발견된 준비 오류가 없습니다.')
            else
              for (final issue in report.issues) ...[
                _PlateValidationIssueRow(issue: issue),
                if (issue != report.issues.last) const Divider(height: 20),
              ],
          ],
        ),
      ),
    );
  }
}

class _PlateValidationIssueRow extends StatelessWidget {
  const _PlateValidationIssueRow({required this.issue});

  final PlateValidationIssue issue;

  @override
  Widget build(BuildContext context) {
    final isWarning = issue.severity == PlateValidationSeverity.warning;
    final color = isWarning
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    final labels = issue.wellLabels.take(8).join(', ');
    final remaining = issue.wellLabels.length - 8;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWarning ? Icons.error_outline : Icons.info_outline,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(issue.message),
                if (labels.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    remaining > 0 ? '$labels 외 $remaining개' : labels,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionSummaryCard extends StatelessWidget {
  const _SelectionSummaryCard({
    required this.selectedCount,
    required this.rangeAnchor,
    required this.onStartRange,
    required this.onAssignGroup,
    required this.onApplyDilution,
  });

  final int selectedCount;
  final WellPosition? rangeAnchor;
  final VoidCallback? onStartRange;
  final VoidCallback? onAssignGroup;
  final VoidCallback onApplyDilution;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selectedCount == 0 ? '선택 영역 없음' : '$selectedCount개 well 선택됨',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              rangeAnchor == null
                  ? '행/열 헤더를 탭하거나 well을 길게 눌러 범위를 선택할 수 있습니다.'
                  : '${rangeAnchor!.label}부터 끝 well을 탭하면 사각형 범위를 선택합니다.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onStartRange,
                  icon: const Icon(Icons.select_all_outlined),
                  label: const Text('범위 시작'),
                ),
                FilledButton.icon(
                  onPressed: onAssignGroup,
                  icon: const Icon(Icons.palette_outlined),
                  label: const Text('그룹 지정'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onApplyDilution,
                  icon: const Icon(Icons.water_drop_outlined),
                  label: const Text('희석 계산'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WellRecordSheet extends StatefulWidget {
  const _WellRecordSheet({required this.well});

  final Well well;

  @override
  State<_WellRecordSheet> createState() => _WellRecordSheetState();
}

class _WellRecordSheetState extends State<_WellRecordSheet> {
  late final TextEditingController _concentrationController;
  late final TextEditingController _concentrationUnitController;
  late final TextEditingController _resultController;
  late final TextEditingController _resultUnitController;
  late final TextEditingController _noteController;
  late bool _excluded;

  @override
  void initState() {
    super.initState();
    final well = widget.well;
    _concentrationController = TextEditingController(
      text: well.concentrationValue == null
          ? ''
          : _formatDose(well.concentrationValue!),
    );
    _concentrationUnitController = TextEditingController(
      text: well.concentrationUnit ?? 'µM',
    );
    _resultController = TextEditingController(
      text: well.resultValue == null ? '' : _formatDose(well.resultValue!),
    );
    _resultUnitController = TextEditingController(
      text: well.resultUnit ?? 'OD450',
    );
    _noteController = TextEditingController(text: well.note);
    _excluded = well.excluded;
  }

  @override
  void dispose() {
    _concentrationController.dispose();
    _concentrationUnitController.dispose();
    _resultController.dispose();
    _resultUnitController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _save() {
    final well = widget.well;
    final concentration = double.tryParse(_concentrationController.text.trim());
    final result = double.tryParse(_resultController.text.trim());
    final concentrationUnit = _concentrationUnitController.text.trim();
    final resultUnit = _resultUnitController.text.trim();
    final nextRole = concentration == 0
        ? WellRole.vehicleControl
        : well.role == WellRole.empty && concentration != null
            ? WellRole.treatment
            : well.role;

    Navigator.of(context).pop(
      well.copyWith(
        concentrationValue: concentration,
        concentrationUnit: concentrationUnit.isEmpty ? null : concentrationUnit,
        role: nextRole,
        resultValue: result,
        resultUnit: result == null || resultUnit.isEmpty ? null : resultUnit,
        note: _noteController.text.trim(),
        excluded: _excluded,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.well.label} well 기록',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '처리 농도와 측정 결과를 함께 기록합니다.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          Text(
            '처리 조건',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _concentrationController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '농도'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _concentrationUnitController,
                  decoration: const InputDecoration(labelText: '단위'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '측정 결과',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  key: const ValueKey('well-result-value-field'),
                  controller: _resultController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '결과값',
                    hintText: '예: 0.82',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('well-result-unit-field'),
                  controller: _resultUnitController,
                  decoration: const InputDecoration(
                    labelText: '결과 단위',
                    hintText: 'OD450',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('well-note-field'),
            controller: _noteController,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Well 메모',
              hintText: '침전, 기포, 오염 의심 등',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            key: const ValueKey('well-excluded-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('분석에서 제외'),
            subtitle: const Text('이상치나 실험 오류가 있는 well을 표시합니다.'),
            value: _excluded,
            onChanged: (value) => setState(() => _excluded = value),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('save-well-record-button'),
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Well 기록 저장'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WellDetailCard extends StatelessWidget {
  const _WellDetailCard({
    required this.well,
    required this.group,
    required this.onEdit,
  });

  final Well? well;
  final WellGroup? group;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final selected = well;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selected == null ? 'Well 상세' : '${selected.label} 상세',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              selected == null
                  ? 'plate에서 well을 선택하면 처리 조건과 측정 결과를 확인합니다.'
                  : selected.concentrationValue == null
                      ? '${group?.name ?? '그룹 없음'} · 농도 미지정'
                      : '${group?.name ?? selected.role.label} · ${_formatDose(selected.concentrationValue!)} ${selected.concentrationUnit ?? ''}',
            ),
            if (selected != null) ...[
              const SizedBox(height: 10),
              Text(
                selected.resultValue == null
                    ? '측정 결과 미입력'
                    : '결과 · ${_formatDose(selected.resultValue!)} ${selected.resultUnit ?? ''}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: selected.resultValue == null
                          ? FontWeight.w400
                          : FontWeight.w700,
                    ),
              ),
              if (selected.note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '메모 · ${selected.note}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (selected.excluded) ...[
                const SizedBox(height: 8),
                const Chip(
                  avatar: Icon(Icons.remove_circle_outline, size: 18),
                  label: Text('분석 제외'),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('농도 · 결과 편집'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DilutionBuilderSheet extends StatefulWidget {
  const _DilutionBuilderSheet({
    required this.selectedCount,
    required this.suggestedColor,
  });

  final int selectedCount;
  final Color suggestedColor;

  @override
  State<_DilutionBuilderSheet> createState() => _DilutionBuilderSheetState();
}

class _DilutionBuilderSheetState extends State<_DilutionBuilderSheet> {
  final _groupController = TextEditingController(text: 'Drug A');
  final _labelController = TextEditingController(text: 'A');
  final _startController = TextEditingController(text: '1000');
  final _factorController = TextEditingController(text: '2');
  final _stepsController = TextEditingController(text: '6');
  final _replicateController = TextEditingController(text: '2');
  final _unitController = TextEditingController(text: 'µM');
  final _stockController = TextEditingController(text: '10000');
  final _volumeController = TextEditingController(text: '100');
  final _overageController = TextEditingController(text: '10');
  final _dilutionService = const DilutionService();
  final _pipettingPlanService = const PipettingPlanService();
  late Color _color = widget.suggestedColor;
  bool _includeZeroControl = true;
  DilutionDirection _direction = DilutionDirection.topToBottom;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _startController,
      _factorController,
      _stepsController,
      _replicateController,
      _unitController,
      _stockController,
      _volumeController,
      _overageController,
    ]) {
      controller.addListener(_refreshPreview);
    }
  }

  void _refreshPreview() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _groupController.dispose();
    _labelController.dispose();
    _startController.dispose();
    _factorController.dispose();
    _stepsController.dispose();
    _replicateController.dispose();
    _unitController.dispose();
    _stockController.dispose();
    _volumeController.dispose();
    _overageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '희석 계산 적용',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            widget.selectedCount == 0
                ? '선택 영역이 없어서 plate 앞쪽 well부터 자동으로 채웁니다.'
                : '${widget.selectedCount}개 선택 well에 순서대로 농도를 적용합니다.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _groupController,
            decoration: const InputDecoration(labelText: '실험군/약물명'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _labelController,
            maxLength: 3,
            decoration: const InputDecoration(labelText: '짧은 라벨'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '시작 농도'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _unitController,
                  decoration: const InputDecoration(labelText: '단위'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _factorController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '희석 배수'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _stepsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '단계 수'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _replicateController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '반복 well 수'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<DilutionDirection>(
            initialValue: _direction,
            decoration: const InputDecoration(labelText: '적용 방향'),
            items: DilutionDirection.values
                .map(
                  (direction) => DropdownMenuItem(
                    value: direction,
                    child: Text(direction.label),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(
              () => _direction = value ?? DilutionDirection.topToBottom,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('0 농도 control 포함'),
            value: _includeZeroControl,
            onChanged: (value) => setState(() => _includeZeroControl = value),
          ),
          const SizedBox(height: 8),
          Text(
            '피펫팅 계획',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '각 농도를 stock에서 직접 희석하는 master mix 기준입니다.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('pipetting-stock-field'),
                  controller: _stockController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Stock 농도'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('pipetting-volume-field'),
                  controller: _volumeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Well당 최종 부피',
                    suffixText: 'µL',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('pipetting-overage-field'),
                  controller: _overageController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '여유분 (%)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PipettingPlanPreview(
            plan: _pipettingPlan,
            requiredWellCount: _requiredWellCount,
            selectedCount: widget.selectedCount,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final color in _PlateEditorScreenState._groupColors)
                ChoiceChip(
                  label: const Text(''),
                  selected: color == _color,
                  onSelected: (_) => setState(() => _color = color),
                  avatar: CircleAvatar(backgroundColor: color),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('희석 적용'),
            ),
          ),
        ],
      ),
    );
  }

  int? get _requiredWellCount {
    final steps = int.tryParse(_stepsController.text.trim());
    final replicates = int.tryParse(_replicateController.text.trim());
    if (steps == null || steps <= 0 || replicates == null || replicates <= 0) {
      return null;
    }
    return (steps + (_includeZeroControl ? 1 : 0)) * replicates;
  }

  PipettingPlan? get _pipettingPlan {
    final start = double.tryParse(_startController.text.trim());
    final factor = double.tryParse(_factorController.text.trim());
    final steps = int.tryParse(_stepsController.text.trim());
    final replicates = int.tryParse(_replicateController.text.trim());
    final stock = double.tryParse(_stockController.text.trim());
    final volume = double.tryParse(_volumeController.text.trim());
    final overage = double.tryParse(_overageController.text.trim());
    if (start == null ||
        factor == null ||
        steps == null ||
        replicates == null ||
        stock == null ||
        volume == null ||
        overage == null ||
        start < 0 ||
        factor <= 0 ||
        steps <= 0 ||
        replicates <= 0) {
      return null;
    }
    try {
      final concentrations = _dilutionService.buildSeries(
        DilutionPlan(
          startConcentration: start,
          dilutionFactor: factor,
          steps: steps,
          includeZeroControl: _includeZeroControl,
          direction: _direction,
        ),
      );
      return _pipettingPlanService.buildDirectDilutionPlan(
        stockConcentration: stock,
        concentrationUnit: _unitController.text.trim().isEmpty
            ? 'µM'
            : _unitController.text.trim(),
        concentrations: concentrations,
        volumePerWell: volume,
        volumeUnit: 'µL',
        replicateCount: replicates,
        overagePercent: overage,
      );
    } on ArgumentError {
      return null;
    }
  }

  void _save() {
    final groupName = _groupController.text.trim();
    final startConcentration = double.tryParse(_startController.text.trim());
    final dilutionFactor = double.tryParse(_factorController.text.trim());
    final steps = int.tryParse(_stepsController.text.trim());
    final replicateCount = int.tryParse(_replicateController.text.trim());
    final volumePerWell = double.tryParse(_volumeController.text.trim());
    final pipettingPlan = _pipettingPlan;
    final unit = _unitController.text.trim().isEmpty
        ? 'µM'
        : _unitController.text.trim();

    if (groupName.isEmpty ||
        startConcentration == null ||
        dilutionFactor == null ||
        steps == null ||
        replicateCount == null ||
        volumePerWell == null ||
        pipettingPlan == null ||
        startConcentration < 0 ||
        dilutionFactor <= 0 ||
        steps <= 0 ||
        replicateCount <= 0 ||
        volumePerWell <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('희석 계산 값을 확인해주세요.')));
      return;
    }

    final requiredWellCount = _requiredWellCount!;
    final availableWellCount =
        widget.selectedCount == 0 ? 96 : widget.selectedCount;
    if (availableWellCount < requiredWellCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '사용 가능한 well이 부족합니다. $requiredWellCount개가 필요하지만 $availableWellCount개만 사용할 수 있습니다.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      _DilutionDraft(
        groupName: groupName,
        shortLabel: _labelController.text.trim().isEmpty
            ? groupName.characters.first
            : _labelController.text.trim(),
        color: _color,
        unit: unit,
        replicateCount: replicateCount,
        volumePerWell: volumePerWell,
        volumeUnit: pipettingPlan.volumeUnit,
        plan: DilutionPlan(
          startConcentration: startConcentration,
          dilutionFactor: dilutionFactor,
          steps: steps,
          includeZeroControl: _includeZeroControl,
          direction: _direction,
        ),
      ),
    );
  }
}

class _PipettingPlanPreview extends StatelessWidget {
  const _PipettingPlanPreview({
    required this.plan,
    required this.requiredWellCount,
    required this.selectedCount,
  });

  final PipettingPlan? plan;
  final int? requiredWellCount;
  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    final currentPlan = plan;
    final required = requiredWellCount;
    final availableWellCount = selectedCount == 0 ? 96 : selectedCount;
    final insufficientSelection =
        required != null && availableWellCount < required;
    if (currentPlan == null) {
      return Card(
        key: const ValueKey('pipetting-plan-preview'),
        color: Theme.of(context).colorScheme.errorContainer,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Stock 농도는 시작 농도 이상이어야 하며 부피와 여유분을 확인해주세요.'),
        ),
      );
    }

    final hasLowVolume = currentPlan.steps.any(
      (step) => step.hasLowStockVolume,
    );
    return Card(
      key: const ValueKey('pipetting-plan-preview'),
      color: const Color(0xFFF8F8FA),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Master mix 미리보기',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${currentPlan.replicateCount}반복 · well당 ${_formatPipettingNumber(currentPlan.volumePerWell)} ${currentPlan.volumeUnit} · 여유분 ${_formatPipettingNumber(currentPlan.overagePercent)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (required != null) ...[
              const SizedBox(height: 4),
              Text(
                '필요 well $required개${selectedCount == 0 ? ' · plate 앞쪽부터 자동 배치' : ' · 선택 $selectedCount개'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: insufficientSelection
                          ? Theme.of(context).colorScheme.error
                          : null,
                      fontWeight:
                          insufficientSelection ? FontWeight.w700 : null,
                    ),
              ),
            ],
            const Divider(height: 20),
            for (final step in currentPlan.steps) ...[
              Row(
                key: ValueKey('pipetting-step-${step.concentration}'),
                children: [
                  SizedBox(
                    width: 78,
                    child: Text(
                      '${_formatPipettingNumber(step.concentration)} ${currentPlan.concentrationUnit}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Stock ${_formatPipettingNumber(step.stockVolume)} + 희석액 ${_formatPipettingNumber(step.diluentVolume)} ${currentPlan.volumeUnit}',
                    ),
                  ),
                  if (step.hasLowStockVolume)
                    Tooltip(
                      message:
                          '1 ${currentPlan.volumeUnit} 미만입니다. 중간 희석액 사용을 검토하세요.',
                      child: Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
              if (step != currentPlan.steps.last) const SizedBox(height: 8),
            ],
            if (hasLowVolume) ...[
              const SizedBox(height: 10),
              Text(
                '경고: 1 ${currentPlan.volumeUnit} 미만 stock 분주가 있습니다. 실제 피펫 범위를 확인하고 필요하면 중간 희석액을 준비하세요.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatPipettingNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
}

class _DilutionDraft {
  const _DilutionDraft({
    required this.groupName,
    required this.shortLabel,
    required this.color,
    required this.unit,
    required this.replicateCount,
    required this.volumePerWell,
    required this.volumeUnit,
    required this.plan,
  });

  final String groupName;
  final String shortLabel;
  final Color color;
  final String unit;
  final int replicateCount;
  final double volumePerWell;
  final String volumeUnit;
  final DilutionPlan plan;
}

class _GroupEditorSheet extends StatefulWidget {
  const _GroupEditorSheet({
    required this.selectedCount,
    required this.suggestedColor,
  });

  final int selectedCount;
  final Color suggestedColor;

  @override
  State<_GroupEditorSheet> createState() => _GroupEditorSheetState();
}

class _GroupEditorSheetState extends State<_GroupEditorSheet> {
  final _nameController = TextEditingController(text: 'Drug A');
  final _labelController = TextEditingController(text: 'A');
  final _unitController = TextEditingController(text: 'µM');
  late Color _color = widget.suggestedColor;
  WellRole _role = WellRole.treatment;

  @override
  void dispose() {
    _nameController.dispose();
    _labelController.dispose();
    _unitController.dispose();
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
            '${widget.selectedCount}개 well 그룹 지정',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: '그룹명'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _labelController,
            maxLength: 3,
            decoration: const InputDecoration(labelText: '짧은 라벨'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<WellRole>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: '역할'),
            items: const [
              DropdownMenuItem(
                value: WellRole.treatment,
                child: Text('Treatment'),
              ),
              DropdownMenuItem(value: WellRole.blank, child: Text('Blank')),
              DropdownMenuItem(
                value: WellRole.vehicleControl,
                child: Text('Vehicle control'),
              ),
              DropdownMenuItem(value: WellRole.sample, child: Text('Sample')),
            ],
            onChanged: (value) =>
                setState(() => _role = value ?? WellRole.treatment),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _unitController,
            decoration: const InputDecoration(labelText: '농도 단위'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final color in _PlateEditorScreenState._groupColors)
                ChoiceChip(
                  label: const Text(''),
                  selected: color == _color,
                  onSelected: (_) => setState(() => _color = color),
                  avatar: CircleAvatar(backgroundColor: color),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('적용'),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('그룹명을 입력해주세요.')));
      return;
    }

    Navigator.of(context).pop(
      _GroupDraft(
        name: name,
        shortLabel: _labelController.text.trim().isEmpty
            ? name.characters.first
            : _labelController.text.trim(),
        color: _color,
        role: _role,
        concentrationUnit: _unitController.text.trim().isEmpty
            ? 'µM'
            : _unitController.text.trim(),
      ),
    );
  }
}

class _GroupDraft {
  const _GroupDraft({
    required this.name,
    required this.shortLabel,
    required this.color,
    required this.role,
    required this.concentrationUnit,
  });

  final String name;
  final String shortLabel;
  final Color color;
  final WellRole role;
  final String concentrationUnit;
}

class _PlateTemplateManagementDialog extends StatefulWidget {
  const _PlateTemplateManagementDialog({
    required this.initialTemplates,
    required this.repository,
    required this.onMessage,
  });

  final List<PlateTemplate> initialTemplates;
  final PlateTemplateRepository repository;
  final ValueChanged<String> onMessage;

  @override
  State<_PlateTemplateManagementDialog> createState() =>
      _PlateTemplateManagementDialogState();
}

class _PlateTemplateManagementDialogState
    extends State<_PlateTemplateManagementDialog> {
  late List<PlateTemplate> _templates = [...widget.initialTemplates];
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Plate 템플릿 관리'),
      content: SizedBox(
        width: double.maxFinite,
        child: _templates.isEmpty
            ? const Text('저장된 Plate 템플릿이 없습니다.')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: _templates.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final template = _templates[index];
                  return ListTile(
                    key: ValueKey('manage-plate-template-${template.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.view_module_outlined),
                    title: Text(template.name),
                    subtitle: Text(
                      '${template.rowCount} × ${template.columnCount} · ${_formatTemplateDate(template.updatedAt)}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          key: ValueKey('rename-plate-template-${template.id}'),
                          tooltip: '템플릿 이름 변경',
                          onPressed: _isBusy ? null : () => _rename(template),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          key: ValueKey('delete-plate-template-${template.id}'),
                          tooltip: '템플릿 삭제',
                          onPressed: _isBusy ? null : () => _delete(template),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }

  Future<void> _rename(PlateTemplate template) async {
    var name = template.name;
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('템플릿 이름 변경'),
        content: TextFormField(
          key: const ValueKey('rename-plate-template-name-field'),
          initialValue: template.name,
          autofocus: true,
          onChanged: (value) => name = value,
          decoration: const InputDecoration(labelText: '템플릿 이름'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('confirm-rename-plate-template'),
            onPressed: () => Navigator.of(context).pop(name.trim()),
            child: const Text('변경'),
          ),
        ],
      ),
    );
    if (nextName == null || nextName.isEmpty || nextName == template.name) {
      return;
    }

    await _runTemplateMutation(
      successMessage: '“$nextName” 템플릿 이름을 변경했습니다.',
      mutation: () async {
        final updated = template.copyWith(
          name: nextName,
          updatedAt: DateTime.now().toUtc(),
        );
        await widget.repository.saveTemplate(updated);
        _replaceLocal(updated);
      },
    );
  }

  Future<void> _delete(PlateTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('“${template.name}” 템플릿을 삭제할까요?'),
        content: const Text('삭제한 템플릿은 새 실험 생성과 Plate 적용 목록에서 사라집니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-plate-template'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    await _runTemplateMutation(
      successMessage: '“${template.name}” 템플릿을 삭제했습니다.',
      mutation: () async {
        await widget.repository.deleteTemplate(template.id);
        setState(() {
          _templates = _templates
              .where((candidate) => candidate.id != template.id)
              .toList();
        });
      },
    );
  }

  Future<void> _runTemplateMutation({
    required String successMessage,
    required Future<void> Function() mutation,
  }) async {
    setState(() => _isBusy = true);
    try {
      await mutation();
    } on Object catch (error) {
      widget.onMessage('템플릿을 변경하지 못했습니다: $error');
      if (mounted) {
        setState(() => _isBusy = false);
      }
      return;
    }
    widget.onMessage(successMessage);
    if (mounted) {
      setState(() => _isBusy = false);
    }
  }

  void _replaceLocal(PlateTemplate updated) {
    setState(() {
      _templates = _templates
          .map((template) => template.id == updated.id ? updated : template)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    });
  }
}

String _formatTemplateDate(DateTime date) {
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

String _formatDose(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

extension _WellRoleLabel on WellRole {
  String get label {
    switch (this) {
      case WellRole.empty:
        return 'Empty';
      case WellRole.treatment:
        return 'Treatment';
      case WellRole.sample:
        return 'Sample';
      case WellRole.blank:
        return 'Blank';
      case WellRole.negativeControl:
        return 'Negative control';
      case WellRole.positiveControl:
        return 'Positive control';
      case WellRole.vehicleControl:
        return 'Vehicle control';
      case WellRole.untreatedControl:
        return 'Untreated control';
      case WellRole.standard:
        return 'Standard';
    }
  }
}

extension _DilutionDirectionLabel on DilutionDirection {
  String get label {
    switch (this) {
      case DilutionDirection.topToBottom:
        return '위 → 아래';
      case DilutionDirection.bottomToTop:
        return '아래 → 위';
      case DilutionDirection.leftToRight:
        return '왼쪽 → 오른쪽';
      case DilutionDirection.rightToLeft:
        return '오른쪽 → 왼쪽';
    }
  }
}

Rect _sharePositionOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  return const Rect.fromLTWH(0, 0, 1, 1);
}

String _plateAnalysisFileName(String plateName) {
  final plateFileName = _plateExportFileName(plateName);
  return '${plateFileName.substring(0, plateFileName.length - 4)}-analysis.tsv';
}

String _plateExportFileName(String plateName) {
  final safeName = plateName
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9가-힣_-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return '${safeName.isEmpty ? 'easycheck-plate' : safeName}.tsv';
}

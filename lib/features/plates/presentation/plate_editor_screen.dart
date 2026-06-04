import 'package:flutter/material.dart';

import '../../../shared/models/well_position.dart';
import '../../dilution/domain/dilution_direction.dart';
import '../../dilution/domain/dilution_plan.dart';
import '../../dilution/domain/dilution_service.dart';
import '../data/file_plate_repository.dart';
import '../data/plate_repository.dart';
import '../domain/plate.dart';
import '../domain/plate_dilution_service.dart';
import '../domain/well.dart';
import '../domain/well_group.dart';
import '../domain/well_role.dart';

class PlateEditorScreen extends StatefulWidget {
  const PlateEditorScreen({
    required this.experimentId,
    this.experimentTitle = 'CCK-8 2배 희석 실험 초안',
    PlateRepository? repository,
    super.key,
  }) : repository = repository ?? const FilePlateRepository();

  final String experimentId;
  final String experimentTitle;
  final PlateRepository repository;

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
  late final List<double> _demoConcentrations;
  Plate? _plate;
  WellPosition? _selectedPosition;
  Set<WellPosition> _selectedPositions = const {};
  WellPosition? _rangeAnchor;
  bool _isLoading = true;

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
        ],
      ),
      body: SafeArea(
        child: _isLoading || plate == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _ExperimentHeaderCard(
                    title: widget.experimentTitle,
                    series: _demoConcentrations,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          plate.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
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
                    onSelected: _selectSingleWell,
                    onRangeSelected: _selectRangeTo,
                    onRowSelected: _selectRow,
                    onColumnSelected: _selectColumn,
                  ),
                  const SizedBox(height: 18),
                  _PlateSummaryCard(plate: plate),
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

    final concentrationController = TextEditingController(
      text: well.concentrationValue == null
          ? ''
          : _formatDose(well.concentrationValue!),
    );
    final unitController = TextEditingController(
      text: well.concentrationUnit ?? 'µM',
    );

    final updated = await showModalBottomSheet<Well>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${well.label} well 편집',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: concentrationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '농도'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: unitController,
                decoration: const InputDecoration(labelText: '단위'),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final concentration = double.tryParse(
                      concentrationController.text.trim(),
                    );
                    Navigator.of(context).pop(
                      well.copyWith(
                        concentrationValue: concentration,
                        concentrationUnit: unitController.text.trim().isEmpty
                            ? 'µM'
                            : unitController.text.trim(),
                        role: concentration == null
                            ? WellRole.empty
                            : concentration == 0
                                ? WellRole.vehicleControl
                                : WellRole.treatment,
                      ),
                    );
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('저장'),
                ),
              ),
            ],
          ),
        );
      },
    );

    concentrationController.dispose();
    unitController.dispose();

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

  Future<void> _savePlate(Plate plate) async {
    await widget.repository.savePlate(plate);
    if (!mounted) {
      return;
    }
    setState(() => _plate = plate);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('plate layout을 저장했습니다.')));
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
    required this.onSelected,
    required this.onRangeSelected,
    required this.onRowSelected,
    required this.onColumnSelected,
  });

  final Plate plate;
  final Set<WellPosition> selectedPositions;
  final ValueChanged<WellPosition> onSelected;
  final ValueChanged<WellPosition> onRangeSelected;
  final ValueChanged<int> onRowSelected;
  final ValueChanged<int> onColumnSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: (plate.rowCount + 1) * (plate.columnCount + 1),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: plate.columnCount + 1,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemBuilder: (context, index) {
            final gridColumnCount = plate.columnCount + 1;
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
                onTap: () => onColumnSelected(columnIndex),
              );
            }
            if (column == 0) {
              final rowIndex = row - 1;
              final rowLabel = String.fromCharCode(
                'A'.codeUnitAt(0) + rowIndex,
              );
              return _HeaderCell(
                key: ValueKey('row-header-$rowLabel'),
                label: rowLabel,
                onTap: () => onRowSelected(rowIndex),
              );
            }

            final position = WellPosition(
              rowIndex: row - 1,
              columnIndex: column - 1,
            );
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
          },
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
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

    return Semantics(
      label: '${well.label} well',
      button: true,
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
                  ? 'plate에서 well을 선택하면 농도와 실험군 정보를 아래에서 확인합니다.'
                  : selected.concentrationValue == null
                      ? '${group?.name ?? '그룹 없음'} · 농도 미지정'
                      : '${group?.name ?? selected.role.label} · ${_formatDose(selected.concentrationValue!)} ${selected.concentrationUnit ?? ''}',
            ),
            if (selected != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('농도 편집'),
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
  late Color _color = widget.suggestedColor;
  bool _includeZeroControl = true;
  DilutionDirection _direction = DilutionDirection.topToBottom;

  @override
  void dispose() {
    _groupController.dispose();
    _labelController.dispose();
    _startController.dispose();
    _factorController.dispose();
    _stepsController.dispose();
    _replicateController.dispose();
    _unitController.dispose();
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
                  keyboardType: TextInputType.number,
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
                  keyboardType: TextInputType.number,
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

  void _save() {
    final groupName = _groupController.text.trim();
    final startConcentration = double.tryParse(_startController.text.trim());
    final dilutionFactor = double.tryParse(_factorController.text.trim());
    final steps = int.tryParse(_stepsController.text.trim());
    final replicateCount = int.tryParse(_replicateController.text.trim());
    final unit = _unitController.text.trim().isEmpty
        ? 'µM'
        : _unitController.text.trim();

    if (groupName.isEmpty ||
        startConcentration == null ||
        dilutionFactor == null ||
        steps == null ||
        replicateCount == null ||
        startConcentration < 0 ||
        dilutionFactor <= 0 ||
        steps <= 0 ||
        replicateCount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('희석 계산 값을 확인해주세요.')));
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

class _DilutionDraft {
  const _DilutionDraft({
    required this.groupName,
    required this.shortLabel,
    required this.color,
    required this.unit,
    required this.replicateCount,
    required this.plan,
  });

  final String groupName;
  final String shortLabel;
  final Color color;
  final String unit;
  final int replicateCount;
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

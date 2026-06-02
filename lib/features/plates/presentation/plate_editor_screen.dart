import 'package:flutter/material.dart';

import '../../../shared/models/well_position.dart';
import '../../dilution/domain/dilution_plan.dart';
import '../../dilution/domain/dilution_service.dart';
import '../data/file_plate_repository.dart';
import '../data/plate_repository.dart';
import '../domain/plate.dart';
import '../domain/well.dart';
import '../domain/well_role.dart';

class PlateEditorScreen extends StatefulWidget {
  const PlateEditorScreen({
    required this.experimentId,
    this.experimentTitle = 'CCK-8 2배 희석 실험 초안',
    super.key,
  });

  final String experimentId;
  final String experimentTitle;

  @override
  State<PlateEditorScreen> createState() => _PlateEditorScreenState();
}

class _PlateEditorScreenState extends State<PlateEditorScreen> {
  final PlateRepository _repository = const FilePlateRepository();
  final _dilutionService = const DilutionService();
  late final List<double> _demoConcentrations;
  Plate? _plate;
  WellPosition? _selectedPosition;
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
            tooltip: '2배 희석 적용',
            onPressed: plate == null ? null : _applyDemoDilution,
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
                  Text(
                    plate.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _PlateGrid(
                    plate: plate,
                    selectedPosition: _selectedPosition,
                    onSelected: (position) => setState(() {
                      _selectedPosition = position;
                    }),
                  ),
                  const SizedBox(height: 18),
                  _WellDetailCard(
                    well: _selectedWell,
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

  Future<void> _loadPlate() async {
    try {
      final stored = await _repository.loadPlate(widget.experimentId);
      final plate = stored ?? _buildDefaultPlate();
      if (stored == null) {
        await _repository.savePlate(plate);
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

  Future<void> _applyDemoDilution() async {
    final plate = _plate;
    if (plate == null) {
      return;
    }

    await _savePlate(_plateWithDemoDilution(plate));
  }

  Plate _plateWithDemoDilution(Plate plate) {
    final updatedWells = plate.wells.map((well) {
      final row = well.position.rowIndex;
      final column = well.position.columnIndex;
      if (column < 2 && row < _demoConcentrations.length) {
        return well.copyWith(
          concentrationValue: _demoConcentrations[row],
          concentrationUnit: 'µM',
          role: _demoConcentrations[row] == 0
              ? WellRole.vehicleControl
              : WellRole.treatment,
        );
      }
      return well;
    }).toList();

    return plate.copyWith(wells: updatedWells);
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
    await _repository.savePlate(plate);
    if (!mounted) {
      return;
    }
    setState(() => _plate = plate);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('plate layout을 저장했습니다.')));
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
    required this.selectedPosition,
    required this.onSelected,
  });

  final Plate plate;
  final WellPosition? selectedPosition;
  final ValueChanged<WellPosition> onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: plate.rowCount * plate.columnCount,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: plate.columnCount,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemBuilder: (context, index) {
            final row = index ~/ plate.columnCount;
            final column = index % plate.columnCount;
            final position = WellPosition(rowIndex: row, columnIndex: column);
            final well = plate.wellAt(position);
            final isSelected = selectedPosition == position;

            return _WellCell(
              well: well,
              selected: isSelected,
              onTap: () => onSelected(position),
            );
          },
        ),
      ),
    );
  }
}

class _WellCell extends StatelessWidget {
  const _WellCell({
    required this.well,
    required this.selected,
    required this.onTap,
  });

  final Well well;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasDose = well.concentrationValue != null;
    final background =
        hasDose ? const Color(0xFFE6D9FF) : const Color(0xFFF2F2F7);
    final borderColor = selected ? Colors.black : Colors.transparent;

    return Semantics(
      label: '${well.label} well',
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Text(
            hasDose ? _formatDose(well.concentrationValue!) : well.label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            style: TextStyle(
              fontSize: hasDose ? 9 : 7,
              fontWeight: hasDose ? FontWeight.w700 : FontWeight.w500,
              color:
                  hasDose ? const Color(0xFF4B208C) : const Color(0xFF8E8E93),
            ),
          ),
        ),
      ),
    );
  }
}

class _WellDetailCard extends StatelessWidget {
  const _WellDetailCard({required this.well, required this.onEdit});

  final Well? well;
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
                      ? '아직 실험군이 지정되지 않은 well입니다.'
                      : '${selected.role.label} · ${_formatDose(selected.concentrationValue!)} ${selected.concentrationUnit ?? ''}',
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

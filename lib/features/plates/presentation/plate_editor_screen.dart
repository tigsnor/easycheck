import 'package:flutter/material.dart';

import '../../../shared/models/well_position.dart';
import '../../dilution/domain/dilution_plan.dart';
import '../../dilution/domain/dilution_service.dart';
import '../domain/plate.dart';

class PlateEditorScreen extends StatefulWidget {
  const PlateEditorScreen({
    this.experimentTitle = 'CCK-8 2배 희석 실험 초안',
    super.key,
  });

  final String experimentTitle;

  @override
  State<PlateEditorScreen> createState() => _PlateEditorScreenState();
}

class _PlateEditorScreenState extends State<PlateEditorScreen> {
  final _plate = Plate(
    id: 'demo-plate',
    experimentId: 'demo-experiment',
    name: '96-well Plate',
  );
  final _dilutionService = const DilutionService();
  late final List<double> _demoConcentrations;
  WellPosition? _selectedPosition;

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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EasyCheck'),
        actions: [
          IconButton(
            tooltip: '새 실험',
            onPressed: () {},
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _ExperimentHeaderCard(
              title: widget.experimentTitle,
              series: _demoConcentrations,
            ),
            const SizedBox(height: 18),
            Text(
              _plate.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            _PlateGrid(
              rowCount: _plate.rowCount,
              columnCount: _plate.columnCount,
              concentrations: _demoConcentrations,
              selectedPosition: _selectedPosition,
              onSelected: (position) => setState(() {
                _selectedPosition = position;
              }),
            ),
            const SizedBox(height: 18),
            _WellDetailCard(
              selectedPosition: _selectedPosition,
              concentrations: _demoConcentrations,
            ),
          ],
        ),
      ),
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'A열 기준으로 ${series.join(' → ')} µM 농도 패턴을 미리 보여줍니다.',
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
    required this.rowCount,
    required this.columnCount,
    required this.concentrations,
    required this.selectedPosition,
    required this.onSelected,
  });

  final int rowCount;
  final int columnCount;
  final List<double> concentrations;
  final WellPosition? selectedPosition;
  final ValueChanged<WellPosition> onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rowCount * columnCount,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columnCount,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemBuilder: (context, index) {
                final row = index ~/ columnCount;
                final column = index % columnCount;
                final position = WellPosition(rowIndex: row, columnIndex: column);
                final isSelected = selectedPosition == position;
                final concentration = column < 2 && row < concentrations.length
                    ? concentrations[row]
                    : null;

                return _WellCell(
                  position: position,
                  concentration: concentration,
                  selected: isSelected,
                  onTap: () => onSelected(position),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WellCell extends StatelessWidget {
  const _WellCell({
    required this.position,
    required this.concentration,
    required this.selected,
    required this.onTap,
  });

  final WellPosition position;
  final double? concentration;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasDose = concentration != null;
    final background = hasDose ? const Color(0xFFE6D9FF) : const Color(0xFFF2F2F7);
    final borderColor = selected ? Colors.black : Colors.transparent;

    return Semantics(
      label: '${position.label} well',
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
            hasDose ? _formatDose(concentration!) : position.label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            style: TextStyle(
              fontSize: hasDose ? 9 : 7,
              fontWeight: hasDose ? FontWeight.w700 : FontWeight.w500,
              color: hasDose ? const Color(0xFF4B208C) : const Color(0xFF8E8E93),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDose(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}

class _WellDetailCard extends StatelessWidget {
  const _WellDetailCard({
    required this.selectedPosition,
    required this.concentrations,
  });

  final WellPosition? selectedPosition;
  final List<double> concentrations;

  @override
  Widget build(BuildContext context) {
    final selected = selectedPosition;
    final concentration = selected != null &&
            selected.columnIndex < 2 &&
            selected.rowIndex < concentrations.length
        ? concentrations[selected.rowIndex]
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selected == null ? 'Well 상세' : '${selected.label} 상세',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              selected == null
                  ? 'plate에서 well을 선택하면 농도와 실험군 정보를 아래에서 확인합니다.'
                  : concentration == null
                      ? '아직 실험군이 지정되지 않은 well입니다.'
                      : 'Drug A · ${_formatDose(concentration)} µM · 2배 희석 예시',
            ),
          ],
        ),
      ),
    );
  }

  String _formatDose(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}

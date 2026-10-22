import 'package:flutter/material.dart';

import '../../../../shared/models/well_position.dart';
import '../../domain/plate.dart';
import '../../domain/well.dart';
import '../../domain/well_group.dart';
import '../../domain/well_role.dart';

/// View-only layout/result presentation; switching views never changes data.
class PlateGrid extends StatefulWidget {
  const PlateGrid({
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
    super.key,
  });

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
  State<PlateGrid> createState() => _PlateGridState();
}

class _PlateGridState extends State<PlateGrid> {
  static const _spacing = 6.0;
  bool _showResults = false;

  bool _isAssigned(Well well) =>
      well.groupId != null ||
      well.role != WellRole.empty ||
      well.concentrationValue != null ||
      well.resultValue != null;

  @override
  Widget build(BuildContext context) {
    final plate = widget.plate;
    final measured = plate.wells.where((w) => w.resultValue != null).length;
    final missing = plate.wells
        .where((w) => _isAssigned(w) && !w.excluded && w.resultValue == null)
        .length;
    final excluded = plate.wells.where((w) => w.excluded).length;
    final units = plate.wells
        .where((w) => w.resultValue != null)
        .map((w) =>
            w.resultUnit?.trim().isNotEmpty == true ? w.resultUnit! : '단위 미지정')
        .toSet();
    final fit = widget.requestedCellSize == null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, children: [
            ChoiceChip(
              key: const ValueKey('plate-layout-view'),
              label: const Text('배치'),
              avatar: const Icon(Icons.grid_on_outlined, size: 18),
              selected: !_showResults,
              onSelected: (_) => setState(() => _showResults = false),
            ),
            ChoiceChip(
              key: const ValueKey('plate-results-view'),
              label: const Text('결과'),
              avatar: const Icon(Icons.fact_check_outlined, size: 18),
              selected: _showResults,
              onSelected: (_) {
                setState(() => _showResults = true);
                if (fit) widget.onZoomIn?.call();
              },
            ),
          ]),
          if (_showResults) ...[
            const SizedBox(height: 6),
            Text('입력 $measured개 · 미입력 $missing개 · 제외 $excluded개',
                key: const ValueKey('plate-results-progress')),
            const Text('미입력은 배치된 well 중 제외되지 않은 항목입니다. ×는 분석 제외입니다.'),
            if (fit) const Text('전체 보기: ● 입력됨 / — 미입력 / × 제외 / · 빈 well'),
            if (units.isNotEmpty) Text('결과 단위: ${units.join(' · ')}'),
            const Text('표시값은 반올림됩니다. 정확한 값과 단위는 well 상세에서 확인하세요.'),
            const SizedBox(height: 6),
          ],
          Row(children: [
            Expanded(
                child: Text(
              fit ? 'Plate 전체 보기' : 'Plate 작업 보기',
              key: const ValueKey('plate-zoom-label'),
              style: Theme.of(context).textTheme.labelLarge,
            )),
            IconButton(
                key: const ValueKey('plate-zoom-out-button'),
                tooltip: 'Plate 축소',
                onPressed: widget.onZoomOut,
                icon: const Icon(Icons.remove_circle_outline)),
            IconButton(
                key: const ValueKey('plate-fit-button'),
                tooltip: 'Plate 전체 보기',
                onPressed: widget.onFit,
                icon: const Icon(Icons.fit_screen_outlined)),
            IconButton(
                key: const ValueKey('plate-zoom-in-button'),
                tooltip: 'Plate 확대',
                onPressed: widget.onZoomIn,
                icon: const Icon(Icons.add_circle_outline)),
          ]),
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                fit
                    ? '전체 배치를 확인하는 보기입니다. 정확한 선택은 확대 후 진행하세요.'
                    : '좌우로 밀어 숨겨진 well을 확인하세요. 각 칸에 좌표가 표시됩니다.',
                style: Theme.of(context).textTheme.bodySmall,
              )),
          LayoutBuilder(builder: (context, constraints) {
            final columns = plate.columnCount + 1;
            final rows = plate.rowCount + 1;
            final fitSize =
                (constraints.maxWidth - _spacing * (columns - 1)) / columns;
            final scale = (MediaQuery.textScalerOf(context).scale(12) / 12)
                .clamp(1.0, 2.0);
            final size = fit
                ? fitSize.clamp(8.0, double.infinity)
                : widget.requestedCellSize! * scale;
            return Scrollbar(
                child: SingleChildScrollView(
              key: const ValueKey('plate-horizontal-scroll'),
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: size * columns + _spacing * (columns - 1),
                height: size * rows + _spacing * (rows - 1),
                child: GridView.builder(
                  key: const ValueKey('plate-grid'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: rows * columns,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: _spacing,
                      crossAxisSpacing: _spacing),
                  itemBuilder: (context, index) => _cell(index, columns, size),
                ),
              ),
            ));
          }),
        ]),
      ),
    );
  }

  Widget _cell(int index, int columns, double size) {
    final row = index ~/ columns;
    final column = index % columns;
    if (row == 0 && column == 0) return const SizedBox.shrink();
    if (row == 0 || column == 0) {
      final label = row == 0 ? '$column' : String.fromCharCode(64 + row);
      return Semantics(
        label: '$label${row == 0 ? '열' : '행'} 전체 선택',
        button: true,
        child: InkWell(
          key: ValueKey(
              row == 0 ? 'column-header-$column' : 'row-header-$label'),
          onTap: () => row == 0
              ? widget.onColumnSelected(column - 1)
              : widget.onRowSelected(row - 1),
          borderRadius: BorderRadius.circular(8),
          child: ColoredBox(
              color: const Color(0xFFFFF7D6),
              child: Center(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: size < 40 ? 10 : 14,
                          fontWeight: FontWeight.w800)))),
        ),
      );
    }
    final position = WellPosition(rowIndex: row - 1, columnIndex: column - 1);
    final well = widget.plate.wellAt(position);
    final group =
        widget.plate.groups.where((g) => g.id == well.groupId).firstOrNull;
    return _WellCell(
      key: ValueKey('well-${well.label}'),
      well: well,
      group: group,
      size: size,
      results: _showResults,
      assigned: _isAssigned(well),
      selected: widget.selectedPositions.contains(position),
      onTap: () => widget.onSelected(position),
      onLongPress: () => widget.onRangeSelected(position),
    );
  }
}

class _WellCell extends StatelessWidget {
  const _WellCell(
      {required this.well,
      required this.group,
      required this.size,
      required this.results,
      required this.assigned,
      required this.selected,
      required this.onTap,
      required this.onLongPress,
      super.key});

  final Well well;
  final WellGroup? group;
  final double size;
  final bool results;
  final bool assigned;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final large = size >= 40;
    final hasResult = well.resultValue != null;
    final status = well.excluded
        ? '분석 제외'
        : hasResult
            ? '결과 입력됨'
            : assigned
                ? '미입력'
                : '빈 well';
    final details = '${well.label} well'
        '${group == null ? '' : ', 그룹 ${group!.name}'}'
        '${well.concentrationValue == null ? '' : ', 농도 ${well.concentrationValue} ${well.concentrationUnit ?? ''}'}'
        '${hasResult ? ', 결과 ${well.resultValue} ${well.resultUnit ?? ''}' : ''}, $status';
    final background = results
        ? well.excluded
            ? const Color(0xFFE5E7EB)
            : hasResult
                ? const Color(0xFFDBEAFE)
                : assigned
                    ? const Color(0xFFFFEDD5)
                    : const Color(0xFFF2F2F7)
        : group?.color ?? const Color(0xFFF2F2F7);
    final foreground =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark
            ? Colors.white
            : const Color(0xFF1F2937);
    final value = results
        ? hasResult
            ? _shortNumber(well.resultValue!)
            : well.excluded
                ? '제외'
                : assigned
                    ? '미입력'
                    : '빈 well'
        : well.concentrationValue == null
            ? (group?.shortLabel ?? '')
            : _shortNumber(well.concentrationValue!);
    final coordinate =
        '${well.label}${!results && group?.shortLabel.isNotEmpty == true ? ' · ${group!.shortLabel}' : ''}${well.excluded ? ' ×' : ''}';
    final content = results
        ? (well.excluded
            ? '×'
            : hasResult
                ? '●'
                : assigned
                    ? '—'
                    : '·')
        : group?.shortLabel.isNotEmpty == true
            ? group!.shortLabel
            : well.label;
    return Semantics(
      label: details,
      hint: '탭하여 선택, 길게 눌러 범위 선택',
      button: true,
      selected: selected,
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Tooltip(
          message: details,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              alignment: Alignment.center,
              padding: EdgeInsets.all(large ? 3 : 0),
              decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: selected ? Colors.black : Colors.transparent,
                      width: selected ? 3 : 1)),
              child: DefaultTextStyle(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: large ? (size >= 64 ? 14 : 12) : 8,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      color: foreground),
                  child: large
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(coordinate),
                          if (value.isNotEmpty) Text(value),
                        ])
                      : Text(content)),
            ),
          )),
    );
  }

  String _shortNumber(double value) {
    if (value == 0) return '0';
    if (value.abs() < 0.001 || value.abs() >= 10000) {
      return value.toStringAsExponential(2);
    }
    final text = value.toStringAsPrecision(4);
    return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
  }
}

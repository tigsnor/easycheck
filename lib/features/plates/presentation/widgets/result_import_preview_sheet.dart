import 'package:flutter/material.dart';

import '../../domain/plate.dart';
import '../../domain/plate_result_import_service.dart';
import '../../domain/well.dart';

class ResultImportPreviewSheet extends StatefulWidget {
  const ResultImportPreviewSheet(
      {required this.plate,
      required this.comparison,
      required this.sourceName,
      super.key});

  final Plate plate;
  final PlateResultImportComparison comparison;
  final String sourceName;

  @override
  State<ResultImportPreviewSheet> createState() =>
      _ResultImportPreviewSheetState();
}

class _ResultImportPreviewSheetState extends State<ResultImportPreviewSheet> {
  late ResultImportComparisonEntry _selected;
  bool _list = false;
  bool _changesOnly = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.comparison.entries
        .firstWhere((entry) => entry.change != ResultImportChange.untouched);
  }

  Color _color(ResultImportChange change) => switch (change) {
        ResultImportChange.added => const Color(0xFFDCFCE7),
        ResultImportChange.overwritten => const Color(0xFFFFEDD5),
        ResultImportChange.identical => const Color(0xFFDBEAFE),
        ResultImportChange.untouched => const Color(0xFFF3F4F6),
      };

  String _measurement(Well well) => well.resultValue == null
      ? '미입력'
      : '${well.resultValue} ${well.resultUnit ?? '(단위 없음)'}';

  Widget _detail(ResultImportComparisonEntry entry, {Key? key}) => Card(
        key: key,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${entry.before.label} · ${entry.label}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            SelectableText('현재: ${_measurement(entry.before)}'),
            SelectableText('적용 후: ${_measurement(entry.after)}'),
            if (entry.change == ResultImportChange.untouched)
              const Text('입력값이 없어 기존 값을 유지합니다.'),
            if (entry.change == ResultImportChange.identical)
              const Text('값과 단위가 같습니다.'),
            if (entry.before.excluded) const Text('분석 제외 상태 유지'),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final entries = widget.comparison.entries;
    final targets = entries
        .where((entry) => entry.change != ResultImportChange.untouched)
        .toList();
    final rows = targets.map((entry) => entry.before.position.rowIndex).toList()
      ..sort();
    final columns = targets
        .map((entry) => entry.before.position.columnNumber)
        .toList()
      ..sort();
    final shown = _changesOnly
        ? entries.where((entry) => entry.changesResult).toList()
        : entries;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('전체 결과 미리보기'),
        actions: [
          IconButton(
              key: const ValueKey('close-import-preview'),
              tooltip: '미리보기 닫기',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close))
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!_list)
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.4),
              child: SingleChildScrollView(
                  child: _detail(_selected,
                      key: const ValueKey('import-preview-selected-detail'))),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인 후 돌아가기')),
          ),
        ]),
      ),
      body: ListView(
        key: const ValueKey('import-preview-scroll'),
        padding: const EdgeInsets.all(16),
        children: [
          Text('원본: ${widget.sourceName}'),
          Text(widget.comparison.summary,
              key: const ValueKey('import-comparison-summary')),
          Text(
              '입력값 위치: ${String.fromCharCode(65 + rows.first)}–${String.fromCharCode(65 + rows.last)}행 · ${columns.first}–${columns.last}열'),
          const Text(
              '빈 셀과 입력 범위 밖의 well은 기존 값을 유지합니다. 0은 입력값입니다. 농도·메모·분석 제외 상태는 유지됩니다.'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            ChoiceChip(
                key: const ValueKey('import-preview-grid-mode'),
                label: const Text('Plate 배치'),
                selected: !_list,
                onSelected: (_) => setState(() => _list = false)),
            ChoiceChip(
                key: const ValueKey('import-preview-list-mode'),
                label: const Text('값 비교 목록'),
                selected: _list,
                onSelected: (_) => setState(() => _list = true)),
          ]),
          if (_list) ...[
            SwitchListTile(
              key: const ValueKey('import-preview-changes-only'),
              contentPadding: EdgeInsets.zero,
              title: const Text('바뀌는 well만 보기'),
              subtitle: Text('${shown.length}개 well 표시'),
              value: _changesOnly,
              onChanged: (value) => setState(() => _changesOnly = value),
            ),
            if (shown.isEmpty) const Text('값이나 단위가 바뀌는 well이 없습니다.'),
            for (final entry in shown)
              _detail(entry,
                  key: ValueKey('import-comparison-${entry.before.label}')),
          ] else ...[
            const Text(
                '좌우로 밀어 전체 Plate를 확인하세요. well을 누르면 아래에 정확한 값과 단위를 표시합니다.'),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, constraints) {
              final scale = (MediaQuery.textScalerOf(context).scale(12) / 12)
                  .clamp(1.0, 2.0);
              final width = 84.0 * scale;
              final height = 64.0 * scale;
              final columnCount = widget.plate.columnCount + 1;
              return SingleChildScrollView(
                key: const ValueKey('import-preview-horizontal-scroll'),
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: columnCount * width,
                  height: (widget.plate.rowCount + 1) * height,
                  child: GridView.builder(
                    primary: false,
                    key: const ValueKey('import-preview-grid'),
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: columnCount * (widget.plate.rowCount + 1),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columnCount, mainAxisExtent: height),
                    itemBuilder: (context, index) {
                      final row = index ~/ columnCount;
                      final column = index % columnCount;
                      if (row == 0 || column == 0) {
                        return Center(
                            child: Text(row == 0
                                ? column == 0
                                    ? ''
                                    : '$column'
                                : String.fromCharCode(64 + row)));
                      }
                      final entry = entries[
                          (row - 1) * widget.plate.columnCount + column - 1];
                      void select() => setState(() => _selected = entry);
                      return Semantics(
                        label:
                            '${entry.before.label}, ${entry.label}, 현재 ${_measurement(entry.before)}, 적용 후 ${_measurement(entry.after)}${entry.before.excluded ? ', 분석 제외 상태 유지' : ''}',
                        button: true,
                        selected: _selected == entry,
                        excludeSemantics: true,
                        onTap: select,
                        child: InkWell(
                          key: ValueKey('import-preview-${entry.before.label}'),
                          onTap: select,
                          child: Container(
                            margin: const EdgeInsets.all(2),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: _color(entry.change),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: _selected == entry
                                        ? Colors.black
                                        : Colors.transparent,
                                    width: 2)),
                            child: Text(
                                '${entry.before.label}${entry.before.excluded ? ' ×' : ''}\n${entry.label}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF1F2937))),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

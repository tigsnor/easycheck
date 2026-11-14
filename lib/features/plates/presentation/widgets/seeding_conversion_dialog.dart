import 'package:flutter/material.dart';
import '../../../../shared/models/cell_number.dart';
import '../../domain/seeding_conversion.dart';

class SeedingConversionDialog extends StatefulWidget {
  const SeedingConversionDialog(
      {required this.quantity, required this.unit, super.key});
  final double quantity;
  final String unit;
  @override
  State<SeedingConversionDialog> createState() =>
      _SeedingConversionDialogState();
}

class _SeedingConversionDialogState extends State<SeedingConversionDialog> {
  final _volume = TextEditingController();
  @override
  void dispose() {
    _volume.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.unit == 'cells/mL' ? 'cells/well' : 'cells/mL';
    double? value;
    String? error;
    if (_volume.text.trim().isNotEmpty) {
      try {
        value = SeedingConversion.convert(widget.quantity, widget.unit,
            double.tryParse(_volume.text.trim()) ?? double.nan);
      } on FormatException catch (e) {
        error = e.message;
      }
    }
    return AlertDialog(
      title: const Text('파종 부피로 환산'),
      scrollable: true,
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('입력: ${CellNumber.format(widget.quantity)} ${widget.unit}'),
            const SizedBox(height: 12),
            TextField(
                key: const ValueKey('seeding-volume-input'),
                controller: _volume,
                keyboardType: TextInputType.text,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: 'well당 파종 부피 (µL)',
                    hintText: '예: 100',
                    errorText: error,
                    errorMaxLines: 3)),
            const SizedBox(height: 12),
            Text(widget.unit == 'cells/mL'
                ? 'cells/well = cells/mL × 파종 부피(µL) ÷ 1000'
                : 'cells/mL = cells/well × 1000 ÷ 파종 부피(µL)'),
            if (value != null)
              Text('환산값: ${CellNumber.format(value)} $target',
                  key: const ValueKey('seeding-conversion-preview')),
            const SizedBox(height: 12),
            const Text(
                '현재 배지 부피가 아닌 실제 파종 부피를 입력하세요. 부피는 이번 계산에만 사용하며, 선택한 well에는 환산한 수치·단위를 기록합니다.'),
          ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
            key: const ValueKey('apply-seeding-conversion'),
            onPressed:
                value == null ? null : () => Navigator.pop(context, value),
            child: const Text('입력칸에 반영')),
      ],
    );
  }
}

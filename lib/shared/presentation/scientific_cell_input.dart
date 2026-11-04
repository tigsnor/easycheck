import 'package:flutter/material.dart';

import '../models/cell_number.dart';

/// A numeric cell quantity; changing the presentation never converts its unit.
class ScientificCellInput extends StatelessWidget {
  const ScientificCellInput({
    required this.coefficientController,
    required this.exponentController,
    required this.unit,
    this.coefficientKey,
    this.exponentKey,
    this.coefficientFocusNode,
    this.errorText,
    super.key,
  });

  final TextEditingController coefficientController;
  final TextEditingController exponentController;
  final String unit;
  final Key? coefficientKey;
  final Key? exponentKey;
  final FocusNode? coefficientFocusNode;
  final String? errorText;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: TextField(
                key: coefficientKey,
                controller: coefficientController,
                focusNode: coefficientFocusNode,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '세포수',
                  hintText: '예: 1 또는 10000',
                  errorText: errorText,
                  errorMaxLines: 5,
                ),
              ),
            ),
            const Padding(
                padding: EdgeInsets.fromLTRB(8, 16, 8, 0), child: Text('×')),
            Expanded(
              flex: 2,
              child: TextField(
                key: exponentKey,
                controller: exponentController,
                keyboardType:
                    const TextInputType.numberWithOptions(signed: true),
                decoration: const InputDecoration(
                    labelText: '10^n', hintText: '예: 4', prefixText: '10^ '),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          const Text('일반 숫자·1e4는 왼쪽에만 입력하세요. 지수 방식은 1 × 10^4처럼 나눠 입력합니다.'),
          const SizedBox(height: 6),
          ListenableBuilder(
            listenable:
                Listenable.merge([coefficientController, exponentController]),
            builder: (context, _) {
              String preview;
              try {
                final value = CellNumber.parse(
                    coefficientController.text, exponentController.text);
                preview = value == null
                    ? '입력값: 미지정'
                    : '입력값: ${CellNumber.format(value)}${unit.isEmpty ? '' : ' $unit'}';
              } on FormatException {
                preview = '입력값: 숫자와 지수를 확인해주세요.';
              }
              return Semantics(
                liveRegion: true,
                child: Text(preview,
                    key: const ValueKey('scientific-cell-preview'),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              );
            },
          ),
        ],
      );
}

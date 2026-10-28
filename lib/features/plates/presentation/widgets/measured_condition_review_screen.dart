import 'package:flutter/material.dart';
import '../../domain/measured_condition_review.dart';

class MeasuredConditionReviewScreen extends StatefulWidget {
  const MeasuredConditionReviewScreen({super.key, required this.review});
  final MeasuredConditionReview review;
  @override
  State<MeasuredConditionReviewScreen> createState() =>
      _MeasuredConditionReviewScreenState();
}

class _MeasuredConditionReviewScreenState
    extends State<MeasuredConditionReviewScreen> {
  final _reason = TextEditingController();
  String? _error;
  bool _leaving = false;
  bool _confirming = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _finish([String? record]) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, record);
  }

  Future<void> _cancel() async {
    if (_leaving || _confirming) return;
    if (_reason.text.isNotEmpty) {
      _confirming = true;
      final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('조건 정정을 취소할까요?'),
                content:
                    const Text('입력한 정정 사유와 조건 변경을 적용하지 않고 기존 Plate를 유지합니다.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('계속 검토')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('정정 취소')),
                ],
              ));
      _confirming = false;
      if (!mounted || discard != true) return;
    }
    await _finish();
  }

  void _confirm() {
    if (_leaving || _confirming) return;
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = '측정 후 조건을 바꾸는 사유를 입력해주세요.');
      return;
    }
    _finish(widget.review.record(_reason.text));
  }

  @override
  Widget build(BuildContext context) => PopScope<String>(
        canPop: _leaving,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _cancel();
        },
        child: Scaffold(
          appBar: AppBar(
              title: const Text('측정 후 조건 정정'),
              leading: IconButton(
                  tooltip: '변경 취소',
                  onPressed: _cancel,
                  icon: const Icon(Icons.close))),
          bottomNavigationBar: SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton(
                      onPressed: _leaving ? null : _confirm,
                      key: const ValueKey('confirm-condition-correction'),
                      child: const Text('정정 확인 후 저장')))),
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
            Text('측정된 ${widget.review.changes.length}개 well의 조건이 바뀝니다.',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
                '기존 측정값을 다른 조건에 연결하면 분석 결과가 바뀔 수 있습니다. 기록 정정일 때만 사유를 남겨 저장하세요. 새로운 처리 실험은 새 실험 노트나 설계 복사본에서 시작하세요.'),
            if (widget.review.otherChangedWellCount > 0)
              Text(
                  '이외 ${widget.review.otherChangedWellCount}개 well의 변경도 함께 저장됩니다.'),
            const SizedBox(height: 16),
            TextField(
                key: const ValueKey('condition-correction-reason'),
                controller: _reason,
                enabled: !_leaving,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                    labelText: '정정 사유 (필수)',
                    hintText: '예: 실험 당시 분주 기록을 확인하여 농도 오기 정정',
                    errorText: _error,
                    errorMaxLines: 3)),
            const SizedBox(height: 16),
            for (final change in widget.review.changes)
              Card(
                  key: ValueKey('condition-change-${change.before.label}'),
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(change.before.label,
                                style: Theme.of(context).textTheme.titleMedium),
                            Text('기존 결과: ${change.resultBefore}'),
                            Text('적용 후 결과: ${change.resultAfter}'),
                            for (final field in change.fields)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                      '${field.label}\n변경 전: ${field.before}\n변경 후: ${field.after}')),
                          ]))),
          ])),
        ),
      );
}

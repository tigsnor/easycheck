import 'package:flutter/material.dart';

import '../../domain/experiment.dart';
import '../../domain/protocol_editing.dart';

class ProtocolChangeReviewScreen extends StatefulWidget {
  const ProtocolChangeReviewScreen(
      {required this.before, required this.after, super.key});
  final List<ExperimentTask> before, after;
  @override
  State<ProtocolChangeReviewScreen> createState() =>
      _ProtocolChangeReviewScreenState();
}

class _ProtocolChangeReviewScreenState
    extends State<ProtocolChangeReviewScreen> {
  final _reason = TextEditingController();
  final _focus = FocusNode();
  final _reasonKey = GlobalKey();
  bool _invalid = false, _allowPop = false, _closing = false;
  @override
  void dispose() {
    _reason.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _pop([String? reason]) async {
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, reason);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    if (_reason.text.isNotEmpty) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('변경 사유 입력을 취소할까요?'),
                  content: const Text('단계 구성 초안은 실험 노트에 남습니다.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('계속 입력')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('사유 버리고 닫기')),
                  ]));
      if (!mounted) return;
      if (discard != true) {
        _closing = false;
        return;
      }
    }
    await _pop();
  }

  Future<void> _confirm() async {
    if (_closing) return;
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _invalid = true);
      _focus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(_reasonKey.currentContext!,
              alignment: .1, duration: const Duration(milliseconds: 200));
        }
      });
      return;
    }
    _closing = true;
    await _pop(reason);
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
            title: const Text('단계 변경 확인'),
            leading: IconButton(
                onPressed: _close,
                tooltip: '닫기',
                icon: const Icon(Icons.close)),
            actions: [
              TextButton(
                  key: const ValueKey('confirm-protocol-change'),
                  onPressed: _confirm,
                  child: const Text('확인 후 저장'))
            ]),
        body: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                          '진행·정정 중이거나 수행 기록이 있는 실험입니다. 변경 사유와 변경 전후 단계 구성을 함께 저장합니다. 기존 수행 기록은 유지합니다.'),
                      const SizedBox(height: 12),
                      Container(
                          key: _reasonKey,
                          child: TextField(
                              key: const ValueKey('protocol-change-reason'),
                              controller: _reason,
                              focusNode: _focus,
                              minLines: 2,
                              maxLines: 5,
                              decoration: InputDecoration(
                                  labelText: '변경 사유',
                                  errorText:
                                      _invalid ? '변경 사유를 입력해주세요.' : null))),
                      const SizedBox(height: 16),
                      for (final line in ProtocolEditing.describe(
                          widget.before, widget.after))
                        Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(line)),
                    ]))),
      ));
}

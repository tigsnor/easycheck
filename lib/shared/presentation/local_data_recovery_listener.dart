import 'dart:async';

import 'package:flutter/material.dart';

import '../data/local_data_recovery_events.dart';

class LocalDataRecoveryListener extends StatefulWidget {
  const LocalDataRecoveryListener({required this.child, super.key});

  final Widget child;

  @override
  State<LocalDataRecoveryListener> createState() =>
      _LocalDataRecoveryListenerState();
}

class _LocalDataRecoveryListenerState extends State<LocalDataRecoveryListener> {
  late final StreamSubscription<LocalDataRecoveryEvent> _subscription;
  final List<LocalDataRecoveryEvent> _pendingEvents = [];
  bool _isShowingNotice = false;

  @override
  void initState() {
    super.initState();
    _subscription = LocalDataRecoveryEvents.instance.stream.listen(
      _queueRecoveryNotice,
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _queueRecoveryNotice(LocalDataRecoveryEvent event) {
    _pendingEvents.add(event);
    if (_isShowingNotice) {
      return;
    }
    _showNextNotice();
  }

  void _showNextNotice() {
    if (!mounted || _pendingEvents.isEmpty) {
      _isShowingNotice = false;
      return;
    }

    _isShowingNotice = true;
    final event = _pendingEvents.removeAt(0);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            icon: const Icon(Icons.restore_outlined),
            title: const Text('로컬 데이터 복구 완료'),
            content: Text(
              '${event.fileName} 파일에 문제가 있어 직전 정상 데이터로 '
              '자동 복구했습니다.\n\n계속 작업하기 전에 전체 데이터 백업을 만들어 두는 것을 권장합니다.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('확인'),
              ),
            ],
          ),
        ),
      );
      if (mounted) {
        _showNextNotice();
      }
    });
  }
}

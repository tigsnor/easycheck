import 'dart:async';

class LocalDataRecoveryEvent {
  const LocalDataRecoveryEvent({
    required this.filePath,
    required this.backupPath,
    required this.recoveredAt,
  });

  final String filePath;
  final String backupPath;
  final DateTime recoveredAt;

  String get fileName {
    final segments = filePath.split(RegExp(r'[/\\]'));
    return segments.isEmpty ? filePath : segments.last;
  }
}

class LocalDataRecoveryEvents {
  LocalDataRecoveryEvents._();

  static final instance = LocalDataRecoveryEvents._();

  final _controller = StreamController<LocalDataRecoveryEvent>.broadcast();

  Stream<LocalDataRecoveryEvent> get stream => _controller.stream;

  void publish(LocalDataRecoveryEvent event) {
    _controller.add(event);
  }
}

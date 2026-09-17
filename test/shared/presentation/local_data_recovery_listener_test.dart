import 'package:easycheck/shared/data/local_data_recovery_events.dart';
import 'package:easycheck/shared/presentation/local_data_recovery_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a non-dismissible notice after automatic recovery', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LocalDataRecoveryListener(child: Scaffold(body: Text('실험 목록'))),
      ),
    );

    LocalDataRecoveryEvents.instance.publish(
      LocalDataRecoveryEvent(
        filePath: '/documents/experiments.json',
        backupPath: '/documents/experiments.json.bak',
        recoveredAt: DateTime.utc(2026, 6, 12),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('로컬 데이터 복구 완료'), findsOneWidget);
    expect(find.textContaining('experiments.json 파일에 문제가 있어'), findsOneWidget);
    expect(find.textContaining('전체 데이터 백업'), findsOneWidget);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.text('로컬 데이터 복구 완료'), findsNothing);
    expect(find.text('실험 목록'), findsOneWidget);
  });
}

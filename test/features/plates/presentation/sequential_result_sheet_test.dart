import 'dart:async';

import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/features/plates/presentation/widgets/sequential_result_sheet.dart';
import 'package:easycheck/shared/models/well_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Finder key(String value) => find.byKey(ValueKey(value));
  String field(WidgetTester tester, String name) =>
      tester.widget<TextField>(key(name)).controller!.text;
  Future<void> tap(WidgetTester tester, String name) async {
    await tester.ensureVisible(key(name));
    await tester.tap(key(name));
    await tester.pumpAndSettle();
  }

  Future<void> show(WidgetTester tester,
      {required Future<bool> Function(Well) save,
      Plate? plate,
      String start = 'A1',
      double textScale = 1,
      ValueChanged<WellPosition>? changed}) async {
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
        home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      isDismissible: false,
                      enableDrag: false,
                      builder: (_) => SequentialResultSheet(
                        plate: plate ??
                            Plate(id: 'p', experimentId: 'e', name: 'Plate'),
                        start: WellPosition.fromLabel(start),
                        onSave: save,
                        onPositionChanged: changed ?? (_) {},
                      ),
                    ),
                    child: const Text('Open'),
                  )),
        )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> column(WidgetTester tester) async {
    await tap(tester, 'sequential-direction');
    await tester.tap(find.text('열 방향 · A1 → B1').last);
    await tester.pumpAndSettle();
  }

  testWidgets('small screen with large text and keyboard keeps save reachable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    final saved = <Well>[];
    await show(tester, textScale: 1.6, save: (w) async {
      saved.add(w);
      return true;
    });
    await tester.ensureVisible(key('sequential-value'));
    await tester.enterText(key('sequential-value'), '1.25');
    await tap(tester, 'sequential-save-next');
    expect(saved.single.resultValue, 1.25);
    expect(find.text('A2 · 결과 연속 입력'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saves zero, preserves metadata and rolls A12 to B1 with unit',
      (tester) async {
    final base = Plate(id: 'p', experimentId: 'e', name: 'Plate');
    final source = base.wells[11].copyWith(
      role: WellRole.vehicleControl,
      concentrationValue: 5,
      note: 'bubble',
      excluded: true,
      volumeValue: 100,
      replicateIndex: 2,
    );
    final saved = <Well>[];
    await show(tester,
        start: 'A12',
        plate: base.copyWith(
            wells: [for (final w in base.wells) w.label == 'A12' ? source : w]),
        save: (w) async {
      saved.add(w);
      return true;
    });
    await tester.enterText(key('sequential-value'), '0');
    await tester.enterText(key('sequential-unit'), 'RFU');
    await tap(tester, 'sequential-save-next');
    expect(saved.single.toJson(),
        source.copyWith(resultValue: 0, resultUnit: 'RFU').toJson());
    expect(find.text('B1 · 결과 연속 입력'), findsOneWidget);
    expect(field(tester, 'sequential-value'), isEmpty);
    expect(field(tester, 'sequential-unit'), 'RFU');
    expect(find.text('A12 저장 완료'), findsOneWidget);
  });

  testWidgets(
      'column order rolls H1 to A2 and loads existing precision and unit',
      (tester) async {
    final base = Plate(id: 'p', experimentId: 'e', name: 'Plate');
    final plate = base.copyWith(wells: [
      base.wells[0],
      base.wells[1].copyWith(
          resultValue: 0.123456789123, resultUnit: 'RFU', excluded: true),
      ...base.wells.skip(2),
    ]);
    await show(tester, start: 'H1', plate: plate, save: (_) async => true);
    await column(tester);
    expect(find.text('저장 후 A2로 이동'), findsOneWidget);
    await tester.enterText(key('sequential-value'), '-1.5');
    await tap(tester, 'sequential-save-next');
    expect(find.text('A2 · 결과 연속 입력'), findsOneWidget);
    expect(field(tester, 'sequential-value'), '0.123456789123');
    expect(field(tester, 'sequential-unit'), 'RFU');
    expect(find.textContaining('기존 결과: 0.123456789123'), findsOneWidget);
    expect(find.textContaining('분석 제외 well입니다.'), findsOneWidget);
  });

  testWidgets(
      'failed save keeps editable draft and guards back until retry succeeds',
      (tester) async {
    final saved = <Well>[];
    var calls = 0;
    await show(tester, save: (w) async {
      calls++;
      if (calls == 1) return false;
      saved.add(w);
      return true;
    });
    await tester.enterText(key('sequential-value'), '0.82');
    await tap(tester, 'sequential-save-next');
    expect(key('sequential-save-error'), findsOneWidget);
    expect(find.text('A1 · 결과 연속 입력'), findsOneWidget);
    expect(field(tester, 'sequential-value'), '0.82');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('현재 well의 입력을 버릴까요?'), findsOneWidget);
    await tester.tap(find.text('계속 입력'));
    await tester.pumpAndSettle();
    await tester.enterText(key('sequential-value'), '0.91');
    await tap(tester, 'sequential-save-next');
    expect(saved.single.resultValue, 0.91);
    expect(find.text('A2 · 결과 연속 입력'), findsOneWidget);
    expect(key('sequential-save-error'), findsNothing);
  });

  testWidgets('pending save prevents duplicate writes and dismissal',
      (tester) async {
    final pending = Completer<bool>();
    var calls = 0;
    final moved = <WellPosition>[];
    await show(tester, changed: moved.add, save: (_) {
      calls++;
      return pending.future;
    });
    await tester.enterText(key('sequential-value'), '1');
    await tap(tester, 'sequential-save-next');
    await tap(tester, 'sequential-save-next');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(moved, isEmpty);
    expect(tester.widget<TextField>(key('sequential-value')).enabled, isFalse);
    expect(tester.widget<IconButton>(key('close-sequential-results')).onPressed,
        isNull);
    expect(find.text('A1 · 결과 연속 입력'), findsOneWidget);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(moved.single.label, 'A2');
  });

  testWidgets(
      'rejects nonfinite and empty input, then saves last well without wrapping',
      (tester) async {
    final saved = <Well>[];
    await show(tester, start: 'H12', save: (w) async {
      saved.add(w);
      return true;
    });
    expect(find.text('저장 후 마치기'), findsOneWidget);
    for (final value in ['', 'NaN', 'Infinity', 'oops']) {
      await tester.enterText(key('sequential-value'), value);
      await tap(tester, 'sequential-save-next');
      expect(find.textContaining('유한한 숫자를 입력해주세요.'), findsOneWidget);
      expect(saved, isEmpty);
    }
    await tester.enterText(key('sequential-value'), '1.2e-3');
    await tap(tester, 'sequential-save-next');
    expect(saved.single.label, 'H12');
    expect(saved.single.resultValue, 0.0012);
    expect(find.byType(SequentialResultSheet), findsNothing);
  });

  testWidgets(
      'discard only drops current draft and existing unitless data stays unitless',
      (tester) async {
    final base = Plate(id: 'p', experimentId: 'e', name: 'Plate');
    final saved = <Well>[];
    await show(tester,
        plate: base.copyWith(wells: [
          base.wells.first.copyWith(resultValue: 1),
          ...base.wells.skip(1)
        ]), save: (w) async {
      saved.add(w);
      return true;
    });
    expect(field(tester, 'sequential-unit'), isEmpty);
    await tap(tester, 'sequential-save-next');
    expect(saved.single.resultUnit, isNull);
    await tester.enterText(key('sequential-value'), '2');
    await tap(tester, 'close-sequential-results');
    await tester.tap(find.text('입력 버리고 닫기'));
    await tester.pumpAndSettle();
    expect(saved.length, 1);
    expect(find.byType(SequentialResultSheet), findsNothing);
  });

  testWidgets(
      'direction changes revisit saved values instead of stale initial values',
      (tester) async {
    final saved = <Well>[];
    await show(tester,
        plate: Plate(
            id: 'p',
            experimentId: 'e',
            name: 'Plate',
            rowCount: 2,
            columnCount: 2), save: (w) async {
      saved.add(w);
      return true;
    });
    for (final value in ['1', '2']) {
      await tester.enterText(key('sequential-value'), value);
      await tap(tester, 'sequential-save-next');
    }
    expect(find.text('B1 · 결과 연속 입력'), findsOneWidget);
    await column(tester);
    await tester.enterText(key('sequential-value'), '3');
    await tap(tester, 'sequential-save-next');
    expect(find.text('A2 · 결과 연속 입력'), findsOneWidget);
    expect(field(tester, 'sequential-value'), '2.0');
    await tap(tester, 'sequential-save-close');
    expect(saved.last.label, 'A2');
    expect(saved.last.resultValue, 2);
    expect(find.byType(SequentialResultSheet), findsNothing);
  });
}

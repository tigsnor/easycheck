import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_result_import_service.dart';
import 'package:easycheck/features/plates/presentation/widgets/result_import_preview_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showPreview(WidgetTester tester, {double scale = 1}) async {
    final base = Plate(id: 'p', experimentId: 'e', name: 'Plate');
    final wells = base.wells.toList();
    wells[1] = wells[1].copyWith(resultValue: 0.2, resultUnit: 'OD450');
    wells[2] = wells[2].copyWith(resultValue: 0.3, resultUnit: 'RFU');
    wells[95] =
        wells[95].copyWith(resultValue: 9, resultUnit: 'OD450', excluded: true);
    final plate = base.copyWith(wells: wells);
    const service = PlateResultImportService();
    final preview = service.parseMatrix(
        text:
            'A\t0\t0.2\t0.3\nH\t${List.filled(11, '').join('\t')}\t0.123456789123');
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: ResultImportPreviewSheet(
          plate: plate,
          comparison: service.compare(
              plate: plate, preview: preview, resultUnit: 'OD450'),
          sourceName: 'reader.tsv'),
    )));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'shows all corner mappings and full precision with exclusion in fixed detail',
      (tester) async {
    await showPreview(tester);
    expect(find.text('신규 1개 · 덮어쓰기 2개 · 동일 1개 · 유지 92개'), findsOneWidget);
    expect(find.text('입력값 위치: A–H행 · 1–12열'), findsOneWidget);
    for (final label in ['A1', 'A12', 'H1', 'H12']) {
      expect(find.byKey(ValueKey('import-preview-$label')), findsOneWidget);
    }
    expect(find.text('적용 후: 0.0 OD450'), findsOneWidget);
    final last = find.byKey(const ValueKey('import-preview-H12'));
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(find.text('H12 · 덮어쓰기'), findsOneWidget);
    expect(find.text('현재: 9.0 OD450'), findsOneWidget);
    expect(find.text('적용 후: 0.123456789123 OD450'), findsOneWidget);
    expect(find.text('분석 제외 상태 유지'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
        find.bySemanticsLabel(
            RegExp('H12, 덮어쓰기, 현재 9.0 OD450, 적용 후 0.123456789123 OD450')),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
      'comparison list can filter unchanged wells and keeps unit-only changes',
      (tester) async {
    await showPreview(tester);
    await tester.tap(find.byKey(const ValueKey('import-preview-list-mode')));
    await tester.pumpAndSettle();
    expect(find.text('96개 well 표시'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-preview-changes-only')));
    await tester.pumpAndSettle();
    expect(find.text('3개 well 표시'), findsOneWidget);
    expect(find.byKey(const ValueKey('import-comparison-A2')), findsNothing);
    final a3 = find.byKey(const ValueKey('import-comparison-A3'));
    await tester.ensureVisible(a3);
    await tester.pumpAndSettle();
    expect(find.descendant(of: a3, matching: find.text('현재: 0.3 RFU')),
        findsOneWidget);
    expect(find.descendant(of: a3, matching: find.text('적용 후: 0.3 OD450')),
        findsOneWidget);
  });

  testWidgets(
      'small screen and large text can reach H12 and read its comparison',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await showPreview(tester, scale: 1.6);
    await tester.drag(find.byKey(const ValueKey('import-preview-scroll')),
        const Offset(0, -400));
    await tester.pumpAndSettle();
    final last = find.byKey(const ValueKey('import-preview-H12'));
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(find.text('H12 · 덮어쓰기'), findsOneWidget);
    expect(find.text('적용 후: 0.123456789123 OD450'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:easycheck/shared/models/well_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plate_editor_screen_test.dart' show FakePlateRepository;

void main() {
  const position = WellPosition(rowIndex: 0, columnIndex: 0);
  Finder field(String name) => find.byKey(ValueKey('well-$name-field'));

  Future<void> tap(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> edit(WidgetTester tester) async {
    await tap(tester, find.byKey(const ValueKey('edit-selected-well-action')));
  }

  Future<void> save(WidgetTester tester) async {
    await tap(tester, find.byKey(const ValueKey('save-well-record-button')));
  }

  Future<FakePlateRepository> open(WidgetTester tester, Well well,
      {bool narrow = false}) async {
    final base = Plate(id: 'p', experimentId: 'e', name: 'Safety');
    final repo = FakePlateRepository()
      ..plate = base.copyWith(wells: [well, ...base.wells.skip(1)]);
    await tester.pumpWidget(MaterialApp(
        builder: narrow
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.6),
                    viewInsets: const EdgeInsets.only(bottom: 250)),
                child: child!)
            : null,
        home: PlateEditorScreen(experimentId: 'e', repository: repo)));
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const ValueKey('well-A1')));
    await edit(tester);
    return repo;
  }

  for (final result in [0.0, -0.82, 1.234567891234e-8]) {
    testWidgets('note and exclusion edits preserve unitless result $result',
        (tester) async {
      final original = Well(
          position: position,
          concentrationValue: 2,
          resultValue: result,
          volumeValue: 100,
          replicateIndex: 2,
          note: ' original note ');
      final repo = await open(tester, original);
      expect(
          tester.widget<TextField>(field('result-unit')).controller!.text, '');
      expect(
          tester
              .widget<TextField>(field('concentration-unit'))
              .controller!
              .text,
          '');
      await tester.enterText(field('note'), 'new observation');
      await save(tester);
      final withNote = original.copyWith(note: 'new observation');
      expect(repo.plate!.wells.first.toJson(), withNote.toJson());
      await edit(tester);
      await tap(tester, find.byKey(const ValueKey('well-excluded-switch')));
      await save(tester);
      expect(repo.plate!.wells.first.toJson(),
          withNote.copyWith(excluded: true).toJson());
    });
  }

  testWidgets('unit-only records and untouched notes are preserved',
      (tester) async {
    const original = Well(
        position: position,
        resultUnit: 'RFU',
        concentrationUnit: 'nM',
        note: ' note ');
    final repo = await open(tester, original);
    await tap(tester, find.byKey(const ValueKey('well-excluded-switch')));
    await save(tester);
    expect(repo.plate!.wells.first.toJson(),
        original.copyWith(excluded: true).toJson());
  });

  testWidgets(
      'units change only through explicit edits and result clearing is retained',
      (tester) async {
    const original = Well(
        position: position,
        concentrationValue: 1,
        concentrationUnit: 'µM',
        resultValue: 0,
        resultUnit: 'OD450');
    final repo = await open(tester, original);
    await tester.enterText(field('result-unit'), 'RFU');
    await tester.enterText(field('concentration-unit'), '');
    await save(tester);
    expect(repo.plate!.wells.first.toJson(), original.toJson());
    await tester.enterText(
        find.byKey(const ValueKey('condition-correction-reason')), '단위 오기 정정');
    await tap(
        tester, find.byKey(const ValueKey('confirm-condition-correction')));
    expect(repo.plate!.wells.first.toJson(),
        original.copyWith(resultUnit: 'RFU', concentrationUnit: null).toJson());
    await edit(tester);
    await tester.enterText(field('result-unit'), '');
    await save(tester);
    await tester.enterText(
        find.byKey(const ValueKey('condition-correction-reason')),
        '단위 미지정으로 정정');
    await tap(
        tester, find.byKey(const ValueKey('confirm-condition-correction')));
    expect(repo.plate!.wells.first.resultValue, 0);
    expect(repo.plate!.wells.first.resultUnit, isNull);
    await edit(tester);
    await tester.enterText(field('result-unit'), 'RLU');
    await tester.enterText(field('result-value'), '');
    await save(tester);
    expect(repo.plate!.wells.first.resultValue, isNull);
    expect(repo.plate!.wells.first.resultUnit, isNull);
  });

  testWidgets('new measurements do not silently assume units', (tester) async {
    final repo = await open(tester, const Well(position: position));
    await tester.enterText(field('result-value'), '0');
    await tester.enterText(field('concentration-value'), '2');
    await save(tester);
    final saved = repo.plate!.wells.first;
    expect(saved.resultValue, 0);
    expect(saved.resultUnit, isNull);
    expect(saved.concentrationUnit, isNull);
    expect(saved.role, WellRole.treatment);
  });

  testWidgets(
      'back and close require discard, barrier and drag cannot lose input',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const original = Well(position: position, note: 'original');
    final repo = await open(tester, original);
    await tester.enterText(field('note'), 'unsaved observation');
    await tester.pump();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(field('note'), findsOneWidget);
    await tester.drag(find.text('A1 well 기록'), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(field('note'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('현재 well의 입력을 버릴까요?'), findsOneWidget);
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field('note')).controller!.text,
        'unsaved observation');
    await tap(tester, find.byKey(const ValueKey('close-well-record')));
    await tester.tap(find.text('입력 버리고 닫기'));
    await tester.pumpAndSettle();
    expect(repo.saveCount, 0);
    expect(repo.plate!.wells.first.toJson(), original.toJson());
    await edit(tester);
    expect(
        tester.widget<TextField>(field('note')).controller!.text, 'original');
  });

  testWidgets(
      'unchanged or reverted input closes without a write or confirmation',
      (tester) async {
    final repo = await open(tester, const Well(position: position));
    await save(tester);
    expect(repo.saveCount, 0);
    await edit(tester);
    await tester.enterText(field('note'), 'temporary');
    await tester.enterText(field('note'), '');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(field('note'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.saveCount, 0);
  });

  testWidgets('failed save keeps the exact unitless draft for retry',
      (tester) async {
    const original =
        Well(position: position, resultValue: -0.125, concentrationValue: 2);
    final repo = await open(tester, original);
    repo.failNextSave = true;
    await tester.enterText(field('note'), 'retry observation');
    await save(tester);
    expect(repo.saveCount, 1);
    expect(repo.plate!.wells.first.toJson(), original.toJson());
    await tap(tester, find.byKey(const ValueKey('retry-save-button')));
    expect(repo.plate!.wells.first.toJson(),
        original.copyWith(note: 'retry observation').toJson());
    expect(repo.plate!.revisions.length, 1);
  });

  testWidgets('narrow large-text editing keeps close and save reachable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo =
        await open(tester, const Well(position: position), narrow: true);
    await tester.enterText(field('note'), 'small screen observation');
    await tap(tester, find.byKey(const ValueKey('close-well-record')));
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();
    await save(tester);
    expect(repo.plate!.wells.first.note, 'small screen observation');
    expect(tester.takeException(), isNull);
  });
}

import 'package:easycheck/features/plates/domain/seeding_conversion.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/cell_condition.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'plate_editor_screen_test.dart' show FakePlateRepository;

void main() {
  test(
      'explicit microlitre conversion preserves zero and rejects invalid ranges',
      () {
    expect(SeedingConversion.convert(100000, 'cells/mL', 100), 10000);
    expect(SeedingConversion.convert(10000, 'cells/well', 100), 100000);
    expect(SeedingConversion.convert(0, 'cells/well', 100), 0);
    for (final volume in [0.0, -1.0, double.nan, double.infinity]) {
      expect(() => SeedingConversion.convert(1, 'cells/mL', volume),
          throwsFormatException);
    }
    expect(
        () => SeedingConversion.convert(1, 'µM', 100), throwsFormatException);
    expect(() => SeedingConversion.convert(-1, 'cells/mL', 100),
        throwsFormatException);
    expect(() => SeedingConversion.convert(1e308, 'cells/well', .1),
        throwsFormatException);
    expect(() => SeedingConversion.convert(1e-320, 'cells/mL', 1e-10),
        throwsFormatException);
  });

  testWidgets(
      'conversion is explicit, does not reuse medium volume, and applies only the draft',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final base = Plate(id: 'p', experimentId: 'e', name: 'P');
    final original = base.copyWith(wells: [
      base.wells.first.copyWith(
          cellCondition: const CellCondition(
              name: 'HeLa', density: 100000, unit: 'cells/mL'),
          volumeValue: 999,
          volumeUnit: 'µL'),
      ...base.wells.skip(1)
    ]);
    final repo = FakePlateRepository()..plate = original;
    Finder key(String name) => find.byKey(ValueKey(name));
    Future<void> tap(String name) async {
      await tester.ensureVisible(key(name));
      await tester.pumpAndSettle();
      await tester.tap(key(name));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(MaterialApp(
        home: PlateEditorScreen(experimentId: 'e', repository: repo)));
    await tester.pumpAndSettle();
    await tap('well-A1');
    await tap('assign-cell-condition-action');
    await tap('convert-seeding-quantity');
    expect(
        tester.widget<TextField>(key('seeding-volume-input')).controller!.text,
        isEmpty);
    expect(
        tester.widget<FilledButton>(key('apply-seeding-conversion')).onPressed,
        isNull);
    await tester.enterText(key('seeding-volume-input'), '0');
    await tester.pumpAndSettle();
    expect(
        tester.widget<FilledButton>(key('apply-seeding-conversion')).onPressed,
        isNull);
    await tester.enterText(key('seeding-volume-input'), '100');
    await tester.pumpAndSettle();
    expect(find.text('환산값: 10,000 cells/well'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repo.saveCount, 0);
    expect(tester.widget<TextField>(key('cell-density-input')).controller!.text,
        '100000.0');
    await tap('convert-seeding-quantity');
    await tester.enterText(key('seeding-volume-input'), '100');
    await tester.pumpAndSettle();
    await tap('apply-seeding-conversion');
    expect(repo.saveCount, 0);
    expect(find.text('입력값: 10,000 cells/well'), findsOneWidget);
    await tap('apply-cell-condition');
    expect(repo.saveCount, 1);
    expect(
        repo.plate!.wells.first.toJson(),
        original.wells.first
            .copyWith(
                cellCondition: const CellCondition(
                    name: 'HeLa', density: 10000, unit: 'cells/well'))
            .toJson());
    expect(repo.plate!.wells.skip(1).map((w) => w.toJson()),
        original.wells.skip(1).map((w) => w.toJson()));
  });
}

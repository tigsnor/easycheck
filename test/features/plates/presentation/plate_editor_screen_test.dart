import 'package:easycheck/features/plates/data/plate_repository.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlateRepository implements PlateRepository {
  Plate? plate;

  @override
  Future<Plate?> loadPlate(String experimentId) async => plate;

  @override
  Future<void> savePlate(Plate plate) async {
    this.plate = plate;
  }
}

void main() {
  testWidgets('creates a default plate and renders dilution values', (
    tester,
  ) async {
    final repository = FakePlateRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: PlateEditorScreen(
          experimentId: 'experiment-1',
          experimentTitle: 'Drug A CCK-8',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Drug A CCK-8'), findsOneWidget);
    expect(find.text('96-well Plate'), findsOneWidget);
    expect(find.textContaining('1000'), findsWidgets);
    expect(repository.plate, isNotNull);
    expect(repository.plate!.wells.length, 96);
  });

  testWidgets('selects a row and opens group assignment sheet', (tester) async {
    final repository = FakePlateRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: PlateEditorScreen(
          experimentId: 'experiment-1',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('row-header-A')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('선택 영역 그룹 지정'));
    await tester.pumpAndSettle();

    expect(find.text('12개 well 그룹 지정'), findsOneWidget);
    expect(find.widgetWithText(TextField, '그룹명'), findsOneWidget);
  });

  testWidgets('applies a custom dilution builder plan to the plate', (
    tester,
  ) async {
    final repository = FakePlateRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: PlateEditorScreen(
          experimentId: 'experiment-1',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('희석 계산 적용'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '시작 농도'), '90');
    await tester.enterText(find.widgetWithText(TextField, '희석 배수'), '3');
    await tester.enterText(find.widgetWithText(TextField, '단계 수'), '2');
    await tester.enterText(find.widgetWithText(TextField, '반복 well 수'), '1');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('희석 적용'));
    await tester.tap(find.text('희석 적용'));
    await tester.pumpAndSettle();

    expect(repository.plate!.wells[0].concentrationValue, 90);
    expect(repository.plate!.wells[1].concentrationValue, 30);
    expect(repository.plate!.wells[2].concentrationValue, isNull);
  });
}

import 'package:easycheck/features/plates/data/plate_repository.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_document_exchange_service.dart';

class FakePlateRepository implements PlateRepository {
  Plate? plate;

  @override
  Future<void> deletePlate(String experimentId) async {
    plate = null;
  }

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
    await tester.scrollUntilVisible(
      find.text('실험군 · 농도 요약'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('실험군 · 농도 요약'), findsOneWidget);
    expect(find.text('Drug A (A)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('plate-validation-card')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('실험 준비 점검'), findsOneWidget);
    expect(find.text('Blank가 없습니다'), findsOneWidget);
    expect(find.text('Control이 없습니다'), findsNothing);
    expect(repository.plate, isNotNull);
    expect(repository.plate!.wells.length, 96);
  });

  testWidgets('zooms the plate and restores screen fit', (tester) async {
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

    expect(find.text('Plate 화면 맞춤'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plate-zoom-in-button')));
    await tester.pumpAndSettle();

    expect(find.text('Plate 40px'), findsOneWidget);
    expect(find.text('좌우로 밀어 숨겨진 well을 확인하세요.'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('well-A1'))).width,
      closeTo(40, 0.1),
    );

    await tester.tap(find.byKey(const ValueKey('plate-zoom-in-button')));
    await tester.pumpAndSettle();
    expect(find.text('Plate 48px'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plate-fit-button')));
    await tester.pumpAndSettle();
    expect(find.text('Plate 화면 맞춤'), findsOneWidget);
  });

  testWidgets('keeps row selection while changing plate zoom', (tester) async {
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

    await tester.tap(find.byKey(const ValueKey('plate-zoom-in-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('선택 영역 그룹 지정'));
    await tester.pumpAndSettle();

    expect(find.text('12개 well 그룹 지정'), findsOneWidget);
  });

  testWidgets('keeps plate controls usable on a narrow phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: PlateEditorScreen(
          experimentId: 'experiment-1',
          repository: FakePlateRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('plate-zoom-in-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plate-zoom-in-button')));
    await tester.pumpAndSettle();
    expect(find.text('Plate 40px'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('imports an Excel-style result matrix into wells', (
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

    await tester.tap(find.byKey(const ValueKey('bulk-result-import-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bulk-result-matrix-field')),
      '\t1\t2\nA\t0.82\t0.79\nB\t0.75\t0.77',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('숫자 4개 인식'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('apply-bulk-results-button')),
    );
    await tester.tap(find.byKey(const ValueKey('apply-bulk-results-button')));
    await tester.pumpAndSettle();

    expect(repository.plate!.wells[0].resultValue, 0.82);
    expect(repository.plate!.wells[1].resultValue, 0.79);
    expect(repository.plate!.wells[12].resultValue, 0.75);
    expect(repository.plate!.wells[13].resultValue, 0.77);
    expect(repository.plate!.wells[0].resultUnit, 'OD450');
  });

  testWidgets('records a result, note, and exclusion flag for a well', (
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

    await tester.tap(find.byKey(const ValueKey('well-A1')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('농도 · 결과 편집'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('농도 · 결과 편집'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('농도 · 결과 편집'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('well-result-value-field')),
      '0.82',
    );
    await tester.enterText(
      find.byKey(const ValueKey('well-result-unit-field')),
      'OD450',
    );
    await tester.enterText(
      find.byKey(const ValueKey('well-note-field')),
      '기포 확인',
    );
    await tester.tap(find.byKey(const ValueKey('well-excluded-switch')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('save-well-record-button')),
    );
    await tester.tap(find.byKey(const ValueKey('save-well-record-button')));
    await tester.pumpAndSettle();

    final savedWell = repository.plate!.wells.first;
    expect(savedWell.resultValue, 0.82);
    expect(savedWell.resultUnit, 'OD450');
    expect(savedWell.note, '기포 확인');
    expect(savedWell.excluded, isTrue);
    expect(find.text('결과 · 0.82 OD450'), findsOneWidget);
    expect(find.text('분석 제외'), findsOneWidget);
  });

  testWidgets('shows save status and undoes the last plate change', (
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

    expect(find.textContaining('저장됨'), findsOneWidget);
    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
    expect(tester.widget<IconButton>(undoButton).onPressed, isNull);

    await tester.tap(find.byTooltip('희석 계산 적용'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '시작 농도'), '90');
    await tester.enterText(find.widgetWithText(TextField, '희석 배수'), '3');
    await tester.enterText(find.widgetWithText(TextField, '단계 수'), '2');
    await tester.enterText(find.widgetWithText(TextField, '반복 well 수'), '1');
    await tester.tap(find.byType(SwitchListTile));
    await tester.ensureVisible(find.text('희석 적용'));
    await tester.tap(find.text('희석 적용'));
    await tester.pumpAndSettle();

    expect(repository.plate!.wells[0].concentrationValue, 90);
    await tester.tap(find.byTooltip('마지막 Plate 변경 실행 취소'));
    await tester.pumpAndSettle();

    expect(repository.plate!.wells[0].concentrationValue, 1000);
    expect(find.text('마지막 Plate 변경을 취소했습니다.'), findsOneWidget);
  });

  testWidgets('opens a plate export sheet and shares a TSV file', (
    tester,
  ) async {
    final repository = FakePlateRepository();
    final exchange = FakeDocumentExchangeService();

    await tester.pumpWidget(
      MaterialApp(
        home: PlateEditorScreen(
          experimentId: 'experiment-1',
          repository: repository,
          documentExchangeService: exchange,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Plate 내보내기'));
    await tester.pumpAndSettle();

    expect(find.text('Plate 내보내기'), findsOneWidget);
    expect(find.textContaining('EasyCheck plate export'), findsOneWidget);
    expect(find.text('복사하기'), findsOneWidget);
    expect(find.text('파일 공유'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('share-plate-file-button')));
    await tester.pumpAndSettle();

    expect(exchange.shareCalls, 1);
    expect(exchange.sharedFileName, '96-well-Plate.tsv');
    expect(exchange.sharedMimeType, 'text/tab-separated-values');
    expect(exchange.sharedContent, contains('EasyCheck plate export'));
  });
}

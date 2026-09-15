import 'package:easycheck/features/plates/data/plate_repository.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well.dart';
import 'package:easycheck/features/plates/domain/well_group.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/features/plates/templates/data/plate_template_repository.dart';
import 'package:easycheck/features/plates/templates/domain/plate_template.dart';
import 'package:easycheck/shared/models/well_position.dart';
import 'package:easycheck/shared/services/document_exchange_service.dart';
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

class FakePlateTemplateRepository implements PlateTemplateRepository {
  final List<PlateTemplate> templates = [];

  @override
  Future<void> deleteTemplate(String id) async {
    templates.removeWhere((template) => template.id == id);
  }

  @override
  Future<List<PlateTemplate>> loadTemplates() async => [...templates];

  @override
  Future<void> saveTemplate(PlateTemplate template) async {
    final index = templates.indexWhere((item) => item.id == template.id);
    if (index == -1) {
      templates.add(template);
    } else {
      templates[index] = template;
    }
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
    final zoomOutAtFit = tester.widget<IconButton>(
      find.byKey(const ValueKey('plate-zoom-out-button')),
    );
    expect(zoomOutAtFit.onPressed, isNull);
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

  testWidgets('keeps plate controls usable on a narrow phone', (tester) async {
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
    expect(find.text('피펫팅 계획'), findsOneWidget);
    expect(find.text('Master mix 미리보기'), findsOneWidget);
    expect(find.textContaining('Stock 22 + 희석액 198 µL'), findsOneWidget);
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
    expect(repository.plate!.wells[0].volumeValue, 100);
    expect(repository.plate!.wells[0].volumeUnit, 'µL');
    expect(repository.plate!.wells[2].concentrationValue, isNull);
  });

  testWidgets('blocks dilution when selected wells are insufficient', (
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
    await tester.tap(find.byTooltip('희석 계산 적용'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('희석 적용'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('희석 적용'));
    await tester.pumpAndSettle();

    expect(find.textContaining('사용 가능한 well이 부족합니다.'), findsOneWidget);
    expect(find.text('희석 계산 적용'), findsOneWidget);
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
    expect(repository.plate!.importHistory.single.sourceName, '클립보드');
    expect(repository.plate!.importHistory.single.valueCount, 4);
  });

  testWidgets('loads a result matrix from a picked CSV/TSV file', (
    tester,
  ) async {
    final repository = FakePlateRepository();
    final exchange = FakeDocumentExchangeService()
      ..documentToPick = const ImportedTextDocument(
        name: 'reader-results.tsv',
        content: '\t1\t2\nA\t1.02\t1.04\nB\t0.98\t0.99',
      );

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

    await tester.tap(find.byKey(const ValueKey('bulk-result-import-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('pick-bulk-result-file-button')),
    );
    await tester.pumpAndSettle();

    expect(exchange.pickCalls, 1);
    expect(exchange.pickedExtensions, ['csv', 'tsv', 'txt']);
    expect(find.textContaining('reader-results.tsv'), findsOneWidget);
    expect(find.textContaining('숫자 4개 인식'), findsOneWidget);
    expect(find.text('적용 단위: OD450'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('bulk-result-wavelength-field')),
      '570',
    );
    await tester.pumpAndSettle();
    expect(find.text('적용 단위: OD570'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('apply-bulk-results-button')),
    );
    await tester.tap(find.byKey(const ValueKey('apply-bulk-results-button')));
    await tester.pumpAndSettle();

    expect(repository.plate!.wells[0].resultValue, 1.02);
    expect(repository.plate!.wells[1].resultValue, 1.04);
    expect(repository.plate!.wells[12].resultValue, 0.98);
    expect(repository.plate!.wells[13].resultValue, 0.99);
    expect(repository.plate!.wells[0].resultUnit, 'OD570');
    expect(
      repository.plate!.importHistory.single.sourceName,
      'reader-results.tsv',
    );
    expect(repository.plate!.importHistory.single.resultUnit, 'OD570');
  });

  testWidgets(
    'confirms duplicate result files and overwrites before applying',
    (tester) async {
      final repository = FakePlateRepository();
      final original = Plate(
        id: 'plate-1',
        experimentId: 'experiment-1',
        name: '96-well Plate',
      );
      repository.plate = original.copyWith(
        wells: original.wells.map((well) {
          if (well.position ==
              const WellPosition(rowIndex: 0, columnIndex: 0)) {
            return well.copyWith(resultValue: 0.10, resultUnit: 'OD450');
          }
          if (well.position ==
              const WellPosition(rowIndex: 0, columnIndex: 1)) {
            return well.copyWith(resultValue: 0.20, resultUnit: 'OD450');
          }
          return well;
        }).toList(),
        importHistory: [
          PlateResultImportRecord(
            id: 'import-1',
            sourceName: 'reader-results.tsv',
            importedAt: DateTime.utc(2026, 6, 19, 9),
            valueCount: 2,
            resultUnit: 'OD450',
          ),
        ],
      );
      final exchange = FakeDocumentExchangeService()
        ..documentToPick = const ImportedTextDocument(
          name: 'reader-results.tsv',
          content: '\t1\t2\nA\t1.02\t1.04\nB\t0.98\t0.99',
        );

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

      await tester.tap(find.byKey(const ValueKey('bulk-result-import-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('pick-bulk-result-file-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('“reader-results.tsv” 파일은 이미 가져온 이력이 있습니다.'),
        findsOneWidget,
      );
      expect(find.text('기존 결과 2개를 덮어씁니다.'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('apply-bulk-results-button')),
      );
      await tester.tap(find.byKey(const ValueKey('apply-bulk-results-button')));
      await tester.pumpAndSettle();

      expect(find.text('결과 가져오기 확인'), findsOneWidget);
      expect(find.textContaining('이미 가져온 이력이 있습니다'), findsWidgets);
      expect(find.textContaining('기존 결과 2개가 새 값으로 바뀝니다'), findsOneWidget);

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(repository.plate!.wells[0].resultValue, 0.10);
      expect(repository.plate!.importHistory.length, 1);

      await tester.tap(find.byKey(const ValueKey('apply-bulk-results-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('덮어쓰기'));
      await tester.pumpAndSettle();

      expect(repository.plate!.wells[0].resultValue, 1.02);
      expect(repository.plate!.wells[1].resultValue, 1.04);
      expect(repository.plate!.wells[12].resultValue, 0.98);
      expect(repository.plate!.wells[13].resultValue, 0.99);
      expect(repository.plate!.importHistory.length, 2);
      expect(
        repository.plate!.importHistory.first.sourceName,
        'reader-results.tsv',
      );
    },
  );

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
    await tester.scrollUntilVisible(
      find.text('결과 · 0.82 OD450'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
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

  testWidgets('shows blank-corrected group analysis and exclusions', (
    tester,
  ) async {
    final exchange = FakeDocumentExchangeService();
    const group = WellGroup(
      id: 'drug-a',
      name: 'Drug A',
      shortLabel: 'A',
      color: Colors.purple,
    );
    final repository = FakePlateRepository();
    final base = Plate(
      id: 'plate-1',
      experimentId: 'experiment-1',
      name: '96-well Plate',
      groups: const [group],
    );
    final replacements = <WellPosition, Well>{
      const WellPosition(rowIndex: 0, columnIndex: 0): const Well(
        position: WellPosition(rowIndex: 0, columnIndex: 0),
        role: WellRole.blank,
        resultValue: 0.1,
        resultUnit: 'OD450',
      ),
      const WellPosition(rowIndex: 0, columnIndex: 1): const Well(
        position: WellPosition(rowIndex: 0, columnIndex: 1),
        role: WellRole.vehicleControl,
        resultValue: 1.1,
        resultUnit: 'OD450',
      ),
      const WellPosition(rowIndex: 1, columnIndex: 0): const Well(
        position: WellPosition(rowIndex: 1, columnIndex: 0),
        groupId: 'drug-a',
        role: WellRole.treatment,
        concentrationValue: 100,
        concentrationUnit: 'µM',
        resultValue: 0.6,
        resultUnit: 'OD450',
      ),
      const WellPosition(rowIndex: 1, columnIndex: 1): const Well(
        position: WellPosition(rowIndex: 1, columnIndex: 1),
        groupId: 'drug-a',
        role: WellRole.treatment,
        concentrationValue: 100,
        concentrationUnit: 'µM',
        resultValue: 0.8,
        resultUnit: 'OD450',
      ),
      const WellPosition(rowIndex: 1, columnIndex: 2): const Well(
        position: WellPosition(rowIndex: 1, columnIndex: 2),
        groupId: 'drug-a',
        role: WellRole.treatment,
        concentrationValue: 100,
        concentrationUnit: 'µM',
        resultValue: 99,
        resultUnit: 'OD450',
        excluded: true,
      ),
    };
    repository.plate = base.copyWith(
      wells: [
        for (final well in base.wells) replacements[well.position] ?? well,
      ],
    );

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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('plate-analysis-card')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('기본 결과 분석'), findsOneWidget);
    expect(find.text('사용 4 · 제외 1'), findsOneWidget);
    expect(find.text('Drug A · 100 µM'), findsOneWidget);
    expect(find.text('평균 · 0.7'), findsOneWidget);
    expect(find.text('Blank 보정 · 0.6'), findsOneWidget);
    expect(find.text('Control 대비 · 60%'), findsOneWidget);
    expect(find.text('분석 제외 1개 · B3'), findsOneWidget);
    expect(find.text('농도별 차트'), findsOneWidget);
    expect(find.text('Control 대비 (%)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('analysis-chart-Drug A-OD450')),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('share-analysis-file-button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-analysis-file-button')));
    await tester.pumpAndSettle();

    expect(exchange.shareCalls, 1);
    expect(exchange.sharedFileName, '96-well-Plate-analysis.tsv');
    expect(exchange.sharedMimeType, 'text/tab-separated-values');
    expect(exchange.sharedContent, contains('PlateNote analysis export'));
    expect(exchange.sharedContent, contains('Drug A\ttreatment\t100'));
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
    expect(find.textContaining('PlateNote plate export'), findsOneWidget);
    expect(find.text('복사하기'), findsOneWidget);
    expect(find.text('파일 공유'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('share-plate-file-button')));
    await tester.pumpAndSettle();

    expect(exchange.shareCalls, 1);
    expect(exchange.sharedFileName, '96-well-Plate.tsv');
    expect(exchange.sharedMimeType, 'text/tab-separated-values');
    expect(exchange.sharedContent, contains('PlateNote plate export'));
  });

  testWidgets('saves the current plate as a reusable template', (tester) async {
    final repository = FakePlateRepository();
    final templateRepository = FakePlateTemplateRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: PlateEditorScreen(
          experimentId: 'experiment-1',
          repository: repository,
          templateRepository: templateRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Plate 템플릿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('현재 Plate를 템플릿으로 저장'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('plate-template-name-field')),
      '반복 실험 템플릿',
    );
    await tester.tap(find.byKey(const ValueKey('confirm-save-plate-template')));
    await tester.pumpAndSettle();

    expect(templateRepository.templates.single.name, '반복 실험 템플릿');
    expect(find.textContaining('템플릿을 저장했습니다'), findsOneWidget);
  });

  testWidgets('applies a template without copying measured results', (
    tester,
  ) async {
    final repository = FakePlateRepository();
    final templateRepository = FakePlateTemplateRepository()
      ..templates.add(
        PlateTemplate.fromPlate(
          id: 'template-1',
          name: '10 µM 처리군',
          createdAt: DateTime.utc(2026, 6, 12),
          plate: Plate(id: 'source', experimentId: 'source', name: 'Source')
              .copyWith(
            wells: Plate(
              id: 'source-wells',
              experimentId: 'source',
              name: 'Source',
            ).wells.map((well) {
              if (well.position ==
                  const WellPosition(rowIndex: 0, columnIndex: 0)) {
                return well.copyWith(
                  role: WellRole.treatment,
                  concentrationValue: 10,
                  resultValue: 9.9,
                  excluded: true,
                );
              }
              return well;
            }).toList(),
          ),
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: PlateEditorScreen(
          experimentId: 'experiment-1',
          repository: repository,
          templateRepository: templateRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Plate 템플릿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장된 템플릿 적용'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 µM 처리군'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-apply-plate-template')),
    );
    await tester.pumpAndSettle();

    final applied = repository.plate!.wellAt(
      const WellPosition(rowIndex: 0, columnIndex: 0),
    );
    expect(applied.concentrationValue, 10);
    expect(applied.resultValue, isNull);
    expect(applied.excluded, isFalse);
    expect(find.textContaining('템플릿을 적용했습니다'), findsOneWidget);
  });

  testWidgets(
    'renames and deletes saved plate templates from management dialog',
    (tester) async {
      final repository = FakePlateRepository();
      final templateRepository = FakePlateTemplateRepository()
        ..templates.add(
          PlateTemplate.fromPlate(
            id: 'template-1',
            name: 'Old template',
            createdAt: DateTime.utc(2026, 6, 12),
            plate: Plate(id: 'source', experimentId: 'source', name: 'Source'),
          ),
        )
        ..templates.add(
          PlateTemplate.fromPlate(
            id: 'template-2',
            name: 'Delete me',
            createdAt: DateTime.utc(2026, 6, 11),
            plate: Plate(
              id: 'source-2',
              experimentId: 'source',
              name: 'Source',
            ),
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: PlateEditorScreen(
            experimentId: 'experiment-1',
            repository: repository,
            templateRepository: templateRepository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Plate 템플릿'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('템플릿 관리'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('rename-plate-template-template-1')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('rename-plate-template-name-field')),
        'Renamed template',
      );
      await tester.tap(
        find.byKey(const ValueKey('confirm-rename-plate-template')),
      );
      await tester.pumpAndSettle();

      expect(
        templateRepository.templates
            .firstWhere((item) => item.id == 'template-1')
            .name,
        'Renamed template',
      );
      expect(find.text('Renamed template'), findsOneWidget);
      expect(find.textContaining('이름을 변경했습니다'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('delete-plate-template-template-2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-delete-plate-template')),
      );
      await tester.pumpAndSettle();

      expect(
        templateRepository.templates.any((item) => item.id == 'template-2'),
        isFalse,
      );
      expect(find.text('Delete me'), findsNothing);
    },
  );

  testWidgets(
    'applies a built-in CCK-8 template when no saved template exists',
    (tester) async {
      final repository = FakePlateRepository();
      final templateRepository = FakePlateTemplateRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: PlateEditorScreen(
            experimentId: 'experiment-1',
            repository: repository,
            templateRepository: templateRepository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Plate 템플릿'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장된 템플릿 적용'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('기본 · CCK-8 2배 희석 3반복'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-apply-plate-template')),
      );
      await tester.pumpAndSettle();

      expect(
        repository.plate!
            .wellAt(const WellPosition(rowIndex: 0, columnIndex: 6))
            .concentrationValue,
        100,
      );
      expect(
        repository.plate!
            .wellAt(const WellPosition(rowIndex: 0, columnIndex: 0))
            .role,
        WellRole.blank,
      );
      expect(find.textContaining('템플릿을 적용했습니다'), findsOneWidget);
    },
  );
}

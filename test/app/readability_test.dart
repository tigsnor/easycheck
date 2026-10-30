import 'package:easycheck/app/theme.dart';
import 'package:easycheck/features/experiments/presentation/experiments_home_screen.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well_group.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:easycheck/features/plates/presentation/widgets/plate_grid.dart';
import 'package:easycheck/shared/presentation/save_status_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/experiments/presentation/experiments_home_screen_test.dart'
    as home;
import '../features/plates/presentation/plate_editor_screen_test.dart'
    as plates;

void main() {
  double contrast(Color a, Color b) {
    final values = [a.computeLuminance(), b.computeLuminance()]..sort();
    return (values.last + 0.05) / (values.first + 0.05);
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.pumpAndSettle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(ValueKey(value));
  void narrow(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
  }

  Widget app(Widget child, {bool large = false}) => MaterialApp(
        theme: buildEasyCheckTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(large ? 1.6 : 1)),
            child: child!),
        home: child,
      );

  test(
      'theme text and action colors remain readable on the surfaces actually used',
      () {
    final theme = buildEasyCheckTheme();
    final c = theme.colorScheme;
    for (final background in [
      c.surface,
      c.surfaceContainerLow,
      c.surfaceContainerHighest
    ]) {
      for (final text in [
        c.primary,
        c.onSurface,
        c.onSurfaceVariant,
        c.tertiary
      ]) {
        expect(contrast(text, background), greaterThanOrEqualTo(4.5));
      }
    }
    expect(contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
    expect(contrast(c.onPrimaryContainer, c.primaryContainer),
        greaterThanOrEqualTo(4.5));
    expect(contrast(c.error, c.errorContainer), greaterThanOrEqualTo(4.5));
    expect(contrast(c.onErrorContainer, c.errorContainer),
        greaterThanOrEqualTo(4.5));
    final disabled = theme.filledButtonTheme.style!;
    expect(
        contrast(disabled.foregroundColor!.resolve({WidgetState.disabled})!,
            disabled.backgroundColor!.resolve({WidgetState.disabled})!),
        greaterThanOrEqualTo(4.5));
    expect(theme.textTheme.bodySmall!.fontSize, greaterThanOrEqualTo(14));
  });

  testWidgets(
      'save status uses words and icons with readable foregrounds in every state',
      (tester) async {
    for (final status in SaveStatus.values) {
      await tester.pumpWidget(app(
          Scaffold(body: SaveStatusIndicator(status: status, onRetry: () {}))));
      await tester.pumpAndSettle();
      final text =
          tester.renderObject<RenderParagraph>(key('save-status-label'));
      final background =
          tester.widget<Material>(key('save-status-banner')).color!;
      expect(contrast(text.text.style!.color!, background),
          greaterThanOrEqualTo(4.5));
      expect(find.byType(Icon), findsWidgets);
      expect(text.text.toPlainText(), isNotEmpty);
    }
  });

  testWidgets(
      'custom group colors keep text and selected borders readable without changing saved colors',
      (tester) async {
    const colors = [Color(0xFF2196F3), Color(0xFF101010), Color(0x99FFCC33)];
    final base = Plate(
        id: 'p',
        experimentId: 'e',
        name: 'Contrast',
        rowCount: 1,
        columnCount: 3,
        groups: [
          for (var i = 0; i < colors.length; i++)
            WellGroup(
                id: '$i', name: 'Group $i', shortLabel: 'G$i', color: colors[i])
        ]);
    final plate = base.copyWith(wells: [
      for (var i = 0; i < 3; i++)
        base.wells[i].copyWith(groupId: '$i', concentrationValue: 10)
    ]);
    final before = plate.toJson();
    await tester.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(
            child: PlateGrid(
      plate: plate,
      selectedPositions: plate.wells.map((w) => w.position).toSet(),
      requestedCellSize: 64,
      onZoomOut: null,
      onFit: null,
      onZoomIn: null,
      onSelected: (_) {},
      onRangeSelected: (_) {},
      onRectangleSelected: (_, __) {},
      onToggleDragSelection: () {},
      onRowSelected: (_) {},
      onColumnSelected: (_) {},
    )))));
    await tester.pumpAndSettle();
    for (var i = 1; i <= 3; i++) {
      final well = key('well-A$i');
      final fill = tester
          .widget<Container>(
              find.descendant(of: well, matching: find.byType(Container)))
          .decoration! as BoxDecoration;
      final style = tester
          .widget<DefaultTextStyle>(find
              .descendant(of: well, matching: find.byType(DefaultTextStyle))
              .first)
          .style;
      expect(contrast(style.color!, fill.color!), greaterThanOrEqualTo(4.5));
      expect(contrast((fill.border! as Border).top.color, fill.color!),
          greaterThanOrEqualTo(4.5));
      expect(find.descendant(of: well, matching: find.textContaining('✓ A$i')),
          findsOneWidget);
    }
    expect(plate.toJson(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'real theme keeps creation errors visible at 320px with large text and keyboard',
      (tester) async {
    narrow(tester);
    final repo = home.FakeExperimentRepository([]);
    await tester.pumpWidget(app(
        ExperimentsHomeScreen(
            repository: repo,
            plateRepository: home.FakePlateRepository(),
            plateTemplateRepository: home.FakePlateTemplateRepository()),
        large: true));
    await tap(tester, find.text('첫 실험 만들기'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tap(tester, find.text('생성'));
    final error = find.text('실험 제목을 입력해주세요.');
    expect(error, findsOneWidget);
    expect(tester.getBottomRight(error).dy, lessThan(480));
    expect(repo.experiments, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'real theme keeps plate selection and cell input usable with large text',
      (tester) async {
    narrow(tester);
    final repo = plates.FakePlateRepository()
      ..plate = Plate(id: 'p', experimentId: 'e', name: 'Cells');
    await tester.pumpWidget(app(
        PlateEditorScreen(
            experimentId: 'e',
            repository: repo,
            templateRepository: plates.FakePlateTemplateRepository()),
        large: true));
    await tap(tester, key('well-A1'));
    await tap(tester, key('assign-cell-condition-action'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tap(tester, key('apply-cell-condition'));
    final error = find.text('세포 종류를 입력해주세요.');
    expect(tester.getBottomRight(error).dy, lessThan(480));
    await tester.enterText(key('cell-name-input'), 'HeLa');
    await tester.enterText(key('cell-density-input'), '5000');
    await tap(tester, key('apply-cell-condition'));
    expect(repo.plate!.wells.first.cellCondition!.name, 'HeLa');
    expect(repo.plate!.wells.first.cellCondition!.density, 5000);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:async';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/presentation/experiments_home_screen.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/templates/domain/plate_template.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'experiments_home_screen_test.dart' as fixtures;

class Notes extends fixtures.FakeExperimentRepository {
  Notes() : super([]);
  final attempts = <Experiment>[];
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<void> saveExperiment(Experiment experiment) async {
    attempts.add(experiment);
    await pending?.future;
    await super.saveExperiment(experiment);
    if (fail) {
      fail = false;
      throw StateError('after write failure');
    }
  }
}

class Plates extends fixtures.FakePlateRepository {
  bool failAfterWrite = false;
  bool failDelete = false;
  @override
  Future<void> savePlate(Plate value) async {
    await super.savePlate(value);
    if (failAfterWrite) {
      failAfterWrite = false;
      throw StateError('after write failure');
    }
  }

  @override
  Future<void> deletePlate(String id) async {
    if (failDelete) throw StateError('delete failure');
    await super.deletePlate(id);
  }
}

void main() {
  Finder field(String label) => find.widgetWithText(TextField, label);
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  final template = PlateTemplate.fromPlate(
      id: 'review-template',
      name: 'Review template',
      createdAt: DateTime.utc(2026),
      plate: Plate(id: 'source', experimentId: 'source', name: 'Source'));
  Future<void> open(WidgetTester tester, Notes notes,
      {Plates? plates, bool expandCells = true}) async {
    await tester.pumpWidget(MaterialApp(
        home: ExperimentsHomeScreen(
            repository: notes,
            plateRepository: plates ?? Plates(),
            plateTemplateRepository:
                fixtures.FakePlateTemplateRepository([template]))));
    await tester.pumpAndSettle();
    await tap(tester, find.text('첫 실험 만들기'));
    await tester.enterText(field('실험 제목'), 'Study');
    if (expandCells) {
      await tap(tester, find.text('노트 참고용 세포 정보 (선택)'));
    }
  }

  Future<void> chooseTemplate(WidgetTester tester, String name) async {
    await tap(
        tester, find.byKey(const ValueKey('new-experiment-template-field')));
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'cell validation remains visible above keyboard on a narrow screen',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final notes = Notes();
    await open(tester, notes);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    await tester.enterText(field('세포 이름'), 'HeLa');
    await tap(tester, find.text('생성'));
    final error = find.text('세포 정보를 기록하려면 이름과 세포수를 입력해주세요.');
    expect(error, findsOneWidget);
    expect(tester.getTopLeft(error).dy, greaterThanOrEqualTo(0));
    expect(tester.getBottomRight(error).dy, lessThan(400));
    expect(notes.attempts, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'collapsed reference keeps draft and expands again for validation',
      (tester) async {
    final notes = Notes();
    await open(tester, notes);
    final section = find.text('노트 참고용 세포 정보 (선택)');
    await tester.enterText(field('세포 이름'), 'HeLa');
    await tap(tester, section);
    expect(field('세포 이름'), findsNothing);
    await tap(tester, find.text('생성'));
    expect(field('세포 이름'), findsOneWidget);
    expect(notes.attempts, isEmpty);
    await tester.enterText(field('세포수'), '10000');
    await tap(tester, section);
    await tap(tester, find.text('생성'));
    expect(notes.experiments.single.cellCountLabel, 'HeLa: 10000/ml');
  });

  testWidgets('untouched optional cell info stays absent', (tester) async {
    final notes = Notes();
    await open(tester, notes, expandCells: false);
    expect(field('세포 이름'), findsNothing);
    await tap(tester, find.text('생성'));
    expect(notes.experiments.single.cellCountLabel, isNull);
  });
  testWidgets(
      'partial and invalid cell info never fabricates values; zero is valid',
      (tester) async {
    final notes = Notes();
    await open(tester, notes);
    await tester.enterText(field('세포 이름'), 'HeLa');
    await tap(tester, find.text('생성'));
    expect(notes.attempts, isEmpty);
    for (final pair in [
      ('', '4'),
      ('NaN', '4'),
      ('-1', '4'),
      ('1', '1.5'),
      ('1', '999'),
      ('1', '-999')
    ]) {
      await tester.enterText(field('세포수'), pair.$1);
      await tester.enterText(field('10^n'), pair.$2);
      await tap(tester, find.text('생성'));
      expect(notes.attempts, isEmpty);
    }
    await tester.enterText(field('세포수'), '0');
    await tester.enterText(field('10^n'), '4');
    await tap(tester, find.text('생성'));
    expect(notes.experiments.single.cellCountLabel, 'HeLa: 0×10^4/ml');
  });
  for (final input in [
    ('10000', '', '10000'),
    ('1', '4', '1×10^4'),
    ('1e4', '', '1e4')
  ]) {
    testWidgets(
        'creation scientific preview matches saved quantity ${input.$1}/${input.$2}',
        (tester) async {
      final notes = Notes();
      await open(tester, notes);
      await tester.enterText(field('세포 이름'), 'HeLa');
      await tester.enterText(field('세포수'), input.$1);
      await tester.enterText(field('10^n'), input.$2);
      await tester.pumpAndSettle();
      expect(find.text('입력값: 10,000 cells/mL'), findsOneWidget);
      await tap(tester, find.text('생성'));
      expect(notes.experiments.single.cellCountLabel, 'HeLa: ${input.$3}/ml');
    });
  }
  testWidgets('failed save keeps all fields and retries with the same identity',
      (tester) async {
    final notes = Notes()..fail = true;
    await open(tester, notes);
    for (final pair in [
      ('프로젝트', 'Project X'),
      ('메모', 'Keep note'),
      ('세포 이름', 'HeLa'),
      ('세포수', '2.5'),
      ('10^n', '4')
    ]) {
      await tester.enterText(field(pair.$1), pair.$2);
    }
    await tap(tester, find.text('생성'));
    expect(notes.experiments, isEmpty);
    expect(find.byKey(const ValueKey('create-experiment-save-error')),
        findsOneWidget);
    expect(tester.widget<TextField>(field('메모')).controller!.text, 'Keep note');
    expect(tester.widget<TextField>(field('세포수')).controller!.text, '2.5');
    await tester.enterText(field('실험 제목'), 'Corrected');
    await tap(tester, find.text('생성'));
    expect(notes.attempts.map((e) => e.id).toSet().length, 1);
    expect(notes.attempts.map((e) => e.createdAt).toSet().length, 1);
    final saved = notes.experiments.single;
    expect(saved.title, 'Corrected');
    expect(saved.projectName, 'Project X');
    expect(saved.notes, 'Keep note');
    expect(saved.cellCountLabel, 'HeLa: 2.5×10^4/ml');
  });
  testWidgets(
      'pending save blocks duplicate create and back; dirty close confirms',
      (tester) async {
    final notes = Notes()..pending = Completer<void>();
    await open(tester, notes);
    await tap(tester, find.byTooltip('닫기'));
    expect(find.text('작성 중인 새 실험을 버릴까요?'), findsOneWidget);
    await tester.tap(find.text('계속 작성'));
    await tester.pumpAndSettle();
    await tap(tester, find.text('생성'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(notes.attempts.length, 1);
    expect(find.text('저장 중…'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '저장 중…'))
            .onPressed,
        isNull);
    notes.pending!.complete();
    await tester.pumpAndSettle();
    expect(notes.experiments.length, 1);
    expect(find.text('새 실험 노트'), findsNothing);
  });
  for (final removeTemplate in [false, true]) {
    testWidgets(
        'template rollback retry with removal=$removeTemplate leaves one consistent experiment',
        (tester) async {
      final notes = Notes();
      final plates = Plates()
        ..failAfterWrite = true
        ..failDelete = true;
      await open(tester, notes, plates: plates);
      await chooseTemplate(tester, 'Review template');
      await tap(tester, find.text('생성'));
      expect(notes.experiments, isEmpty);
      expect(plates.plate, isNotNull);
      expect(find.textContaining('정리도 실패'), findsOneWidget);
      plates.failDelete = false;
      if (removeTemplate) await chooseTemplate(tester, '빈 Plate로 시작');
      await tap(tester, find.text('생성'));
      expect(notes.attempts.map((e) => e.id).toSet().length, 1);
      final saved = notes.experiments.single;
      if (removeTemplate) {
        expect(plates.plate, isNull);
      } else {
        expect(plates.plate!.experimentId, saved.id);
      }
    });
  }
  testWidgets('discard cannot close while partial persistence cleanup fails',
      (tester) async {
    final notes = Notes();
    final plates = Plates()
      ..failAfterWrite = true
      ..failDelete = true;
    await open(tester, notes, plates: plates);
    await chooseTemplate(tester, 'Review template');
    await tap(tester, find.text('생성'));
    await tap(tester, find.byTooltip('닫기'));
    await tester.tap(find.text('입력 버리고 닫기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('정리하지 못해 닫지 않았습니다'), findsOneWidget);
    expect(plates.plate, isNotNull);
    plates.failDelete = false;
    await tap(tester, find.byTooltip('닫기'));
    await tester.tap(find.text('입력 버리고 닫기'));
    await tester.pumpAndSettle();
    expect(plates.plate, isNull);
    expect(notes.experiments, isEmpty);
    expect(find.text('새 실험 노트'), findsNothing);
  });
}

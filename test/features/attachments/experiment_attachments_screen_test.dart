import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:easycheck/features/attachments/data/attachment_exchange_service.dart';
import 'package:easycheck/shared/services/document_exchange_service.dart';
import 'package:easycheck/features/attachments/presentation/experiment_attachments_screen.dart';
import 'package:easycheck/features/attachments/domain/experiment_attachment.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/presentation/experiment_detail_screen.dart';
import 'package:easycheck/features/experiments/presentation/experiments_home_screen.dart';
import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/attachment_fixture.dart';
import '../../support/fake_document_exchange_service.dart';
import '../plates/presentation/plate_editor_screen_test.dart'
    show FakePlateRepository, FakePlateTemplateRepository;
import '../experiments/presentation/experiments_home_screen_test.dart'
    show FakeExperimentRepository;

void main() {
  late MemoryAttachmentStore files;
  late FakeAttachmentExchange exchange;
  setUp(() {
    files = MemoryAttachmentStore();
    exchange = FakeAttachmentExchange()
      ..picked =
          PickedAttachment(name: 'reader.csv', bytes: attachmentBlob().bytes);
  });
  Future<void> open(WidgetTester tester,
      {Experiment? experiment,
      bool readOnly = false,
      Future<void> Function(Experiment)? save,
      double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: ExperimentAttachmentsScreen(
            experiment: experiment ?? attachedExperiment(attachments: []),
            plate: Plate(id: 'p', experimentId: 'e', name: 'P'),
            readOnly: readOnly,
            onChanged: save ?? (_) async {},
            fileStore: files,
            exchange: exchange)));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'imports original with description and well link, edits metadata and shares exact bytes',
      (tester) async {
    Experiment? saved;
    await open(tester, save: (e) async {
      saved = e;
    });
    await tap(tester, 'add-attachment-file');
    await tester.enterText(
        find.byKey(const ValueKey('attachment-description')), '기포 관찰');
    await tap(tester, 'attachment-scope');
    await tester.tap(find.text('특정 well').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('attachment-well')), 'h12');
    await tap(tester, 'save-attachment');
    final a = saved!.attachments.single;
    expect(a.wellLabel, 'H12');
    expect(a.scope, AttachmentScope.well);
    expect(a.description, '기포 관찰');
    expect(a.observedAt, isNull);
    expect(files.files[a.digest], attachmentBlob().bytes);
    expect(find.text('Well H12 · ${attachmentBlob().bytes.length} B'),
        findsOneWidget);
    await tap(tester, 'edit-attachment-${a.id}');
    await tester.enterText(
        find.byKey(const ValueKey('attachment-description')), '확인 완료');
    await tap(tester, 'save-attachment');
    expect(saved!.attachments.single.digest, a.digest);
    expect(saved!.attachments.single.description, '확인 완료');
    expect(files.writes, 1);
    await tap(tester, 'share-attachment-${a.id}');
    expect(exchange.sharedBytes, attachmentBlob().bytes);
    expect(exchange.sharedName, 'reader.csv');
  });

  testWidgets('invalid well and cancelled draft never save bytes or metadata',
      (tester) async {
    var saves = 0;
    await open(tester, save: (_) async {
      saves++;
    });
    await tap(tester, 'add-attachment-file');
    await tap(tester, 'attachment-scope');
    await tester.tap(find.text('특정 well').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('attachment-well')), 'Z99');
    await tap(tester, 'save-attachment');
    expect(find.textContaining('올바른 well 좌표'), findsOneWidget);
    expect(saves, 0);
    expect(files.writes, 0);
    await tap(tester, 'close-attachment-editor');
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();
    expect(find.text('Z99'), findsOneWidget);
    await tap(tester, 'close-attachment-editor');
    await tester.tap(find.text('변경 버리고 닫기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-attachment')), findsNothing);
    expect(files.files, isEmpty);
  });

  testWidgets('binary save failure retains selected file and caption for retry',
      (tester) async {
    files.failWrite = true;
    var saves = 0;
    await open(tester, save: (_) async {
      saves++;
    });
    await tap(tester, 'add-attachment-file');
    await tester.enterText(
        find.byKey(const ValueKey('attachment-description')), 'keep caption');
    await tap(tester, 'save-attachment');
    expect(saves, 0);
    expect(find.textContaining('선택한 파일과 입력은 유지'), findsOneWidget);
    expect(find.text('keep caption'), findsOneWidget);
    files.failWrite = false;
    await tap(tester, 'save-attachment');
    expect(saves, 1);
    expect(exchange.picks, 1);
  });

  testWidgets(
      'metadata failure and pending save do not duplicate writes or allow closing',
      (tester) async {
    final gate = Completer<void>();
    var saves = 0;
    Experiment? saved;
    await open(tester, save: (e) async {
      saves++;
      if (saves == 1) {
        await gate.future;
        throw StateError('failed');
      }
      saved = e;
    });
    await tap(tester, 'add-attachment-file');
    await tester.ensureVisible(find.byKey(const ValueKey('save-attachment')));
    await tester.tap(find.byKey(const ValueKey('save-attachment')));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('save-attachment')))
            .onPressed,
        isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const ValueKey('save-attachment')), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('선택한 파일과 입력은 유지'), findsOneWidget);
    await tap(tester, 'save-attachment');
    expect(saves, 2);
    expect(saved!.attachments, hasLength(1));
    expect(saved!.revisions, hasLength(1));
  });

  testWidgets(
      'removal requires confirmation and keeps metadata on save failure',
      (tester) async {
    await files.write(attachmentBlob());
    var fail = true;
    Experiment? saved;
    await open(tester, experiment: attachedExperiment(), save: (e) async {
      if (fail) throw StateError('failed');
      saved = e;
    });
    await tap(tester, 'remove-attachment-a');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('reader.csv'), findsOneWidget);
    await tap(tester, 'remove-attachment-a');
    await tap(tester, 'confirm-remove-attachment');
    expect(find.text('reader.csv'), findsOneWidget);
    fail = false;
    await tap(tester, 'remove-attachment-a');
    await tap(tester, 'confirm-remove-attachment');
    expect(saved!.attachments, isEmpty);
    expect(files.files[attachmentBlob().digest], isNotNull);
  });

  testWidgets(
      'read-only screen flags missing originals and has no mutation actions',
      (tester) async {
    var saves = 0;
    await open(tester, experiment: attachedExperiment(), readOnly: true,
        save: (_) async {
      saves++;
    });
    expect(find.textContaining('원본 누락 또는 손상'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-attachment-file')), findsNothing);
    expect(find.byKey(const ValueKey('remove-attachment-a')), findsNothing);
    await tap(tester, 'share-attachment-a');
    expect(find.textContaining('원본을 공유하지 못했습니다'), findsOneWidget);
    expect(saves, 0);
  });

  testWidgets(
      'picker cancellation and oversized files leave the experiment unchanged',
      (tester) async {
    var saves = 0;
    await open(tester, save: (_) async {
      saves++;
    });
    exchange.picked = null;
    await tap(tester, 'add-attachment-photo');
    expect(exchange.imageOnly, true);
    expect(find.byKey(const ValueKey('save-attachment')), findsNothing);
    exchange.picked = PickedAttachment(
        name: 'big.dat', bytes: Uint8List(maxAttachmentBytes + 1));
    await tap(tester, 'add-attachment-file');
    expect(find.textContaining('10MB를 초과'), findsOneWidget);
    expect(files.writes, 0);
    expect(saves, 0);
  });

  testWidgets(
      'photo preview and editing work on a narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final png = AttachmentBlob(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a/e8AAAAASUVORK5CYII='));
    await files.write(png);
    await open(tester,
        experiment: attachedExperiment(
            attachments: [attachment(blob: png, name: 'photo.png')]),
        scale: 1.6);
    await tester.ensureVisible(find.text('사진 보기'));
    await tester.tap(find.text('사진 보기'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tap(tester, 'edit-attachment-a');
    await tester.enterText(
        find.byKey(const ValueKey('attachment-description')), '사진 설명');
    await tap(tester, 'save-attachment');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'experiment detail saves draft before opening attachments and retains updates on later saves',
      (tester) async {
    Experiment? saved;
    await tester.pumpWidget(MaterialApp(
        home: ExperimentDetailScreen(
            experiment: attachedExperiment(attachments: []),
            onChanged: (e) async {
              saved = e;
            },
            attachmentFileStore: files,
            attachmentExchange: exchange,
            plateRepository: FakePlateRepository())));
    await tester.enterText(
        find.widgetWithText(TextField, 'Assay'), 'Edited assay');
    await tap(tester, 'open-experiment-attachments');
    expect(saved!.title, 'Edited assay');
    await tap(tester, 'add-attachment-file');
    await tap(tester, 'save-attachment');
    expect(saved!.attachments, hasLength(1));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '저장'));
    await tester.pumpAndSettle();
    expect(saved!.attachments, hasLength(1));
  });

  testWidgets(
      'backup UI includes attachments and blocks exporting a missing original',
      (tester) async {
    final repo = FakeExperimentRepository([attachedExperiment()]);
    final docs = FakeDocumentExchangeService();
    await files.write(attachmentBlob());
    await tester.pumpWidget(MaterialApp(
        home: ExperimentsHomeScreen(
            repository: repo,
            plateRepository: FakePlateRepository(),
            plateTemplateRepository: FakePlateTemplateRepository(),
            attachmentFileStore: files,
            documentExchangeService: docs)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('전체 데이터 백업 및 복원'));
    await tester.pumpAndSettle();
    await tap(tester, 'share-backup-file-button');
    final backup = const EasyCheckBackupService().decode(docs.sharedContent!);
    expect(backup.attachmentFiles.values.single.bytes, attachmentBlob().bytes);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    files.files.clear();
    await tester.tap(find.byTooltip('전체 데이터 백업 및 복원'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('backup-export-unavailable')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('share-backup-file-button')), findsNothing);
  });
  testWidgets(
      'picked backup restores missing attachment originals through the home UI',
      (tester) async {
    final repo = FakeExperimentRepository([attachedExperiment()]);
    final docs = FakeDocumentExchangeService()
      ..documentToPick = ImportedTextDocument(
          name: 'with-attachments.json',
          content: const EasyCheckBackupService().encode(
              experiments: [attachedExperiment()],
              plates: [],
              attachmentFiles: {attachmentBlob().digest: attachmentBlob()}));
    await tester.pumpWidget(MaterialApp(
        home: ExperimentsHomeScreen(
            repository: repo,
            plateRepository: FakePlateRepository(),
            plateTemplateRepository: FakePlateTemplateRepository(),
            attachmentFileStore: files,
            documentExchangeService: docs)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('전체 데이터 백업 및 복원'));
    await tester.pumpAndSettle();
    await tap(tester, 'pick-backup-file-button');
    expect(find.text('첨부 1개 · 원본 무결성 검사 완료'), findsOneWidget);
    await tap(tester, 'restore-backup-button');
    expect(files.files, isEmpty);
    await tap(tester, 'confirm-restore-backup-button');
    expect(files.files[attachmentBlob().digest], attachmentBlob().bytes);
    expect(repo.experiments.single.attachments.single.digest,
        attachmentBlob().digest);
  });
}

import 'dart:convert';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

class ImportedTextDocument {
  const ImportedTextDocument({required this.name, required this.content});

  final String name;
  final String content;
}

enum DocumentShareStatus { success, dismissed, unavailable }

abstract interface class DocumentExchangeService {
  Future<DocumentShareStatus> shareTextDocument({
    required String content,
    required String fileName,
    required String mimeType,
    String? subject,
    Rect? sharePositionOrigin,
  });

  Future<ImportedTextDocument?> pickTextDocument({
    required List<String> allowedExtensions,
  });
}

class PlatformDocumentExchangeService implements DocumentExchangeService {
  const PlatformDocumentExchangeService();

  @override
  Future<DocumentShareStatus> shareTextDocument({
    required String content,
    required String fileName,
    required String mimeType,
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(utf8.encode(content), mimeType: mimeType)],
        fileNameOverrides: [fileName],
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => DocumentShareStatus.success,
      ShareResultStatus.dismissed => DocumentShareStatus.dismissed,
      ShareResultStatus.unavailable => DocumentShareStatus.unavailable,
    };
  }

  @override
  Future<ImportedTextDocument?> pickTextDocument({
    required List<String> allowedExtensions,
  }) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (result == null || result.xFiles.isEmpty) {
      return null;
    }

    final file = result.xFiles.single;
    return ImportedTextDocument(
      name: file.name,
      content: await file.readAsString(),
    );
  }
}

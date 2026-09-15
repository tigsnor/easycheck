import 'dart:ui';

import 'package:easycheck/shared/services/document_exchange_service.dart';

class FakeDocumentExchangeService implements DocumentExchangeService {
  ImportedTextDocument? documentToPick;
  DocumentShareStatus shareStatus = DocumentShareStatus.success;
  int shareCalls = 0;
  int pickCalls = 0;
  String? sharedContent;
  String? sharedFileName;
  String? sharedMimeType;
  List<String>? pickedExtensions;

  @override
  Future<ImportedTextDocument?> pickTextDocument({
    required List<String> allowedExtensions,
  }) async {
    pickCalls += 1;
    pickedExtensions = allowedExtensions;
    return documentToPick;
  }

  @override
  Future<DocumentShareStatus> shareTextDocument({
    required String content,
    required String fileName,
    required String mimeType,
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    shareCalls += 1;
    sharedContent = content;
    sharedFileName = fileName;
    sharedMimeType = mimeType;
    return shareStatus;
  }
}

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/services/document_exchange_service.dart';
import '../../experiments/domain/experiment.dart';
import '../../plates/domain/plate.dart';
import '../data/attachment_exchange_service.dart';
import '../data/attachment_file_store.dart';
import '../domain/experiment_attachment.dart';

class ExperimentAttachmentsScreen extends StatefulWidget {
  const ExperimentAttachmentsScreen(
      {required this.experiment,
      required this.onChanged,
      required this.fileStore,
      required this.exchange,
      this.plate,
      this.readOnly = false,
      super.key});
  final Experiment experiment;
  final Plate? plate;
  final bool readOnly;
  final Future<void> Function(Experiment) onChanged;
  final AttachmentFileStore fileStore;
  final AttachmentExchangeService exchange;
  @override
  State<ExperimentAttachmentsScreen> createState() =>
      _ExperimentAttachmentsScreenState();
}

class _ExperimentAttachmentsScreenState
    extends State<ExperimentAttachmentsScreen> {
  late Experiment _experiment = widget.experiment;
  bool _busy = false;
  String? _error;
  Map<String, String> _fileErrors = {};

  @override
  void initState() {
    super.initState();
    _checkFiles();
  }

  Future<void> _checkFiles() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final errors = <String, String>{};
    for (final attachment in _experiment.attachments) {
      try {
        await widget.fileStore.read(attachment);
      } on Object {
        errors[attachment.id] = '원본 누락 또는 손상';
      }
    }
    if (mounted) {
      setState(() {
        _fileErrors = errors;
        _busy = false;
      });
    }
  }

  Future<bool> _save(
      List<ExperimentAttachment> attachments, String summary) async {
    if (_busy || widget.readOnly) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    final now = DateTime.now().toUtc();
    final updated = _experiment
        .copyWith(attachments: attachments, updatedAt: now, revisions: [
      ..._experiment.revisions,
      ExperimentRevision(
          id: const Uuid().v4(), changedAt: now, summary: summary),
    ]);
    try {
      await widget.onChanged(updated);
      if (mounted) {
        setState(() {
          _experiment = updated;
          _busy = false;
        });
      }
      return true;
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '저장하지 못했습니다: $error';
        });
      }
      return false;
    }
  }

  Future<void> _add(bool imageOnly) async {
    if (_busy || widget.readOnly) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    PickedAttachment? picked;
    try {
      picked = await widget.exchange.pick(imageOnly: imageOnly);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '파일을 불러오지 못했습니다: $error');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (picked == null) return;
    final AttachmentBlob blob;
    try {
      blob = AttachmentBlob(picked.bytes);
    } on Object catch (error) {
      setState(() => _error = '$error');
      return;
    }
    final selected = picked;
    final attachment = ExperimentAttachment(
        id: const Uuid().v4(),
        fileName: selected.name,
        digest: blob.digest,
        byteLength: blob.bytes.length,
        addedAt: DateTime.now().toUtc());
    await _edit(attachment, blob: blob);
  }

  Future<void> _edit(ExperimentAttachment attachment,
      {AttachmentBlob? blob}) async {
    if (_busy || widget.readOnly) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        builder: (_) => _AttachmentEditor(
            isNew: blob != null,
            attachment: attachment,
            plate: widget.plate,
            onSave: (updated) async {
              // Write immutable bytes first. Retrying never rewrites a valid original.
              if (blob != null) await widget.fileStore.write(blob);
              final saved = await _save([
                for (final a in _experiment.attachments)
                  if (a.id != updated.id) a,
                updated,
              ], '첨부 ${blob == null ? '정보 수정' : '추가'}: ${updated.fileName}');
              if (saved) _fileErrors.remove(updated.id);
              return saved;
            }));
  }

  Future<void> _remove(ExperimentAttachment attachment) async {
    if (_busy || widget.readOnly) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('첨부를 제거할까요?'),
                content: Text(
                    '${attachment.fileName}\n이 실험의 첨부 목록과 이후 백업에서 제외합니다. 기기에 선택했던 원본은 변경하지 않습니다.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소')),
                  FilledButton(
                      key: const ValueKey('confirm-remove-attachment'),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('제거'))
                ]));
    if (confirmed == true && mounted) {
      await _save(
          _experiment.attachments.where((a) => a.id != attachment.id).toList(),
          '첨부 제거: ${attachment.fileName}');
    }
  }

  Future<void> _view(ExperimentAttachment attachment) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await widget.fileStore.read(attachment);
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
              child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * .75,
                  child: Column(children: [
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(attachment.fileName)),
                    Expanded(
                        child: InteractiveViewer(
                            child: Image.memory(bytes,
                                cacheWidth: 1600,
                                fit: BoxFit.contain,
                                errorBuilder: (_, error, stack) => const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text(
                                        '이 사진 형식은 미리보기를 지원하지 않습니다. 원본 공유로 확인해주세요.'))))),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('닫기')),
                  ]))));
    } on Object catch (error) {
      if (mounted) setState(() => _error = '원본을 확인하지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(
      ExperimentAttachment attachment, BuildContext anchor) async {
    if (_busy) return;
    final box = anchor.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await widget.fileStore.read(attachment);
      final result = await widget.exchange
          .share(name: attachment.fileName, bytes: bytes, origin: origin);
      if (mounted && result == DocumentShareStatus.unavailable) {
        setState(() => _error = '이 기기에서는 원본 공유를 사용할 수 없습니다.');
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '원본을 공유하지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('사진·원본 파일'), actions: [
          IconButton(
              tooltip: '원본 상태 다시 확인',
              onPressed: _busy ? null : _checkFiles,
              icon: const Icon(Icons.refresh))
        ]),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(_experiment.title,
              style: Theme.of(context).textTheme.titleMedium),
          Text(
              '첨부 ${_experiment.attachments.length}개 · ${_size(_experiment.attachments.fold(0, (sum, a) => sum + a.byteLength))}'),
          const Text(
              '선택한 원본을 앱에 복사합니다. 파일당 10MB, 전체 실험의 첨부 원본 합계 50MB까지 지원합니다.'),
          if (widget.readOnly) const Text('완료된 실험: 첨부 조회와 원본 공유만 가능합니다.'),
          if (!widget.readOnly)
            Wrap(spacing: 8, children: [
              FilledButton.icon(
                  key: const ValueKey('add-attachment-photo'),
                  onPressed: _busy ? null : () => _add(true),
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text('사진 선택')),
              OutlinedButton.icon(
                  key: const ValueKey('add-attachment-file'),
                  onPressed: _busy ? null : () => _add(false),
                  icon: const Icon(Icons.attach_file),
                  label: const Text('파일 선택')),
            ]),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_experiment.attachments.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('장비 결과 파일이나 실험 사진을 추가해 원본과 관찰 내용을 함께 보관하세요.')),
          for (final a in _experiment.attachments)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(a.fileName,
                              style: Theme.of(context).textTheme.titleSmall),
                          Text('${a.targetLabel} · ${_size(a.byteLength)}'),
                          Text('추가: ${_time(a.addedAt)}'),
                          if (a.observedAt != null)
                            Text('촬영/측정: ${_time(a.observedAt!)}'),
                          if (a.description.isNotEmpty) Text(a.description),
                          if (_fileErrors.containsKey(a.id))
                            Text('원본 누락 또는 손상 · 백업에서 복원해주세요.',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                          Wrap(spacing: 8, children: [
                            if (a.isPreviewableImage)
                              TextButton(
                                  onPressed: _busy ? null : () => _view(a),
                                  child: const Text('사진 보기')),
                            Builder(
                                builder: (anchor) => TextButton(
                                    key: ValueKey('share-attachment-${a.id}'),
                                    onPressed:
                                        _busy ? null : () => _share(a, anchor),
                                    child: const Text('원본 공유'))),
                            if (!widget.readOnly) ...[
                              TextButton(
                                  key: ValueKey('edit-attachment-${a.id}'),
                                  onPressed: _busy ? null : () => _edit(a),
                                  child: const Text('정보 수정')),
                              TextButton(
                                  key: ValueKey('remove-attachment-${a.id}'),
                                  onPressed: _busy ? null : () => _remove(a),
                                  child: const Text('첨부 제거')),
                            ],
                          ]),
                        ]))),
        ])),
      ));
}

String _size(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
        ? '${(bytes / 1024).toStringAsFixed(1)} KB'
        : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
String _time(DateTime time) => time.toLocal().toString().substring(0, 16);

class _AttachmentEditor extends StatefulWidget {
  const _AttachmentEditor(
      {required this.attachment,
      required this.plate,
      required this.onSave,
      required this.isNew});
  final ExperimentAttachment attachment;
  final Plate? plate;
  final Future<bool> Function(ExperimentAttachment) onSave;
  final bool isNew;
  @override
  State<_AttachmentEditor> createState() => _AttachmentEditorState();
}

class _AttachmentEditorState extends State<_AttachmentEditor> {
  late final _description =
      TextEditingController(text: widget.attachment.description);
  late final _well =
      TextEditingController(text: widget.attachment.wellLabel ?? '');
  late AttachmentScope _scope = widget.attachment.scope;
  late DateTime? _observedAt = widget.attachment.observedAt;
  bool _saving = false;
  bool _allowPop = false;
  bool _confirming = false;
  String? _error;
  // A newly picked file itself is an unsaved change, even with no caption.
  bool get _dirty =>
      widget.isNew ||
      _description.text != widget.attachment.description ||
      _well.text != (widget.attachment.wellLabel ?? '') ||
      _scope != widget.attachment.scope ||
      _observedAt != widget.attachment.observedAt;

  @override
  void initState() {
    super.initState();
    _description.addListener(_changed);
    _well.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _description.dispose();
    _well.dispose();
    super.dispose();
  }

  Future<void> _pop() async {
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _close() async {
    if (_saving || _confirming) return;
    if (!_dirty) {
      await _pop();
      return;
    }
    _confirming = true;
    final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('첨부 변경을 버릴까요?'),
                content: const Text('파일과 정보의 변경 사항은 저장되지 않습니다.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('계속 편집')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('변경 버리고 닫기'))
                ]));
    _confirming = false;
    if (discard == true && mounted) await _pop();
  }

  Future<void> _save() async {
    if (_saving) return;
    final label = _well.text.trim().toUpperCase();
    if (_scope != AttachmentScope.experiment &&
        (widget.plate == null ||
            (_scope == AttachmentScope.well &&
                !widget.plate!.wells.any((w) => w.label == label)))) {
      setState(() => _error = '연결할 Plate 또는 올바른 well 좌표를 확인해주세요.');
      return;
    }
    final old = widget.attachment;
    final updated = ExperimentAttachment(
        id: old.id,
        fileName: old.fileName,
        digest: old.digest,
        byteLength: old.byteLength,
        addedAt: old.addedAt,
        description: _description.text.trim(),
        observedAt: _observedAt,
        scope: _scope,
        wellLabel: _scope == AttachmentScope.well ? label : null);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      ExperimentAttachment.fromJson(updated.toJson());
      if (!await widget.onSave(updated)) throw StateError('저장에 실패했습니다.');
      if (mounted) await _pop();
    } on Object catch (error) {
      if (mounted) {
        setState(
            () => _error = '저장하지 못했습니다. 선택한 파일과 입력은 유지됩니다. 다시 시도해주세요. $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime() async {
    final initial = _observedAt?.toLocal() ?? DateTime.now();
    final date = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(initial.year < 1900 ? initial.year : 1900),
        lastDate: DateTime(initial.year > 2200 ? initial.year : 2200, 12, 31));
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time != null && mounted) {
      setState(() => _observedAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute)
              .toUtc());
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: _allowPop || (!_saving && !_dirty),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _close();
      },
      child: SafeArea(
          child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text('첨부 정보',
                              style: Theme.of(context).textTheme.titleLarge)),
                      IconButton(
                          key: const ValueKey('close-attachment-editor'),
                          tooltip: '닫기',
                          onPressed: _saving ? null : _close,
                          icon: const Icon(Icons.close))
                    ]),
                    Text(widget.attachment.fileName),
                    TextField(
                        key: const ValueKey('attachment-description'),
                        controller: _description,
                        enabled: !_saving,
                        minLines: 2,
                        maxLines: 4,
                        decoration:
                            const InputDecoration(labelText: '설명 / 관찰 내용')),
                    DropdownButtonFormField<AttachmentScope>(
                        key: const ValueKey('attachment-scope'),
                        initialValue: _scope,
                        decoration: const InputDecoration(labelText: '연결 대상'),
                        items: [
                          for (final scope in AttachmentScope.values)
                            DropdownMenuItem(
                                value: scope,
                                enabled: widget.plate != null ||
                                    scope == AttachmentScope.experiment,
                                child: Text(switch (scope) {
                                  AttachmentScope.experiment => '실험 전체',
                                  AttachmentScope.plate => 'Plate 전체',
                                  AttachmentScope.well => '특정 well'
                                })),
                        ],
                        onChanged: _saving
                            ? null
                            : (s) => setState(() => _scope = s!)),
                    if (_scope == AttachmentScope.well)
                      TextField(
                          key: const ValueKey('attachment-well'),
                          controller: _well,
                          enabled: !_saving,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                              labelText: 'Well 좌표', hintText: '예: A1')),
                    const SizedBox(height: 12),
                    Text(_observedAt == null
                        ? '촬영/측정 시각 미지정'
                        : '촬영/측정: ${_time(_observedAt!)}'),
                    Wrap(children: [
                      TextButton(
                          onPressed: _saving ? null : _pickTime,
                          child: const Text('촬영/측정 시각 지정')),
                      if (_observedAt != null)
                        TextButton(
                            onPressed: _saving
                                ? null
                                : () => setState(() => _observedAt = null),
                            child: const Text('시각 지우기'))
                    ]),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    FilledButton(
                        key: const ValueKey('save-attachment'),
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? '저장 중…' : '첨부 저장')),
                  ]))));
}

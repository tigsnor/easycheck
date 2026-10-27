import 'package:flutter/material.dart';

import '../../plates/data/plate_repository.dart';
import '../domain/experiment.dart';
import '../domain/experiment_completion_review.dart';

/// Returning a record approves the review; the caller persists it with completion.
class ExperimentCompletionScreen extends StatefulWidget {
  const ExperimentCompletionScreen(
      {super.key,
      required this.experiment,
      required this.repository,
      required this.onOpenWell,
      required this.onNoteChanged,
      this.initialNote = ''});
  final Experiment experiment;
  final PlateRepository repository;
  final Future<void> Function(String label) onOpenWell;
  final ValueChanged<String> onNoteChanged;
  final String initialNote;

  @override
  State<ExperimentCompletionScreen> createState() =>
      _ExperimentCompletionScreenState();
}

class _ExperimentCompletionScreenState
    extends State<ExperimentCompletionScreen> {
  late final TextEditingController _note;
  ExperimentCompletionReview? _review;
  Object? _error;
  String? _noteError;
  bool _loading = true;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.initialNote);
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plate = await widget.repository.loadPlate(widget.experiment.id);
      final review = const ExperimentCompletionReviewService()
          .review(widget.experiment, plate);
      if (mounted) {
        setState(() {
          _review = review;
          _loading = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(String label) async {
    if (_loading || _confirmed) return;
    setState(() => _loading = true);
    try {
      await widget.onOpenWell(label);
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        await _load();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  void _confirm() {
    final review = _review;
    if (_confirmed || _loading || _error != null || review == null) return;
    if (review.issues.isNotEmpty && _note.text.trim().isEmpty) {
      setState(() => _noteError = '미측정·제외 등 확인 항목의 사유를 적어 주세요.');
      return;
    }
    _confirmed = true;
    Navigator.pop(context, review.record(_note.text));
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return Scaffold(
      appBar: AppBar(title: const Text('완료 전 점검')),
      body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            const Text(
                                'Plate를 읽지 못해 점검할 수 없습니다. 완료 상태는 저장되지 않았습니다.'),
                            const SizedBox(height: 12),
                            FilledButton(
                                onPressed: _load, child: const Text('다시 점검')),
                          ])))
                  : ListView(padding: const EdgeInsets.all(20), children: [
                      Text(
                          review!.issues.isEmpty
                              ? '확인할 항목이 없습니다'
                              : '${review.issues.length}개 항목을 확인해 주세요',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text(
                          '자동 점검은 결과의 과학적 타당성을 판정하지 않습니다. 좌표를 눌러 수정하거나, 의도한 미측정·제외 사유를 메모하고 완료하세요. 단계 수정은 뒤로 돌아가서 진행하세요.'),
                      const SizedBox(height: 16),
                      for (final issue in review.issues)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(issue.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      const SizedBox(height: 6),
                                      Text(issue.message),
                                      if (issue.wellLabels.isNotEmpty)
                                        Wrap(spacing: 6, children: [
                                          for (final label in issue.wellLabels)
                                            ActionChip(
                                                label: Text(label),
                                                tooltip: '$label 수정',
                                                onPressed: () => _open(label))
                                        ]),
                                    ]))),
                      const SizedBox(height: 16),
                      TextField(
                          key: const ValueKey('completion-review-note'),
                          controller: _note,
                          minLines: 3,
                          maxLines: 8,
                          onChanged: (value) {
                            widget.onNoteChanged(value);
                            if (_noteError != null) {
                              setState(() => _noteError = null);
                            }
                          },
                          decoration: InputDecoration(
                              labelText: review.issues.isEmpty
                                  ? '검토 메모 (선택)'
                                  : '검토 메모 (필수)',
                              hintText: '예: H12 기포로 미측정, 분석 제외. 원본 파일 별도 확인.',
                              errorText: _noteError)),
                      const SizedBox(height: 8),
                      const Text(
                          '점검 항목·좌표·메모는 완료 시점의 변경 이력에 함께 저장됩니다. 완료 후에는 수정 잠금이 적용됩니다.'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                          key: const ValueKey('confirm-completion-review'),
                          onPressed: _confirm,
                          icon: const Icon(Icons.task_alt),
                          label: const Text('검토 후 완료 저장')),
                    ])),
    );
  }
}

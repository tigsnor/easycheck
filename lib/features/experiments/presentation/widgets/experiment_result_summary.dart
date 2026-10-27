import 'package:flutter/material.dart';

import '../../../plates/data/plate_repository.dart';
import '../../../plates/domain/plate.dart';

class ExperimentResultSummary extends StatefulWidget {
  const ExperimentResultSummary(
      {super.key, required this.experimentId, required this.repository});
  final String experimentId;
  final PlateRepository repository;

  @override
  State<ExperimentResultSummary> createState() =>
      _ExperimentResultSummaryState();
}

class _ExperimentResultSummaryState extends State<ExperimentResultSummary> {
  late Future<Plate?> _plate;
  @override
  void initState() {
    super.initState();
    _plate = widget.repository.loadPlate(widget.experimentId);
  }

  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<Plate?>(
            future: _plate,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Text('측정 현황을 불러오는 중…');
              }
              if (snapshot.hasError) {
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('측정 현황을 읽지 못했습니다. 저장된 데이터를 확인할 수 없습니다.'),
                      TextButton(
                          onPressed: () => setState(() {
                                _plate = widget.repository
                                    .loadPlate(widget.experimentId);
                              }),
                          child: const Text('현황 다시 불러오기')),
                    ]);
              }
              final plate = snapshot.data;
              if (plate == null) {
                return const Text(
                    '아직 Plate 기록이 없습니다. 설계에서 배치를 만들거나 결과 입력을 시작하세요.');
              }
              final measured =
                  plate.wells.where((well) => well.resultValue != null).length;
              final included = plate.wells
                  .where((well) => well.resultValue != null && !well.excluded)
                  .length;
              final excluded =
                  plate.wells.where((well) => well.excluded).length;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('측정 현황',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('결과 입력 $measured / ${plate.wells.length} well'),
                    Text('분석에 포함된 측정값 $included개 · 분석 제외 표시 $excluded개'),
                    const SizedBox(height: 8),
                    const Text(
                        '전체 well에는 미사용 자리도 포함됩니다. 누락·단위·분석 기준은 완료 전 점검에서 확인하세요.'),
                  ]);
            }),
      ));
}

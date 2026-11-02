import 'package:easycheck/features/plates/domain/plate_exclusion_event.dart';

PlateExclusionEvent exclusionEvent(int index) => PlateExclusionEvent(
    id: 'event-$index',
    wellLabel: 'A1',
    changedAt: DateTime.utc(2026, 11, 2, 10, index),
    source: ExclusionChangeSource.wellEdit,
    reason: '기포 확인 $index',
    beforeExcluded: index.isOdd,
    afterExcluded: index.isEven,
    beforeResult: 0,
    afterResult: 0,
    beforeUnit: 'OD450',
    afterUnit: 'OD450');

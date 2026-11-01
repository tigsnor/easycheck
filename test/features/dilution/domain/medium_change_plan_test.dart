import 'dart:convert';

import 'package:easycheck/features/dilution/domain/medium_change_plan.dart';
import 'package:easycheck/features/plates/domain/assay_condition.dart';
import 'package:easycheck/features/plates/domain/measured_condition_review.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_medium_change_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/assay_condition_fixture.dart';

void main() {
  MediumChangePlan plan(
          {MediumChangeMode mode = MediumChangeMode.add,
          double initialVolume = 100,
          double initialConcentration = 10,
          double initialPercent = .1,
          double removed = 0,
          double volume = 20,
          double concentration = 0,
          double percent = 0,
          String unit = 'µM',
          String? vehicle = 'DMSO'}) =>
      MediumChangePlan(
          mode: mode,
          unit: unit,
          vehicle: vehicle,
          initialVolume: initialVolume,
          initialConcentration: initialConcentration,
          initialVehiclePercent: initialPercent,
          removedVolume: removed,
          incomingVolume: volume,
          incomingConcentration: concentration,
          incomingVehiclePercent: percent);

  test('addition includes drug and vehicle already present and adds volumes',
      () {
    final p = plan(
        initialConcentration: 5,
        initialPercent: .2,
        concentration: 50,
        percent: 2);
    expect(p.finalVolume, 120);
    expect(p.retainedVolume, 100);
    expect(p.finalConcentration, closeTo(12.5, 1e-12));
    expect(p.finalVehiclePercent, closeTo(.5, 1e-12));
    final emptyDrug = plan(
        initialConcentration: 0,
        initialPercent: 0,
        volume: 10,
        concentration: 100,
        percent: 1);
    expect(emptyDrug.finalVolume, 110);
    expect(emptyDrug.finalConcentration, closeTo(100 / 11, 1e-12));
    expect(emptyDrug.finalVehiclePercent, closeTo(1 / 11, 1e-12));
    for (final value in [.1, .3, 2.123456789]) {
      final same = plan(
          initialVolume: 123,
          volume: 17,
          initialConcentration: value,
          concentration: value,
          initialPercent: value,
          percent: value);
      expect(same.finalConcentration, value);
      expect(same.finalVehiclePercent, value);
    }
  });

  test(
      'partial replacement removes dissolved mass before adding the new solution',
      () {
    final p = plan(mode: MediumChangeMode.replacePart, removed: 40);
    expect(p.retainedVolume, 60);
    expect(p.finalVolume, 80);
    expect(p.finalConcentration, 7.5);
    expect(p.finalVehiclePercent, closeTo(.075, 1e-12));
    expect(p.description, contains('제거 40.0 µL'));
    expect(p.description, contains('잔류 60.0 µL'));
  });

  test(
      'full replacement ignores old solution and preserves exact incoming conditions',
      () {
    final p = plan(
        mode: MediumChangeMode.replaceAll,
        initialVolume: double.nan,
        initialConcentration: double.nan,
        initialPercent: double.nan,
        volume: 75,
        concentration: 1.23456789,
        percent: .03);
    expect(p.retainedVolume, 0);
    expect(p.finalVolume, 75);
    expect(p.finalConcentration, 1.23456789);
    expect(p.finalVehiclePercent, .03);
    expect(p.description, contains('기존 배지 전량 제거'));
    expect(p.description, isNot(contains('NaN')));
    expect(
        plan(initialVolume: 0, initialPercent: 0, vehicle: null)
            .finalVehiclePercent,
        0);
  });

  test(
      'invalid geometry, nonfinite inputs, unit omissions and unsupported unnamed vehicle are rejected',
      () {
    final invalid = <MediumChangePlan Function()>[
      () => plan(volume: 0),
      () => plan(volume: -1),
      () => plan(volume: double.infinity),
      () => plan(concentration: -1),
      () => plan(concentration: double.nan),
      () => plan(initialVolume: -1),
      () => plan(initialConcentration: double.infinity),
      () => plan(percent: 101),
      () => plan(percent: -1),
      () => plan(initialPercent: double.nan),
      () => plan(initialPercent: 101),
      () => plan(unit: ''),
      () => plan(unit: ' µM'),
      () => plan(vehicle: null),
      () => plan(vehicle: ''),
      () => plan(initialPercent: 0, percent: 1, vehicle: null),
      () => plan(removed: 1),
      () => plan(mode: MediumChangeMode.replacePart, removed: 0),
      () => plan(mode: MediumChangeMode.replacePart, removed: 100),
      () => plan(mode: MediumChangeMode.replacePart, removed: 101),
      () => plan(initialVolume: 1.7e308, volume: 1.7e308),
    ];
    for (final build in invalid) {
      expect(build, throwsFormatException);
    }
    expect(plan(volume: .5).hasLowDispenseVolume, isTrue);
    expect(
        plan(mode: MediumChangeMode.replacePart, removed: .5)
            .hasLowDispenseVolume,
        isTrue);
    expect(plan(volume: 1).hasLowDispenseVolume, isFalse);
    expect(plan(initialPercent: 100, percent: 100).finalVehiclePercent,
        closeTo(100, 1e-12));
    expect(
        plan(initialConcentration: 1e300, concentration: 1e300)
            .finalConcentration,
        closeTo(1e300, 1e285));
  });

  test(
      'applying touches only selected final conditions, retains results and records measured changes',
      () {
    const service = PlateMediumChangeService();
    final base = assayPlate();
    final source = base.copyWith(wells: [
      base.wells.first.copyWith(
          volumeValue: 100, volumeUnit: 'µL', resultValue: 0, excluded: true),
      ...base.wells.skip(1)
    ]);
    final updated = service.apply(
        plate: source,
        positions: {source.wells.first.position},
        plan: plan(mode: MediumChangeMode.replacePart, removed: 40),
        finalMedium: 'DMEM + 10% FBS');
    final w = updated.wells.first;
    expect(w.concentrationValue, 7.5);
    expect(w.volumeValue, 80);
    expect(w.assayCondition!.vehiclePercent, closeTo(.075, 1e-12));
    expect(w.resultValue, 0);
    expect(w.excluded, true);
    expect(w.cellCondition, source.wells.first.cellCondition);
    expect(w.groupId, source.wells.first.groupId);
    expect(w.role, source.wells.first.role);
    expect(w.note, source.wells.first.note);
    expect(updated.wells.skip(1).map((w) => w.toJson()),
        source.wells.skip(1).map((w) => w.toJson()));
    final review = MeasuredConditionReview.compare(source, updated);
    expect(review.changes.single.fields.map((f) => f.label),
        containsAll(['부피', '배지·용매 조건']));
    expect(Plate.fromJson(jsonDecode(jsonEncode(updated.toJson()))).toJson(),
        updated.toJson());
    expect(
        () => service.apply(
            plate: source, positions: {}, plan: plan(), finalMedium: 'DMEM'),
        throwsFormatException);
  });

  test(
      'recorded source values and vehicle names cannot be silently replaced by calculator inputs',
      () {
    const service = PlateMediumChangeService();
    final w =
        assayPlate().wells.first.copyWith(volumeValue: 100, volumeUnit: 'µL');
    for (final different in [
      w.copyWith(volumeValue: 99),
      w.copyWith(volumeUnit: 'mL'),
      w.copyWith(concentrationValue: 9),
      w.copyWith(concentrationUnit: 'mM'),
      w.copyWith(assayCondition: dmsoHigh),
      w.copyWith(assayCondition: ethanol)
    ]) {
      expect(() => service.validateSource([w, different], plan()),
          throwsFormatException);
    }
    service.validateSource([
      w.copyWith(
          volumeValue: null, concentrationValue: null, assayCondition: null)
    ], plan());
    service.validateSource(
        [w.copyWith(volumeUnit: 'mL', assayCondition: ethanol)],
        plan(mode: MediumChangeMode.replaceAll));
    final blank = w.copyWith(
        assayCondition:
            const AssayCondition(medium: 'DMEM', vehiclePercent: 0));
    service.validateSource(
        [blank], plan(initialPercent: 0, vehicle: 'ethanol', percent: 1));
  });
}

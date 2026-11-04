import 'package:easycheck/shared/models/cell_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinary, exponent and pasted notation resolve to the same number', () {
    for (final input in [
      ('10000', ''),
      ('1', '4'),
      ('1e4', ''),
      ('1 × 10^4', '')
    ]) {
      expect(CellNumber.parse(input.$1, input.$2), 10000);
    }
    expect(CellNumber.parse('1.2', '-3'), .0012);
    expect(CellNumber.parse('', ''), isNull);
    expect(CellNumber.parse('0', '4'), 0);
    expect(CellNumber.format(10000), '10,000');
    expect(CellNumber.format(.0012), '0.0012');
  });
  test('rejects incomplete, negative, nonfinite, overflow and underflow inputs',
      () {
    for (final input in [
      ('', '4'),
      ('-1', ''),
      ('NaN', ''),
      ('Infinity', ''),
      ('1', '1.5'),
      ('1', '999'),
      ('1', '-999')
    ]) {
      expect(() => CellNumber.parse(input.$1, input.$2), throwsFormatException);
    }
  });
  test(
      'single conversion preserves existing precision and decimal exponent scaling',
      () {
    for (final value in [0.12345678912345678, 0.0, 1e-300, 1e300, 5e-324]) {
      expect(CellNumber.parse(value.toString(), ''), value);
    }
    expect(CellNumber.parse('1.2345678912345678', '4'),
        double.parse('1.2345678912345678e4'));
    expect(CellNumber.parse('1e-300', '400'), 1e100);
    expect(CellNumber.parse('1e300', '-400'), 1e-100);
  });
}

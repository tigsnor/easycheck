/// Cell-count input without intermediate floating-point multiplication.
abstract final class CellNumber {
  static final _decimal =
      RegExp(r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+))(?:[eE]([+-]?\d+))?$');
  static final _writtenPower = RegExp(
      r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*[×xX*]\s*10\s*\^\s*([+-]?\d+)$');

  /// A blank exponent means an ordinary number; both blank mean unspecified.
  static double? parse(String coefficient, String exponent) {
    var text = coefficient.trim();
    final powerText = exponent.trim();
    if (text.isEmpty && powerText.isEmpty) return null;
    final written = _writtenPower.firstMatch(text);
    if (written != null) text = '${written[1]}e${written[2]}';
    final match = _decimal.firstMatch(text);
    final extra = powerText.isEmpty ? BigInt.zero : BigInt.tryParse(powerText);
    if (match == null ||
        extra == null ||
        (powerText.isNotEmpty && !RegExp(r'^[+-]?\d+$').hasMatch(powerText))) {
      throw const FormatException('0 이상의 숫자와 정수 지수를 입력해주세요.');
    }
    final mantissa = match[1]!;
    final power = BigInt.parse(match[2] ?? '0') + extra;
    final result = double.tryParse('${mantissa}e$power');
    final nonzero = RegExp(r'[1-9]').hasMatch(mantissa);
    if (result == null ||
        !result.isFinite ||
        result < 0 ||
        (result == 0 && nonzero)) {
      throw const FormatException('세포 수가 계산 가능한 범위를 벗어났습니다.');
    }
    return result;
  }

  /// Show all digits in the round-trip representation; never round for input.
  static String format(double value) {
    final raw = value.toString();
    if (raw.contains('e') || raw.contains('E')) return raw;
    final parts = raw.split('.');
    final integer = parts.first
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    final fraction = parts.length > 1 && parts[1] != '0' ? '.${parts[1]}' : '';
    return '$integer$fraction';
  }
}

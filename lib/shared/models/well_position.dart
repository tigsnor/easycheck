class WellPosition {
  const WellPosition({required this.rowIndex, required this.columnIndex})
    : assert(rowIndex >= 0),
      assert(columnIndex >= 0);

  factory WellPosition.fromLabel(String label) {
    final trimmed = label.trim().toUpperCase();
    if (trimmed.length < 2) {
      throw FormatException('Invalid well label: $label');
    }

    final rowCode = trimmed.codeUnitAt(0);
    final rowIndex = rowCode - 'A'.codeUnitAt(0);
    final column = int.tryParse(trimmed.substring(1));

    if (rowIndex < 0 || rowIndex > 25 || column == null || column < 1) {
      throw FormatException('Invalid well label: $label');
    }

    return WellPosition(rowIndex: rowIndex, columnIndex: column - 1);
  }

  final int rowIndex;
  final int columnIndex;

  String get rowLabel => String.fromCharCode('A'.codeUnitAt(0) + rowIndex);
  int get columnNumber => columnIndex + 1;
  String get label => '$rowLabel$columnNumber';

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WellPosition &&
            other.rowIndex == rowIndex &&
            other.columnIndex == columnIndex;
  }

  @override
  int get hashCode => Object.hash(rowIndex, columnIndex);

  @override
  String toString() => label;
}

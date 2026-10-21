List<Map<String, Object?>> jsonObjectList(
  Object? value,
  String field, {
  bool required = false,
}) {
  if (value == null && !required) return [];
  if (value is! List) {
    throw FormatException('$field must be an array.');
  }
  return value.map((item) {
    if (item is! Map<String, Object?>) {
      throw FormatException('$field must contain only objects.');
    }
    return item;
  }).toList();
}

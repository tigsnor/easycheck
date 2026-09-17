enum WellRole {
  empty,
  treatment,
  sample,
  blank,
  negativeControl,
  positiveControl,
  vehicleControl,
  untreatedControl,
  standard,
}

extension WellRoleJson on WellRole {
  static WellRole fromName(String? name) {
    return WellRole.values.firstWhere(
      (role) => role.name == name,
      orElse: () => WellRole.empty,
    );
  }
}

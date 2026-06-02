import '../domain/plate.dart';

abstract class PlateRepository {
  Future<Plate?> loadPlate(String experimentId);
  Future<void> savePlate(Plate plate);
}

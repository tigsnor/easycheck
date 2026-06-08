import '../domain/plate.dart';

abstract class PlateRepository {
  Future<void> deletePlate(String experimentId);
  Future<Plate?> loadPlate(String experimentId);
  Future<void> savePlate(Plate plate);
}

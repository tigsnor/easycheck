import '../domain/plate_template.dart';

abstract class PlateTemplateRepository {
  Future<List<PlateTemplate>> loadTemplates();
  Future<void> saveTemplate(PlateTemplate template);
  Future<void> deleteTemplate(String id);
}

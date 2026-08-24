class DrugInfoModel {
  final String key;
  final String active1;
  final String active2;

  final List<String> uses;
  final String adultDose;
  final String pediatricDose;
  final List<String> contraindications;
  final String pregnancy;
  final String lactation;
  final List<String> sideEffects;
  final List<String> interactions;
  final String notes;

  DrugInfoModel({
    required this.key,
    required this.active1,
    required this.active2,
    this.uses = const [],
    this.adultDose = "",
    this.pediatricDose = "",
    this.contraindications = const [],
    this.pregnancy = "",
    this.lactation = "",
    this.sideEffects = const [],
    this.interactions = const [],
    this.notes = "",
  });

  Map<String, dynamic> toMap() {
    return {
      "key": key,
      "active1": active1,
      "active2": active2,
      "uses": uses,
      "adultDose": adultDose,
      "pediatricDose": pediatricDose,
      "contraindications": contraindications,
      "pregnancy": pregnancy,
      "lactation": lactation,
      "sideEffects": sideEffects,
      "interactions": interactions,
      "notes": notes,
    };
  }
}
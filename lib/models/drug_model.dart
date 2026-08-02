class DrugModel {
  final String id;
  final String registration;
  final String tradeName;
  final String packSize;
  final String active1;
  final String active2;
  final String manufacturer;
  final String agent;
  final double price;
  final List<String> search;

  DrugModel({
    required this.id,
    required this.registration,
    required this.tradeName,
    required this.packSize,
    required this.active1,
    required this.active2,
    required this.manufacturer,
    required this.agent,
    required this.price,
    required this.search,
  });

  factory DrugModel.fromMap(String id, Map<String, dynamic> map) {
    return DrugModel(
      id: id,

      registration: map["registration"]?.toString() ?? "",

      tradeName: map["tradeName"]?.toString() ?? "",

      packSize: map["packSize"]?.toString() ?? "",

      active1: map["active1"]?.toString() ?? "",

      active2: map["active2"]?.toString() ?? "",

      manufacturer: map["manufacturer"]?.toString() ?? "",

      agent: map["agent"]?.toString() ?? "",

      price: _parsePrice(map["price"]),

      search: List<String>.from(map["search"] ?? []),
    );
  }

  factory DrugModel.fromLocal(Map<String, dynamic> map) {
    return DrugModel(
      id: map["id"]?.toString() ?? "",

      registration: map["registration"]?.toString() ?? "",

      tradeName: map["tradeName"]?.toString() ?? "",

      packSize: map["packSize"]?.toString() ?? "",

      active1: map["active1"]?.toString() ?? "",

      active2: map["active2"]?.toString() ?? "",

      manufacturer: map["manufacturer"]?.toString() ?? "",

      agent: map["agent"]?.toString() ?? "",

      price: _parsePrice(map["price"]),

      search: List<String>.from(map["search"] ?? []),
    );
  }

  static double _parsePrice(dynamic value) {
    if (value == null) {
      return 0.0;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString().replaceAll(",", ".")) ?? 0.0;
  }

  Map<String, dynamic> toMap() {
    return {
      "id": id,

      "registration": registration,

      "tradeName": tradeName,

      "packSize": packSize,

      "active1": active1,

      "active2": active2,

      "manufacturer": manufacturer,

      "agent": agent,

      "price": price,

      "search": search,
    };
  }

  // ============================
  // Drug Strength
  // ============================

  String get strength {
    final text = "$tradeName $packSize".toLowerCase();

    final match = RegExp(r'\d+\s?(mg|mcg|g|ml)').firstMatch(text);

    return match?.group(0)?.replaceAll(" ", "").toLowerCase() ?? "";
  }

  // ============================
  // Search Helpers
  // ============================

  String get tradeNameLower => tradeName.toLowerCase().trim();

  String get active1Lower => active1.toLowerCase().trim();

  String get active2Lower => active2.toLowerCase().trim();

  String get registrationLower => registration.toLowerCase().trim();

  bool matches(String query) {
    query = query.toLowerCase().trim();

    return search.any((item) => item.toLowerCase().contains(query));
  }

  int searchScore(String query) {
    query = query.toLowerCase().trim();

    if (tradeNameLower.startsWith(query)) {
      return 100;
    }

    if (tradeNameLower.contains(query)) {
      return 90;
    }

    if (active1Lower.startsWith(query)) {
      return 80;
    }

    if (active2Lower.startsWith(query)) {
      return 70;
    }

    if (registrationLower.startsWith(query)) {
      return 60;
    }

    return 0;
  }

  DrugModel copyWith({
    String? id,

    String? registration,

    String? tradeName,

    String? packSize,

    String? active1,

    String? active2,

    String? manufacturer,

    String? agent,

    double? price,

    List<String>? search,
  }) {
    return DrugModel(
      id: id ?? this.id,

      registration: registration ?? this.registration,

      tradeName: tradeName ?? this.tradeName,

      packSize: packSize ?? this.packSize,

      active1: active1 ?? this.active1,

      active2: active2 ?? this.active2,

      manufacturer: manufacturer ?? this.manufacturer,

      agent: agent ?? this.agent,

      price: price ?? this.price,

      search: search ?? this.search,
    );
  }

  @override
  String toString() {
    return """
DrugModel(
id: $id,
name: $tradeName,
strength: $strength,
pack: $packSize,
price: $price
)
""";
  }
}

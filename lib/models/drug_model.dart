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
      "registration": registration,
      "tradeName": tradeName,
      "packSize": packSize,
      "active1": active1,
      "active2": active2,
      "manufacturer": manufacturer,
      "agent": agent,
      "price": price,
    };
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
    );
  }

  @override
  String toString() {
    return """
DrugModel(
id: $id,
name: $tradeName,
pack: $packSize,
price: $price
)
""";
  }
}

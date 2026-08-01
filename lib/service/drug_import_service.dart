import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';

class DrugImportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _cell(List<Data?> row, int index) {
    if (index >= row.length) return "";

    final value = row[index]?.value;

    if (value == null) return "";

    return value.toString().trim();
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9%]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _buildSearch({
    required String registration,
    required String tradeName,
    required String packSize,
    required String active1,
    required String active2,
    required String manufacturer,
    required String agent,
  }) {
    final Set<String> result = {};

    void addWords(String text) {
      final value = _normalize(text);

      if (value.isEmpty) return;

      result.add(value);

      for (final word in value.split(" ")) {
        if (word.isNotEmpty) {
          result.add(word);
        }
      }
    }

    addWords(registration);
    addWords(tradeName);
    addWords(packSize);
    addWords(active1);
    addWords(active2);
    addWords(manufacturer);
    addWords(agent);

    return result.toList();
  }

  Future<int> importExcel(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) {
      return 0;
    }

    final sheet = excel.tables.values.first;

    int count = 0;

    int batchCount = 0;

    WriteBatch batch = _db.batch();

    for (int i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];

      final registration = _cell(row, 0);

      // تجاهل الصفوف بدون Registration
      if (registration.isEmpty) {
        continue;
      }

      final tradeName = _cell(row, 1);

      final packSize = _cell(row, 2);

      final active1 = _cell(row, 3);

      final active2 = _cell(row, 4);

      final agent = _cell(row, 5);

      final manufacturer = _cell(row, 6);

      final priceText = _cell(
        row,
        7,
      ).replaceAll(",", "").replaceAll("ر.ع.", "").trim();

      final price = double.tryParse(priceText) ?? 0.0;

      final doc = _db.collection("drugs").doc(registration);

      batch.set(doc, {
        "registration": registration,

        "registrationLower": _normalize(registration),

        "tradeName": tradeName,

        "tradeNameLower": _normalize(tradeName),

        "packSize": packSize,

        "active1": active1,

        "active1Lower": _normalize(active1),

        "active2": active2,

        "active2Lower": _normalize(active2),

        "agent": agent,

        "agentLower": _normalize(agent),

        "manufacturer": manufacturer,

        "manufacturerLower": _normalize(manufacturer),

        "price": price,

        "search": _buildSearch(
          registration: registration,
          tradeName: tradeName,
          packSize: packSize,
          active1: active1,
          active2: active2,
          manufacturer: manufacturer,
          agent: agent,
        ),

        "updatedAt": FieldValue.serverTimestamp(),
      });

      count++;

      batchCount++;

      // Firestore limit = 500
      if (batchCount == 400) {
        await batch.commit();

        print("Uploaded $count drugs");

        batch = _db.batch();

        batchCount = 0;
      }
    }

    if (batchCount > 0) {
      await batch.commit();
    }

    print("Finished upload: $count drugs");

    return count;
  }
}

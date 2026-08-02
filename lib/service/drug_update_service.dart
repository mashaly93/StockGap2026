import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';

class DrugUpdateService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _cell(List<Data?> row, int index) {
    if (index >= row.length) return "";

    final value = row[index]?.value;

    if (value == null) return "";

    return value.toString().trim();
  }

  Future<int> updateExcel(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) {
      return 0;
    }

    final sheet = excel.tables.values.first;

    int count = 0;

    WriteBatch batch = _db.batch();

    int batchCount = 0;

    for (int i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];

      // A
      final registration = _cell(row, 0);

      if (registration.isEmpty) {
        continue;
      }

      // C
      final active2 = _cell(row, 2);

      // D
      final agent = _cell(row, 3);

      // E
      final manufacturer = _cell(row, 4);

      // F
      final priceText = _cell(
        row,
        5,
      ).replaceAll(",", "").replaceAll("ر.ع.", "").trim();

      final price = double.tryParse(priceText) ?? 0.0;

      final doc = _db.collection("drugs").doc(registration);

      batch.update(doc, {
        "active2": active2,

        "active2Lower": active2.toLowerCase(),

        "agent": agent,

        "agentLower": agent.toLowerCase(),

        "manufacturer": manufacturer,

        "manufacturerLower": manufacturer.toLowerCase(),

        "price": price,

        "updatedAt": FieldValue.serverTimestamp(),
      });

      count++;

      batchCount++;

      if (batchCount == 400) {
        await batch.commit();

        batch = _db.batch();

        batchCount = 0;
      }
    }

    if (batchCount > 0) {
      await batch.commit();
    }

    print("Updated $count drugs");

    return count;
  }
}

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';

class DrugImportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<int> importExcel(Uint8List bytes) async {
    int count = 0;

    final excel = Excel.decodeBytes(bytes);

    final sheet = excel.tables[excel.tables.keys.first];

    if (sheet == null) {
      return 0;
    }

    // Skip first row (headers)
    for (int i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];

      final registration = row[0]?.value.toString().trim() ?? "";

      if (registration.isEmpty) {
        continue;
      }

      final tradeName = row[1]?.value.toString().trim() ?? "";

      final packSize = row[2]?.value.toString().trim() ?? "";

      final active1 = row[3]?.value.toString().trim() ?? "";

      final active2 = row[4]?.value.toString().trim() ?? "";

      final agent = row[5]?.value.toString().trim() ?? "";

      final manufacturer = row[6]?.value.toString().trim() ?? "";

      final price = double.tryParse(row[7]?.value.toString() ?? "0") ?? 0;

      await _db.collection("drugs").doc(registration).set({
        "registration": registration,

        "tradeName": tradeName,

        "tradeNameLower": tradeName.toLowerCase(),

        "packSize": packSize,

        "active1": active1,

        "active1Lower": active1.toLowerCase(),

        "active2": active2,

        "active2Lower": active2.toLowerCase(),

        "actives": [active1.toLowerCase(), active2.toLowerCase()],

        "agent": agent,

        "manufacturer": manufacturer,

        "price": price,

        "search": [
          tradeName.toLowerCase(),

          active1.toLowerCase(),

          active2.toLowerCase(),

          packSize.toLowerCase(),
        ],

        "updatedAt": FieldValue.serverTimestamp(),
      });

      count++;

      print("Uploaded: $registration");
    }

    return count;
  }
}

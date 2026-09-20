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

  // ============================================================
  // OLD FUNCTION
  // ============================================================

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

  // ============================================================
  // ADD NEW DRUGS FROM EXCEL
  //
  // Excel:
  //
  // A = Regn. No.
  // B = Trade Name
  // C = Pack Size
  // D = Active 1
  // E = Active 2
  // F = Local Agent
  // G = Mfr Name
  // H = Appr. RP
  //
  // Firestore:
  //
  // drugs/{Registration No.}
  //
  // Existing drugs are NOT modified.
  // ============================================================

  Future<int> addNewDrugsFromExcel(Uint8List bytes) async {
    print("");
    print("==========================================");
    print("🚀 ADD NEW DRUGS FROM EXCEL");
    print("==========================================");

    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) {
      print("❌ NO EXCEL SHEETS FOUND");
      return 0;
    }

    final sheet = excel.tables.values.first;

    print("📄 Using first sheet");
    print("📊 Total rows: ${sheet.rows.length}");

    int added = 0;
    int skipped = 0;
    int invalid = 0;

    WriteBatch batch = _db.batch();

    int batchCount = 0;

    // ============================================================
    // FIND HEADER
    // ============================================================

    int headerRow = -1;

    for (int i = 0; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];

      for (int j = 0; j < row.length; j++) {
        final value = row[j]?.value?.toString().trim().toLowerCase() ?? "";

        if (value.contains("registration") || value.contains("regn")) {
          headerRow = i;
          break;
        }
      }

      if (headerRow != -1) {
        break;
      }
    }

    // لو الـ Header مش موجود، نفترض أول صف Header
    if (headerRow == -1) {
      print(
        "⚠️ Registration header not found."
        " Assuming row 0 is header.",
      );

      headerRow = 0;
    }

    print("📌 Header row: $headerRow");

    // ============================================================
    // READ DATA
    // ============================================================

    for (int i = headerRow + 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];

      if (row.isEmpty) {
        continue;
      }

      // ==========================================================
      // COLUMN A
      // Registration
      // ==========================================================

      final registration = _cell(row, 0);

      if (registration.isEmpty) {
        continue;
      }

      // ==========================================================
      // COLUMN B
      // Trade Name
      // ==========================================================

      final tradeName = _cell(row, 1);

      // ==========================================================
      // COLUMN C
      // Pack Size
      // ==========================================================

      final packSize = _cell(row, 2);

      // ==========================================================
      // COLUMN D
      // Active 1
      // ==========================================================

      final active1 = _cell(row, 3);

      // ==========================================================
      // COLUMN E
      // Active 2
      // ==========================================================

      final active2 = _cell(row, 4);

      // ==========================================================
      // COLUMN F
      // Local Agent
      // ==========================================================

      final agent = _cell(row, 5);

      // ==========================================================
      // COLUMN G
      // Manufacturer
      // ==========================================================

      final manufacturer = _cell(row, 6);

      // ==========================================================
      // COLUMN H
      // Appr. RP
      // ==========================================================

      String priceText = _cell(row, 7);

      print("");
      print("ROW $i");
      print("Registration: [$registration]");
      print("Trade Name: [$tradeName]");
      print("Pack Size: [$packSize]");
      print("Active 1: [$active1]");
      print("Active 2: [$active2]");
      print("Agent: [$agent]");
      print("Manufacturer: [$manufacturer]");
      print("Price: [$priceText]");

      // ==========================================================
      // VALIDATE
      // ==========================================================

      if (tradeName.isEmpty) {
        print("⚠️ SKIPPED: $registration - Trade Name is empty");

        invalid++;

        continue;
      }

      // ==========================================================
      // PRICE
      // ==========================================================

      double price = 0.0;

      if (priceText.isNotEmpty) {
        priceText = priceText
            .replaceAll(",", "")
            .replaceAll("ر.ع.", "")
            .replaceAll("OMR", "")
            .trim();

        price = double.tryParse(priceText) ?? 0.0;
      }

      // ==========================================================
      // FIRESTORE DOCUMENT
      //
      // Registration No. = Document ID
      // ==========================================================

      final doc = _db.collection("drugs").doc(registration);

      // ==========================================================
      // CHECK IF ALREADY EXISTS
      // ==========================================================

      final existing = await doc.get();

      if (existing.exists) {
        skipped++;

        print(
          "⏭️ SKIPPED: "
          "drugs/$registration already exists",
        );

        continue;
      }

      // ==========================================================
      // SEARCH ARRAY
      // ==========================================================

      final search =
          <String>[
                registration,
                tradeName,
                active1,
                active2,
                manufacturer,
                agent,
              ]
              .where((value) => value.trim().isNotEmpty)
              .map((value) => value.trim().toLowerCase())
              .toSet()
              .toList();

      // ==========================================================
      // FIRESTORE DATA
      // ==========================================================

      final data = {
        "registration": registration,
        "tradeName": tradeName,
        "packSize": packSize,
        "active1": active1,
        "active2": active2,
        "manufacturer": manufacturer,
        "agent": agent,
        "price": price,
        "search": search,

        // Lowercase fields
        "registrationLower": registration.toLowerCase(),

        "tradeNameLower": tradeName.toLowerCase(),

        "active1Lower": active1.toLowerCase(),

        "active2Lower": active2.toLowerCase(),

        "agentLower": agent.toLowerCase(),

        "manufacturerLower": manufacturer.toLowerCase(),

        "createdAt": FieldValue.serverTimestamp(),

        "updatedAt": FieldValue.serverTimestamp(),
      };

      // ==========================================================
      // ADD NEW DRUG
      // ==========================================================

      batch.set(doc, data);

      added++;
      batchCount++;

      print(
        "✅ ADD QUEUED: "
        "drugs/$registration → $tradeName",
      );

      // ==========================================================
      // FIRESTORE BATCH LIMIT
      // ==========================================================

      if (batchCount == 400) {
        await batch.commit();

        print("🔥 Committed batch of 400 new drugs");

        batch = _db.batch();

        batchCount = 0;
      }
    }

    // ============================================================
    // COMMIT REMAINING
    // ============================================================

    if (batchCount > 0) {
      await batch.commit();

      print(
        "🔥 Committed remaining "
        "$batchCount new drugs",
      );
    }

    // ============================================================
    // FINAL RESULT
    // ============================================================

    print("");
    print("==========================================");
    print("✅ NEW DRUGS ADDED: $added");
    print("⏭️ ALREADY EXISTED: $skipped");
    print("⚠️ INVALID ROWS: $invalid");
    print("==========================================");
    print("");

    return added;
  }

  // ============================================================
  // UPDATE PRICES ONLY
  //
  // Excel:
  //
  // Column A = Registration No.
  // Column B = New Price
  //
  // Firestore:
  //
  // drugs/{Registration No.}
  //
  // Only "price" will be changed.
  // ============================================================

  Future<int> updatePricesFromExcel(Uint8List bytes) async {
    print("");
    print("==========================================");
    print("🔥 PRICE UPDATE FUNCTION STARTED");
    print("==========================================");

    final excel = Excel.decodeBytes(bytes);

    print("📊 Excel decoded");

    if (excel.tables.isEmpty) {
      print("❌ NO EXCEL SHEETS FOUND");
      return 0;
    }

    print("📄 Sheets found: ${excel.tables.keys.toList()}");

    int count = 0;

    WriteBatch batch = _db.batch();

    int batchCount = 0;

    // ============================================================
    // READ FIRST SHEET
    // ============================================================

    final sheet = excel.tables.values.first;

    print("📄 Using first sheet");
    print("📊 Total rows: ${sheet.rows.length}");

    // ============================================================
    // DEBUG - PRINT FIRST 10 ROWS
    // ============================================================

    print("");
    print("========== EXCEL DATA DEBUG ==========");

    for (int i = 0; i < sheet.rows.length && i < 10; i++) {
      final row = sheet.rows[i];

      print("ROW $i:");

      for (int j = 0; j < row.length; j++) {
        final value = row[j]?.value;

        print(
          "   COL $j = [$value] "
          "TYPE = ${value.runtimeType}",
        );
      }
    }

    print("======================================");
    print("");

    // ============================================================
    // FIND HEADER
    // ============================================================

    int headerRow = -1;
    int registrationColumn = -1;
    int priceColumn = -1;

    for (int i = 0; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];

      for (int j = 0; j < row.length; j++) {
        final value = row[j]?.value?.toString().trim().toLowerCase() ?? "";

        if (value.contains("registration") || value.contains("regn")) {
          headerRow = i;
          registrationColumn = j;

          // السعر في العمود التالي
          if (j + 1 < row.length) {
            priceColumn = j + 1;
          }

          break;
        }
      }

      if (headerRow != -1) {
        break;
      }
    }

    print("========== HEADER DEBUG ==========");

    print("Header row: $headerRow");
    print("Registration column: $registrationColumn");
    print("Price column: $priceColumn");

    print("==================================");

    // ============================================================
    // IF HEADER NOT FOUND
    // ============================================================

    if (headerRow == -1) {
      print("");
      print("❌ Registration No. header was NOT found.");
      print("❌ No prices were updated.");
      print("");

      return 0;
    }

    // ============================================================
    // READ DATA
    // ============================================================

    for (int i = headerRow + 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];

      if (row.isEmpty) {
        continue;
      }

      // ----------------------------------------------------------
      // Registration
      // ----------------------------------------------------------

      final registration = _cell(row, registrationColumn);

      // ----------------------------------------------------------
      // Price
      // ----------------------------------------------------------

      String priceText = _cell(row, priceColumn);

      print(
        "ROW $i → "
        "Registration=[$registration] "
        "Price=[$priceText]",
      );

      // ----------------------------------------------------------
      // Skip empty registration
      // ----------------------------------------------------------

      if (registration.isEmpty) {
        continue;
      }

      // ----------------------------------------------------------
      // Skip empty price
      // ----------------------------------------------------------

      if (priceText.isEmpty) {
        print("⚠️ Empty price for $registration");

        continue;
      }

      // ----------------------------------------------------------
      // Clean price
      // ----------------------------------------------------------

      priceText = priceText
          .replaceAll(",", "")
          .replaceAll("ر.ع.", "")
          .replaceAll("OMR", "")
          .trim();

      // ----------------------------------------------------------
      // Convert price
      // ----------------------------------------------------------

      final price = double.tryParse(priceText);

      if (price == null) {
        print(
          "❌ Invalid price [$priceText] "
          "for [$registration]",
        );

        continue;
      }

      // ----------------------------------------------------------
      // Firestore document
      //
      // Registration No. = Document ID
      // ----------------------------------------------------------

      final doc = _db.collection("drugs").doc(registration);

      // ----------------------------------------------------------
      // UPDATE PRICE ONLY
      // ----------------------------------------------------------

      batch.update(doc, {
        "price": price,
        "updatedAt": FieldValue.serverTimestamp(),
      });

      print(
        "✅ UPDATE QUEUED: "
        "drugs/$registration → $price",
      );

      count++;

      batchCount++;

      // ----------------------------------------------------------
      // Firestore batch limit
      // ----------------------------------------------------------

      if (batchCount == 400) {
        await batch.commit();

        print("🔥 Committed batch of 400 price updates");

        batch = _db.batch();

        batchCount = 0;
      }
    }

    // ============================================================
    // COMMIT REMAINING
    // ============================================================

    if (batchCount > 0) {
      await batch.commit();

      print(
        "🔥 Committed remaining "
        "$batchCount price updates",
      );
    }

    // ============================================================
    // FINAL RESULT
    // ============================================================

    print("");
    print("==========================================");
    print("🔥 UPDATED PRICES: $count");
    print("==========================================");
    print("");

    return count;
  }
}

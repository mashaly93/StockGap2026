import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'Homescreen.dart';

class StoreInventoryScreen extends StatefulWidget {
  final String storeCode;
  final Timestamp? expireDate;

  const StoreInventoryScreen({
    super.key,
    required this.storeCode,
    this.expireDate,
  });

  @override
  State<StoreInventoryScreen> createState() => _StoreInventoryScreenState();
}

class _StoreInventoryScreenState extends State<StoreInventoryScreen> {
  // ============================================================
  // SETTINGS
  // ============================================================

  // Firestore يسمح حتى 500 عملية في WriteBatch.
  // نستخدم 400 كحد آمن.
  static const int batchSize = 400;

  // ============================================================
  // STATE
  // ============================================================

  bool uploading = false;

  String status = "";
  String currentStage = "";

  int processedItems = 0;
  int totalItems = 0;

  int currentBatch = 0;
  int totalBatches = 0;

  double progress = 0;

  // ============================================================
  // READ EXCEL
  // ============================================================

  Future<List<List<String>>> readExcel(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) {
      return [];
    }

    final sheet = excel.tables.values.first;

    final rows = <List<String>>[];

    for (final row in sheet.rows) {
      final convertedRow = <String>[];

      for (final cell in row) {
        if (cell == null) {
          convertedRow.add("");
          continue;
        }

        try {
          final value = cell.value;

          if (value == null) {
            convertedRow.add("");
          } else {
            convertedRow.add(value.toString().trim());
          }
        } catch (_) {
          convertedRow.add(cell.toString().trim());
        }
      }

      rows.add(convertedRow);
    }

    return rows;
  }

  // ============================================================
  // NORMALIZE HEADER
  // ============================================================

  String _normalizeHeader(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ============================================================
  // PARSE PRICE
  // ============================================================

  double? _parsePrice(String value) {
    var cleaned = value.trim();

    if (cleaned.isEmpty) {
      return null;
    }

    // إزالة العملات
    cleaned = cleaned
        .replaceAll("ر.ع.", "")
        .replaceAll("OMR", "")
        .replaceAll("omr", "")
        .replaceAll("RO", "")
        .replaceAll("ro", "")
        .replaceAll("رع", "")
        .replaceAll(" ", "")
        .trim();

    if (cleaned.isEmpty) {
      return null;
    }

    // تجاهل النسب
    if (cleaned.contains("%")) {
      return null;
    }

    // إزالة comma من 1,250.50
    cleaned = cleaned.replaceAll(",", "");

    final number = double.tryParse(cleaned);

    if (number == null) {
      return null;
    }

    if (number <= 0) {
      return null;
    }

    // حماية من الأرقام الغريبة
    if (number > 100000) {
      return null;
    }

    return number;
  }

  // ============================================================
  // FIND HEADER ROW
  // ============================================================

  int _findHeaderRow(List<List<String>> rows) {
    for (int i = 0; i < rows.length && i < 20; i++) {
      final row = rows[i];

      final normalizedValues = row
          .map(_normalizeHeader)
          .where((e) => e.isNotEmpty)
          .toList();

      final joined = normalizedValues.join(" ");

      bool hasItem = false;
      bool hasPrice = false;

      for (final value in normalizedValues) {
        if (_isItemHeader(value)) {
          hasItem = true;
        }

        if (_isPriceHeader(value)) {
          hasPrice = true;
        }
      }

      if (hasItem && hasPrice) {
        return i;
      }

      // بعض الملفات يكون فيها Header مثل:
      // Item Name + Warehouse Price
      if (joined.contains("item name") && joined.contains("price")) {
        return i;
      }
    }

    // لو لم نجد Header واضح، نستخدم أول صف.
    return 0;
  }

  // ============================================================
  // ITEM HEADER
  // ============================================================

  bool _isItemHeader(String value) {
    const exactNames = [
      "item",
      "item name",
      "product",
      "product name",
      "name",
      "description",
      "item description",
      "product description",
      "item description name",
    ];

    if (exactNames.contains(value)) {
      return true;
    }

    if (value.contains("item name")) {
      return true;
    }

    if (value.contains("product name")) {
      return true;
    }

    if (value.contains("item description")) {
      return true;
    }

    if (value.contains("product description")) {
      return true;
    }

    return false;
  }

  // ============================================================
  // PRICE HEADER
  // ============================================================

  bool _isPriceHeader(String value) {
    const exactNames = [
      "price",
      "warehouse price",
      "wh price",
      "purchase price",
      "unit price",
      "cost price",
      "sale price",
      "selling price",
    ];

    if (exactNames.contains(value)) {
      return true;
    }

    if (value.contains("warehouse price")) {
      return true;
    }

    if (value.contains("purchase price")) {
      return true;
    }

    if (value.contains("unit price")) {
      return true;
    }

    if (value.contains("cost price")) {
      return true;
    }

    if (value.contains("sale price")) {
      return true;
    }

    if (value.contains("selling price")) {
      return true;
    }

    return false;
  }

  // ============================================================
  // FIND ITEM COLUMN
  // ============================================================

  int _findItemColumn(List<String> header) {
    // أولًا: exact match
    for (int i = 0; i < header.length; i++) {
      final value = _normalizeHeader(header[i]);

      if (value == "item name") {
        return i;
      }
    }

    for (int i = 0; i < header.length; i++) {
      final value = _normalizeHeader(header[i]);

      if (value == "product name") {
        return i;
      }
    }

    for (int i = 0; i < header.length; i++) {
      final value = _normalizeHeader(header[i]);

      if (value == "item") {
        return i;
      }
    }

    for (int i = 0; i < header.length; i++) {
      final value = _normalizeHeader(header[i]);

      if (value == "product") {
        return i;
      }
    }

    for (int i = 0; i < header.length; i++) {
      final value = _normalizeHeader(header[i]);

      if (value == "description") {
        return i;
      }
    }

    // Partial match
    for (int i = 0; i < header.length; i++) {
      final value = _normalizeHeader(header[i]);

      if (value.contains("item name") ||
          value.contains("product name") ||
          value.contains("item description") ||
          value.contains("product description")) {
        return i;
      }
    }

    // fallback
    return 0;
  }

  // ============================================================
  // FIND PRICE COLUMN
  // ============================================================

  int _findPriceColumn(List<String> header) {
    // أعلى أولوية
    const priority = [
      "warehouse price",
      "wh price",
      "purchase price",
      "cost price",
      "unit price",
      "price",
      "sale price",
      "selling price",
    ];

    for (final wanted in priority) {
      for (int i = 0; i < header.length; i++) {
        final value = _normalizeHeader(header[i]);

        if (value == wanted) {
          return i;
        }
      }
    }

    // Partial match
    for (int i = 0; i < header.length; i++) {
      final value = _normalizeHeader(header[i]);

      if (value.contains("warehouse price") ||
          value.contains("purchase price") ||
          value.contains("unit price") ||
          value.contains("cost price") ||
          value.contains("sale price") ||
          value.contains("selling price")) {
        return i;
      }
    }

    // ==========================================================
    // FALLBACK
    // ==========================================================

    // لا يوجد Header واضح للسعر.
    // نبحث في الصفوف لاحقًا عن أول قيمة رقمية.
    return -1;
  }

  // ============================================================
  // EXTRACT ITEMS
  // ============================================================

  List<Map<String, dynamic>> extractItems(List<List<String>> rows) {
    if (rows.isEmpty) {
      return [];
    }

    final headerIndex = _findHeaderRow(rows);

    if (headerIndex >= rows.length) {
      return [];
    }

    final header = rows[headerIndex];

    debugPrint("=================================");
    debugPrint("EXCEL HEADER ROW: $headerIndex");
    debugPrint("HEADER: $header");
    debugPrint("=================================");

    final itemColumn = _findItemColumn(header);
    final priceColumn = _findPriceColumn(header);

    debugPrint("ITEM COLUMN: $itemColumn");
    debugPrint("PRICE COLUMN: $priceColumn");

    final items = <Map<String, dynamic>>[];

    int skipped = 0;

    for (int i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];

      if (row.isEmpty) {
        skipped++;
        continue;
      }

      // ======================================================
      // ITEM
      // ======================================================

      String itemName = "";

      if (itemColumn >= 0 && itemColumn < row.length) {
        itemName = row[itemColumn].trim();
      }

      // ======================================================
      // FALLBACK ITEM
      // ======================================================

      if (itemName.isEmpty) {
        for (final cell in row) {
          final value = cell.trim();

          if (value.isEmpty) {
            continue;
          }

          // لو رقم، غالبًا سعر
          if (_parsePrice(value) != null) {
            continue;
          }

          itemName = value;
          break;
        }
      }

      if (itemName.isEmpty) {
        skipped++;
        continue;
      }

      // ======================================================
      // IGNORE HEADER-LIKE ROW
      // ======================================================

      final normalizedName = _normalizeHeader(itemName);

      if (normalizedName == "item" ||
          normalizedName == "item name" ||
          normalizedName == "product" ||
          normalizedName == "product name" ||
          normalizedName == "name" ||
          normalizedName == "description") {
        skipped++;
        continue;
      }

      // ======================================================
      // PRICE
      // ======================================================

      double? price;

      // ======================================================
      // USE PRICE COLUMN
      // ======================================================

      if (priceColumn >= 0 && priceColumn < row.length) {
        price = _parsePrice(row[priceColumn]);
      }

      // ======================================================
      // FALLBACK PRICE
      // ======================================================

      // لو لم نجد عمود Price واضح،
      // نبحث عن أول رقم صالح في الصف.
      if (price == null) {
        for (int column = 0; column < row.length; column++) {
          if (column == itemColumn) {
            continue;
          }

          final parsed = _parsePrice(row[column]);

          if (parsed == null) {
            continue;
          }

          price = parsed;
          break;
        }
      }

      // ======================================================
      // NO PRICE
      // ======================================================

      if (price == null) {
        skipped++;

        debugPrint("SKIPPED - NO PRICE: $row");

        continue;
      }

      // ======================================================
      // ADD ITEM
      // ======================================================

      items.add({"name": itemName, "price": price, "active": true});

      if (items.length <= 10) {
        debugPrint(
          "ITEM ${items.length}: "
          "name='$itemName' | price=$price",
        );
      }
    }

    debugPrint("=================================");
    debugPrint("TOTAL EXCEL ROWS: ${rows.length}");
    debugPrint("VALID ITEMS: ${items.length}");
    debugPrint("SKIPPED ROWS: $skipped");
    debugPrint("=================================");

    return items;
  }

  // ============================================================
  // SPLIT INTO BATCHES
  // ============================================================

  List<List<T>> _splitIntoChunks<T>(List<T> items, int size) {
    final result = <List<T>>[];

    for (int i = 0; i < items.length; i += size) {
      final end = (i + size < items.length) ? i + size : items.length;

      result.add(items.sublist(i, end));
    }

    return result;
  }

  // ============================================================
  // DELETE OLD INVENTORY
  // ============================================================

  Future<int> deleteOldInventory(CollectionReference inventoryRef) async {
    if (mounted) {
      setState(() {
        currentStage = "Removing old inventory...";
        status = "Reading old inventory...";
        progress = 0;
        processedItems = 0;
        totalItems = 0;
        currentBatch = 0;
        totalBatches = 0;
      });
    }

    debugPrint("=================================");
    debugPrint("READING OLD INVENTORY...");
    debugPrint("=================================");

    final snapshot = await inventoryRef.get();

    final oldDocs = snapshot.docs;

    final total = oldDocs.length;

    debugPrint("OLD INVENTORY COUNT: $total");

    if (total == 0) {
      if (mounted) {
        setState(() {
          currentStage = "Old inventory is empty";
          status = "Old inventory is empty";
          progress = 1;
        });
      }

      return 0;
    }

    final chunks = _splitIntoChunks(oldDocs, batchSize);

    totalBatches = chunks.length;

    int deleted = 0;

    for (int i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];

      final batchNumber = i + 1;

      if (mounted) {
        setState(() {
          currentStage = "Removing old inventory...";
          status =
              "Removing old inventory...\n"
              "$deleted / $total";
          currentBatch = batchNumber;
          totalBatches = chunks.length;
          progress = total == 0 ? 0 : deleted / total;
        });
      }

      debugPrint(
        "START DELETE BATCH "
        "$batchNumber/${chunks.length} "
        "(${chunk.length} docs)",
      );

      final batch = FirebaseFirestore.instance.batch();

      for (final doc in chunk) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      deleted += chunk.length;

      debugPrint(
        "DELETE BATCH "
        "$batchNumber/${chunks.length} COMPLETED "
        "(${chunk.length} docs)",
      );

      if (mounted) {
        setState(() {
          processedItems = deleted;
          totalItems = total;
          currentBatch = batchNumber;
          totalBatches = chunks.length;
          progress = (deleted / total).clamp(0.0, 1.0);

          currentStage = "Removing old inventory...";

          status =
              "Removing old inventory...\n"
              "$deleted / $total";
        });
      }
    }

    debugPrint("OLD INVENTORY DELETE FINISHED: $deleted");

    return deleted;
  }

  // ============================================================
  // UPLOAD NEW INVENTORY
  // ============================================================

  Future<int> uploadNewInventory(
    CollectionReference inventoryRef,
    List<Map<String, dynamic>> items,
  ) async {
    if (items.isEmpty) {
      return 0;
    }

    final chunks = _splitIntoChunks(items, batchSize);

    final total = items.length;

    int uploaded = 0;

    totalBatches = chunks.length;

    for (int i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];

      final batchNumber = i + 1;

      if (mounted) {
        setState(() {
          currentStage = "Uploading inventory...";
          status =
              "Uploading inventory...\n"
              "$uploaded / $total";
          processedItems = uploaded;
          totalItems = total;
          currentBatch = batchNumber;
          totalBatches = chunks.length;
          progress = total == 0 ? 0 : uploaded / total;
        });
      }

      debugPrint(
        "START UPLOAD BATCH "
        "$batchNumber/${chunks.length} "
        "(${chunk.length} docs)",
      );

      final batch = FirebaseFirestore.instance.batch();

      for (final item in chunk) {
        final docRef = inventoryRef.doc();

        batch.set(docRef, {
          "name": item["name"].toString(),
          "price": item["price"],
          "active": true,
          "updatedAt": FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      uploaded += chunk.length;

      debugPrint(
        "UPLOAD BATCH "
        "$batchNumber/${chunks.length} COMPLETED "
        "(${chunk.length} docs)",
      );

      if (mounted) {
        setState(() {
          processedItems = uploaded;
          totalItems = total;
          currentBatch = batchNumber;
          totalBatches = chunks.length;
          progress = (uploaded / total).clamp(0.0, 1.0);

          currentStage = "Uploading inventory...";

          status =
              "Uploading inventory...\n"
              "$uploaded / $total";
        });
      }
    }

    return uploaded;
  }

  // ============================================================
  // MAIN UPLOAD
  // ============================================================

  Future<void> uploadInventory() async {
    if (uploading) {
      return;
    }

    try {
      // ========================================================
      // PICK EXCEL
      // ========================================================

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["xlsx", "xls"],
        withData: true,
      );

      if (result == null) {
        return;
      }

      final file = result.files.first;

      if (!mounted) {
        return;
      }

      setState(() {
        uploading = true;

        currentStage = "Reading Excel...";
        status = "Reading Excel...";

        progress = 0;

        processedItems = 0;
        totalItems = 0;

        currentBatch = 0;
        totalBatches = 0;
      });

      debugPrint("=================================");
      debugPrint("OPENING STORE INVENTORY");
      debugPrint("STORE CODE = ${widget.storeCode}");
      debugPrint("FILE NAME = ${file.name}");
      debugPrint(
        "FIREBASE PATH = "
        "stores/${widget.storeCode}/inventory",
      );
      debugPrint("=================================");

      // ========================================================
      // READ BYTES
      // ========================================================

      Uint8List? bytes = file.bytes;

      if (bytes == null || bytes.isEmpty) {
        if (file.path == null) {
          throw Exception("Could not read Excel file.");
        }

        // Windows / Desktop
        bytes = await XFile(file.path!).readAsBytes();
      }

      if (bytes!.isEmpty) {
        throw Exception("Could not read Excel file.");
      }

      // ========================================================
      // READ EXCEL
      // ========================================================

      final rows = await readExcel(bytes);

      debugPrint("=================================");
      debugPrint("ROWS EXTRACTED: ${rows.length}");

      if (rows.isNotEmpty) {
        debugPrint("FIRST ROW: ${rows.first}");
      }

      if (rows.length > 1) {
        debugPrint("SECOND ROW: ${rows[1]}");
      }

      debugPrint("=================================");

      if (rows.isEmpty) {
        throw Exception("No rows were extracted from Excel.");
      }

      // ========================================================
      // EXTRACT ITEM + PRICE
      // ========================================================

      if (mounted) {
        setState(() {
          currentStage = "Detecting items and prices...";
          status = "Detecting items and prices...";
          progress = 0;
        });
      }

      final items = extractItems(rows);

      // ========================================================
      // SAFETY
      // ========================================================

      if (items.isEmpty) {
        throw Exception(
          "No valid items found.\n\n"
          "Excel must contain Item and Price.",
        );
      }

      if (rows.length > 100 && items.length < 10) {
        throw Exception(
          "Excel extraction failed.\n\n"
          "Rows: ${rows.length}\n"
          "Valid items: ${items.length}\n\n"
          "Old Firebase inventory was NOT deleted.",
        );
      }

      debugPrint("=================================");
      debugPrint("ITEMS READY: ${items.length}");
      debugPrint("=================================");

      // ========================================================
      // FIREBASE
      // ========================================================

      final db = FirebaseFirestore.instance;

      final storeRef = db.collection("stores").doc(widget.storeCode);

      final inventoryRef = storeRef.collection("inventory");

      // ========================================================
      // DELETE OLD
      // ========================================================

      if (mounted) {
        setState(() {
          currentStage = "Removing old inventory...";
          status = "Removing old inventory...";
          progress = 0;
          processedItems = 0;
          totalItems = 0;
          currentBatch = 0;
          totalBatches = 0;
        });
      }

      final deleted = await deleteOldInventory(inventoryRef);

      debugPrint("OLD DOCUMENTS DELETED: $deleted");

      // ========================================================
      // UPLOAD NEW
      // ========================================================

      if (mounted) {
        setState(() {
          currentStage = "Uploading inventory...";
          status =
              "Uploading inventory...\n"
              "0 / ${items.length}";
          progress = 0;

          processedItems = 0;
          totalItems = items.length;

          currentBatch = 0;

          totalBatches = (items.length / batchSize).ceil();
        });
      }

      final uploaded = await uploadNewInventory(inventoryRef, items);

      // ========================================================
      // CHECK COUNT
      // ========================================================

      if (uploaded != items.length) {
        throw Exception(
          "Upload count mismatch.\n"
          "Expected: ${items.length}\n"
          "Uploaded: $uploaded",
        );
      }

      // ========================================================
      // UPDATE STORE
      // ========================================================

      if (mounted) {
        setState(() {
          currentStage = "Updating store information...";
          status = "Updating store information...";
          progress = 0.98;
        });
      }

      await storeRef.set({
        "inventoryCount": items.length,
        "inventoryUpdatedAt": FieldValue.serverTimestamp(),
        "inventoryAvailable": true,
        "inventoryFileName": file.name,
      }, SetOptions(merge: true));

      // ========================================================
      // VERIFY
      // ========================================================

      if (mounted) {
        setState(() {
          currentStage = "Verifying inventory...";
          status = "Verifying Firebase inventory...";
          progress = 0.99;
        });
      }

      final verifySnapshot = await inventoryRef.get();

      final firebaseCount = verifySnapshot.docs.length;

      debugPrint("=================================");
      debugPrint("FIREBASE VERIFICATION");
      debugPrint("EXPECTED: ${items.length}");
      debugPrint("FIREBASE: $firebaseCount");
      debugPrint("=================================");

      if (firebaseCount != items.length) {
        throw Exception(
          "Firebase verification failed.\n"
          "Expected: ${items.length}\n"
          "Firebase: $firebaseCount",
        );
      }

      // ========================================================
      // SUCCESS
      // ========================================================

      if (!mounted) {
        return;
      }

      setState(() {
        uploading = false;

        currentStage = "Inventory uploaded successfully ✔";

        processedItems = items.length;
        totalItems = items.length;

        currentBatch = totalBatches;

        progress = 1.0;

        status =
            "Inventory uploaded successfully ✔\n\n"
            "${items.length} items saved.\n\n"
            "Firebase documents: $firebaseCount";
      });

      debugPrint("=================================");
      debugPrint("STORE INVENTORY UPLOAD SUCCESS");
      debugPrint("UPLOADED ITEMS: ${items.length}");
      debugPrint("FIREBASE DOCUMENTS: $firebaseCount");
      debugPrint("PATH: stores/${widget.storeCode}/inventory");
      debugPrint("FIELDS: name + price + active + updatedAt");
      debugPrint("=================================");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "تم تحديث المخزون بنجاح ✔\n"
            "عدد الأصناف: ${items.length}",
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint("=================================");
      debugPrint("STORE INVENTORY UPLOAD FAILED");
      debugPrint("ERROR: $e");
      debugPrint("STACK TRACE:");
      debugPrint(stackTrace.toString());
      debugPrint("=================================");

      if (!mounted) {
        return;
      }

      setState(() {
        uploading = false;

        currentStage = "Upload failed";

        status = "Upload failed:\n$e";

        progress = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("حدث خطأ أثناء رفع المخزون:\n$e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> logout() async {
    if (!mounted) {
      return;
    }

    Navigator.pushNamedAndRemoveUntil(
      context,
      Homescreen.routeName,
      (route) => false,
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,

      appBar: AppBar(
        backgroundColor: Colors.grey.shade100,
        elevation: 0,

        title: const Text(
          "Store Inventory",
          style: TextStyle(
            color: Color(0xff0050c0),
            fontWeight: FontWeight.bold,
          ),
        ),

        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xff0050c0)),
            tooltip: "Logout",
            onPressed: uploading ? null : logout,
          ),
        ],
      ),

      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),

          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),

            child: Column(
              children: [
                const Icon(
                  Icons.inventory_2,
                  size: 70,
                  color: Color(0xff0050c0),
                ),

                const SizedBox(height: 15),

                const Text(
                  "Store Inventory",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff0050c0),
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  "Store: ${widget.storeCode}",
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 35),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final small = constraints.maxWidth < 750;

                    final uploadCard = _buildUploadCard();

                    final infoCard = _buildInfoCard();

                    if (!small) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: uploadCard),
                          const SizedBox(width: 20),
                          Expanded(child: infoCard),
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        uploadCard,
                        const SizedBox(height: 20),
                        infoCard,
                      ],
                    );
                  },
                ),

                const SizedBox(height: 25),

                if (uploading || status.isNotEmpty) _buildProgressCard(),

                const SizedBox(height: 20),

                if (widget.expireDate != null)
                  Text(
                    "Valid Until: "
                    "${widget.expireDate!.toDate().day}/"
                    "${widget.expireDate!.toDate().month}/"
                    "${widget.expireDate!.toDate().year}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // PROGRESS CARD
  // ============================================================

  Widget _buildProgressCard() {
    final percent = (progress * 100).round();

    return Card(
      elevation: 4,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

      child: Padding(
        padding: const EdgeInsets.all(22),

        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  uploading ? Icons.cloud_upload : Icons.check_circle,

                  size: 32,

                  color: uploading ? const Color(0xff0050c0) : Colors.green,
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    currentStage.isEmpty ? status : currentStage,

                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                Text(
                  "$percent%",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff0050c0),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            ClipRRect(
              borderRadius: BorderRadius.circular(10),

              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),

                minHeight: 12,

                backgroundColor: Colors.grey.shade200,

                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xff0050c0),
                ),
              ),
            ),

            const SizedBox(height: 14),

            if (totalItems > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,

                children: [
                  Text(
                    "$processedItems / $totalItems",

                    style: const TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  if (totalBatches > 0)
                    Text(
                      "Batch "
                      "$currentBatch / "
                      "$totalBatches",

                      style: const TextStyle(color: Colors.grey),
                    ),
                ],
              ),

            if (status.isNotEmpty) ...[
              const SizedBox(height: 10),

              Text(
                status,

                textAlign: TextAlign.center,

                style: const TextStyle(
                  color: Color(0xff0050c0),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // UPLOAD CARD
  // ============================================================

  Widget _buildUploadCard() {
    return Card(
      elevation: 4,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

      child: Padding(
        padding: const EdgeInsets.all(20),

        child: Row(
          children: [
            Icon(
              uploading ? Icons.sync : Icons.upload_file,

              size: 55,

              color: uploading ? Colors.orange : const Color(0xff0050c0),
            ),

            const SizedBox(width: 18),

            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    "Upload Inventory",

                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  SizedBox(height: 7),

                  Text("Excel only", style: TextStyle(color: Colors.grey)),

                  SizedBox(height: 5),

                  Text(
                    "Item Name + Price",

                    style: TextStyle(
                      color: Color(0xff0050c0),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            ElevatedButton(
              onPressed: uploading ? null : uploadInventory,

              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff0050c0),

                foregroundColor: Colors.white,

                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              child: Text(uploading ? "Uploading..." : "Upload"),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // INFO CARD
  // ============================================================

  Widget _buildInfoCard() {
    return Card(
      elevation: 4,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

      child: Padding(
        padding: const EdgeInsets.all(20),

        child: Row(
          children: [
            const Icon(Icons.cloud_upload, size: 55, color: Color(0xff0050c0)),

            const SizedBox(width: 18),

            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    "Firebase Inventory",

                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  SizedBox(height: 7),

                  Text(
                    "Only item name and price are stored.",

                    style: TextStyle(color: Colors.grey),
                  ),

                  SizedBox(height: 5),

                  Text(
                    "Quantity is not required.",

                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

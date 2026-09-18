import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../matcher/matcher.dart';

class WarehouseImportScreen extends StatefulWidget {
  final String storeCode;

  const WarehouseImportScreen({super.key, required this.storeCode});

  @override
  State<WarehouseImportScreen> createState() => _WarehouseImportScreenState();
}

class _WarehouseImportScreenState extends State<WarehouseImportScreen> {
  // ============================================================
  // OMAN COLORS
  // ============================================================

  static const Color omanRed = Color(0xffC8102E);
  static const Color omanGreen = Color(0xff00843D);
  static const Color omanWhite = Color(0xffFFFFFF);

  static const Color pageBackground = Color(0xffF5F7F8);
  static const Color textDark = Color(0xff202124);
  static const Color textGrey = Color(0xff6B7280);

  // ============================================================
  // SETTINGS
  // ============================================================

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

    return sheet.rows.map((row) {
      return row.map((cell) {
        if (cell == null) {
          return "";
        }

        final value = cell.value;

        if (value == null) {
          return "";
        }

        return value.toString().trim();
      }).toList();
    }).toList();
  }

  // ============================================================
  // READ CSV
  // ============================================================

  List<List<String>> readCsv(String text) {
    final rows = <List<String>>[];

    final lines = const LineSplitter().convert(text);

    for (final line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }

      rows.add(_parseCsvLine(line));
    }

    return rows;
  }

  // ============================================================
  // CSV PARSER
  // ============================================================

  List<String> _parseCsvLine(String line) {
    final result = <String>[];

    final buffer = StringBuffer();

    bool insideQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        if (insideQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          insideQuotes = !insideQuotes;
        }

        continue;
      }

      if (char == ',' && !insideQuotes) {
        result.add(buffer.toString().trim());

        buffer.clear();

        continue;
      }

      buffer.write(char);
    }

    result.add(buffer.toString().trim());

    return result;
  }

  // ============================================================
  // PDF -> CSV USING TABULA
  // ============================================================

  Future<List<List<String>>> convertPdfToRows(String pdfPath) async {
    if (!Platform.isWindows) {
      throw Exception(
        "PDF conversion using Tabula is currently "
        "configured for Windows.",
      );
    }

    final exeDir = File(Platform.resolvedExecutable).parent.path;

    final tabulaPath =
        "$exeDir"
        "${Platform.pathSeparator}"
        "tools"
        "${Platform.pathSeparator}"
        "tabula.jar";

    final javaPath =
        "$exeDir"
        "${Platform.pathSeparator}"
        "jre"
        "${Platform.pathSeparator}"
        "bin"
        "${Platform.pathSeparator}"
        "java.exe";

    final tabulaFile = File(tabulaPath);

    final javaFile = File(javaPath);

    if (!await tabulaFile.exists()) {
      throw Exception("Tabula not found:\n$tabulaPath");
    }

    if (!await javaFile.exists()) {
      throw Exception("Java not found:\n$javaPath");
    }

    final tempDirectory = await Directory.systemTemp.createTemp(
      "warehouse_import_",
    );

    final csvPath =
        "${tempDirectory.path}"
        "${Platform.pathSeparator}"
        "inventory.csv";

    try {
      if (!mounted) {
        return [];
      }

      setState(() {
        currentStage = "Converting PDF...";
        status = "Converting PDF...";
        progress = 0;
      });

      debugPrint("=================================");
      debugPrint("WAREHOUSE PDF -> CSV");
      debugPrint("PDF: $pdfPath");
      debugPrint("JAVA: $javaPath");
      debugPrint("TABULA: $tabulaPath");
      debugPrint("CSV: $csvPath");
      debugPrint("=================================");

      final result = await Process.run(javaPath, [
        "-jar",
        tabulaPath,
        "-p",
        "all",
        "-f",
        "CSV",
        "-o",
        csvPath,
        pdfPath,
      ], runInShell: true);

      debugPrint("TABULA STDOUT:");
      debugPrint(result.stdout.toString());

      debugPrint("TABULA STDERR:");
      debugPrint(result.stderr.toString());

      debugPrint("TABULA EXIT CODE: ${result.exitCode}");

      if (result.exitCode != 0) {
        throw Exception("Tabula failed:\n${result.stderr}");
      }

      final csvFile = File(csvPath);

      if (!await csvFile.exists()) {
        throw Exception("Tabula did not create CSV file.");
      }

      final csvText = await csvFile.readAsString(encoding: utf8);

      if (csvText.trim().isEmpty) {
        throw Exception("Tabula returned an empty CSV.");
      }

      final rows = readCsv(csvText);

      debugPrint("=================================");
      debugPrint("CSV rows extracted: ${rows.length}");

      if (rows.isNotEmpty) {
        debugPrint("FIRST ROW: ${rows.first}");
      }

      if (rows.length > 1) {
        debugPrint("SECOND ROW: ${rows[1]}");
      }

      debugPrint("=================================");

      return rows;
    } finally {
      try {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      } catch (_) {}
    }
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

    cleaned = cleaned
        .replaceAll(",", "")
        .replaceAll("ر.ع.", "")
        .replaceAll("OMR", "")
        .replaceAll("omr", "")
        .replaceAll(" ", "")
        .trim();

    final number = double.tryParse(cleaned);

    if (number == null) {
      return null;
    }

    if (number <= 0) {
      return null;
    }

    return number;
  }

  // ============================================================
  // FIND HEADER ROW
  // ============================================================

  int _findHeaderRow(List<List<String>> rows) {
    for (int i = 0; i < rows.length && i < 15; i++) {
      final row = rows[i];

      final joined = row.map(_normalizeHeader).join(" ");

      if (joined.contains("item name") ||
          joined.contains("product name") ||
          joined.contains("description") ||
          joined.contains("item") ||
          joined.contains("product") ||
          joined.contains("wh price") ||
          joined.contains("warehouse price") ||
          joined.contains("purchase price") ||
          joined.contains("price")) {
        return i;
      }
    }

    return 0;
  }

  // ============================================================
  // EXTRACT ITEMS
  // FIXED COLUMNS:
  // COLUMN 1 = NAME
  // COLUMN 2 = PRICE
  // COLUMN 3 = OFFER
  // ============================================================

  List<Map<String, dynamic>> extractItems(List<List<String>> rows) {
    if (rows.isEmpty) {
      return [];
    }

    final headerIndex = _findHeaderRow(rows);

    debugPrint("=================================");
    debugPrint("HEADER ROW INDEX: $headerIndex");
    debugPrint("HEADER: ${rows[headerIndex]}");
    debugPrint("FIXED COLUMNS:");
    debugPrint("COLUMN 1 = ITEM NAME");
    debugPrint("COLUMN 2 = PRICE");
    debugPrint("COLUMN 3 = OFFER");
    debugPrint("=================================");

    final items = <Map<String, dynamic>>[];

    int skipped = 0;

    for (int i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];

      // --------------------------------------------------------
      // MUST HAVE AT LEAST NAME + PRICE
      // --------------------------------------------------------

      if (row.length < 2) {
        skipped++;

        debugPrint("SKIPPED - NOT ENOUGH COLUMNS: $row");

        continue;
      }

      // --------------------------------------------------------
      // COLUMN 1 = ITEM NAME
      // --------------------------------------------------------

      final name = row.isNotEmpty ? row[0].trim() : "";

      if (name.isEmpty) {
        skipped++;

        debugPrint("SKIPPED - NO NAME: $row");

        continue;
      }

      // --------------------------------------------------------
      // IGNORE HEADER ROWS
      // --------------------------------------------------------

      final normalizedName = _normalizeHeader(name);

      if (normalizedName == "item" ||
          normalizedName == "item name" ||
          normalizedName == "product" ||
          normalizedName == "product name" ||
          normalizedName == "name" ||
          normalizedName == "description") {
        skipped++;

        continue;
      }

      // --------------------------------------------------------
      // COLUMN 2 = PRICE
      // --------------------------------------------------------

      final price = _parsePrice(row[1]);

      if (price == null) {
        skipped++;

        debugPrint("SKIPPED - NO VALID PRICE: $row");

        continue;
      }

      // --------------------------------------------------------
      // COLUMN 3 = OFFER
      // --------------------------------------------------------

      String offer = "";

      if (row.length >= 3) {
        offer = row[2].trim();
      }

      // --------------------------------------------------------
      // ADD ITEM
      // --------------------------------------------------------

      final item = {
        "name": name,
        "price": price,
        "offer": offer,
        "active": true,
      };

      items.add(item);

      if (items.length <= 10) {
        debugPrint(
          "ITEM ${items.length}: "
          "name='$name' | "
          "price=$price | "
          "offer='$offer'",
        );
      }
    }

    debugPrint("=================================");
    debugPrint("TOTAL ROWS: ${rows.length}");
    debugPrint("VALID ITEMS: ${items.length}");
    debugPrint("SKIPPED ROWS: $skipped");
    debugPrint("=================================");

    return items;
  }

  // ============================================================
  // DELETE OLD INVENTORY
  // ============================================================

  Future<void> deleteOldInventory(
    FirebaseFirestore db,
    CollectionReference inventoryRef,
  ) async {
    int deleted = 0;

    while (true) {
      final snapshot = await inventoryRef.limit(400).get();

      if (snapshot.docs.isEmpty) {
        break;
      }

      final batch = db.batch();

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);

        deleted++;
      }

      await batch.commit();

      debugPrint("OLD INVENTORY DELETED: $deleted");

      if (!mounted) {
        return;
      }

      setState(() {
        currentStage = "Removing old inventory...";

        status =
            "Removing old inventory...\n"
            "$deleted old items deleted";

        processedItems = deleted;
      });
    }

    debugPrint(
      "OLD INVENTORY DELETE FINISHED: "
      "$deleted",
    );
  }

  // ============================================================
  // IMPORT INVENTORY
  // ============================================================

  Future<void> importInventory() async {
    if (uploading) {
      return;
    }

    try {
      // ========================================================
      // PICK FILE
      // ========================================================

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["xlsx", "xls", "pdf", "csv"],
        withData: true,
      );

      if (result == null) {
        return;
      }

      final file = result.files.first;

      final filePath = file.path;

      if (filePath == null || filePath.trim().isEmpty) {
        throw Exception("Could not get file path.");
      }

      final extension = file.extension?.toLowerCase() ?? "";

      debugPrint("");
      debugPrint("=================================");
      debugPrint(
        "WAREHOUSE INVENTORY "
        "UPLOAD STARTED",
      );
      debugPrint("FILE NAME: ${file.name}");
      debugPrint("FILE PATH: $filePath");
      debugPrint("FILE EXTENSION: $extension");
      debugPrint("STORE CODE: ${widget.storeCode}");
      debugPrint("=================================");

      if (!mounted) {
        return;
      }

      setState(() {
        uploading = true;

        currentStage = "Reading file...";

        status = "Reading file...";

        progress = 0;

        processedItems = 0;

        totalItems = 0;

        currentBatch = 0;

        totalBatches = 0;
      });

      // ========================================================
      // READ FILE
      // ========================================================

      List<List<String>> rows = [];

      // ========================================================
      // PDF
      // ========================================================

      if (extension == "pdf") {
        rows = await convertPdfToRows(filePath);
      }
      // ========================================================
      // CSV
      // ========================================================
      else if (extension == "csv") {
        if (mounted) {
          setState(() {
            currentStage = "Reading CSV...";

            status = "Reading CSV...";

            progress = 0;
          });
        }

        final csvText = await File(filePath).readAsString(encoding: utf8);

        rows = readCsv(csvText);
      }
      // ========================================================
      // EXCEL
      // ========================================================
      else {
        Uint8List? bytes = file.bytes;

        if (bytes == null || bytes.isEmpty) {
          bytes = await File(filePath).readAsBytes();
        }

        if (bytes.isEmpty) {
          throw Exception("Could not read Excel file.");
        }

        if (mounted) {
          setState(() {
            currentStage = "Reading Excel...";

            status = "Reading Excel...";

            progress = 0;
          });
        }

        rows = await readExcel(bytes);
      }

      // ========================================================
      // DEBUG
      // ========================================================

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
        throw Exception("No rows were extracted from the file.");
      }

      // ========================================================
      // EXTRACT
      // ========================================================

      if (mounted) {
        setState(() {
          currentStage = "Detecting item names, prices and offers...";

          status = "Detecting item names, prices and offers...";

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
          "The file must contain:\n"
          "Column 1 = Item Name\n"
          "Column 2 = Price\n"
          "Column 3 = Offer",
        );
      }

      if (rows.length > 100 && items.length < 10) {
        throw Exception(
          "Extraction failed.\n\n"
          "Rows extracted: ${rows.length}\n"
          "Valid items: ${items.length}\n\n"
          "Old Firebase inventory "
          "was NOT deleted.",
        );
      }

      // ========================================================
      // FIREBASE
      // ========================================================

      final db = FirebaseFirestore.instance;

      final storeRef = db.collection("stores").doc(widget.storeCode);

      final inventoryRef = storeRef.collection("inventory");

      debugPrint("=================================");
      debugPrint(
        "FIREBASE STORE: "
        "${widget.storeCode}",
      );
      debugPrint(
        "FIREBASE PATH: "
        "stores/${widget.storeCode}/inventory",
      );
      debugPrint("ITEMS TO UPLOAD: ${items.length}");
      debugPrint("=================================");

      // ========================================================
      // DELETE OLD INVENTORY
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

      await deleteOldInventory(db, inventoryRef);

      // ========================================================
      // UPLOAD NEW INVENTORY
      // ========================================================

      int uploaded = 0;

      int batchNumber = 0;

      WriteBatch batch = db.batch();

      totalItems = items.length;

      totalBatches = (items.length / batchSize).ceil();

      for (final item in items) {
        final name = item["name"].toString();

        final price = item["price"];

        final offer = item["offer"]?.toString() ?? "";

        final docRef = inventoryRef.doc();

        batch.set(docRef, {
          "name": name,
          "original": name,
          "normalized": Matcher.normalize(name),
          "price": price,
          "offer": offer,
          "active": true,
          "updatedAt": FieldValue.serverTimestamp(),
        });

        uploaded++;

        // ======================================================
        // COMMIT EVERY 400
        // ======================================================

        if (uploaded % batchSize == 0) {
          batchNumber++;

          debugPrint("=================================");
          debugPrint("UPLOADING BATCH #$batchNumber");
          debugPrint(
            "ITEMS: "
            "$uploaded / ${items.length}",
          );
          debugPrint("=================================");

          if (mounted) {
            setState(() {
              currentStage = "Uploading inventory...";

              status =
                  "Uploading inventory...\n"
                  "$uploaded / ${items.length}";

              processedItems = uploaded;

              totalItems = items.length;

              currentBatch = batchNumber;

              totalBatches = (items.length / batchSize).ceil();

              progress = (uploaded / items.length).clamp(0.0, 1.0);
            });
          }

          await batch.commit();

          debugPrint(
            "BATCH #$batchNumber "
            "COMMITTED SUCCESSFULLY",
          );

          batch = db.batch();
        } else {
          if (mounted && (uploaded % 20 == 0 || uploaded == items.length)) {
            setState(() {
              currentStage = "Uploading inventory...";

              status =
                  "Uploading inventory...\n"
                  "$uploaded / ${items.length}";

              processedItems = uploaded;

              totalItems = items.length;

              currentBatch = (uploaded / batchSize).ceil();

              totalBatches = (items.length / batchSize).ceil();

              progress = (uploaded / items.length).clamp(0.0, 1.0);
            });
          }
        }
      }

      // ========================================================
      // COMMIT REMAINING
      // ========================================================

      if (uploaded % batchSize != 0) {
        batchNumber++;

        debugPrint("=================================");
        debugPrint(
          "UPLOADING FINAL BATCH "
          "#$batchNumber",
        );
        debugPrint(
          "ITEMS: "
          "$uploaded / ${items.length}",
        );
        debugPrint("=================================");

        await batch.commit();

        debugPrint("FINAL BATCH COMMITTED SUCCESSFULLY");
      }

      // ========================================================
      // SAVE STORE INFO
      // ========================================================

      if (mounted) {
        setState(() {
          currentStage = "Updating store information...";

          status = "Updating store information...";

          progress = 0.97;
        });
      }

      await storeRef.set({
        "inventoryCount": items.length,
        "inventoryUpdatedAt": FieldValue.serverTimestamp(),
        "inventoryAvailable": true,
        "inventoryFileName": file.name,
      }, SetOptions(merge: true));

      debugPrint("STORE INFO UPDATED SUCCESSFULLY");

      // ========================================================
      // VERIFY FIREBASE
      // ========================================================

      if (mounted) {
        setState(() {
          currentStage = "Verifying inventory...";

          status = "Verifying Firebase inventory...";

          progress = 0.99;
        });
      }

      final verifySnapshot = await inventoryRef.get();

      debugPrint("");
      debugPrint("=================================");
      debugPrint("FIREBASE VERIFICATION");
      debugPrint("EXPECTED ITEMS: ${items.length}");
      debugPrint(
        "FIREBASE DOCUMENTS: "
        "${verifySnapshot.docs.length}",
      );
      debugPrint(
        "FIREBASE PATH: "
        "stores/${widget.storeCode}/inventory",
      );
      debugPrint("=================================");

      // ========================================================
      // VERIFY FAILED
      // ========================================================

      if (!mounted) {
        return;
      }

      if (verifySnapshot.docs.length != items.length) {
        setState(() {
          uploading = false;

          currentStage = "Verification failed";

          status =
              "Upload completed but "
              "verification failed.\n\n"
              "Expected: ${items.length}\n"
              "Firebase: "
              "${verifySnapshot.docs.length}";

          progress = 0.99;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Uploaded successfully, but the quantity "
              "does not match.\n"
              "Required: ${items.length} | "
              "Found: "
              "${verifySnapshot.docs.length}",
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 7),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(12),
          ),
        );

        return;
      }

      // ========================================================
      // SUCCESS
      // ========================================================

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
            "Firebase documents: "
            "${verifySnapshot.docs.length}";
      });

      debugPrint("");
      debugPrint("=================================");
      debugPrint(
        "WAREHOUSE INVENTORY "
        "UPLOAD SUCCESS",
      );
      debugPrint("UPLOADED ITEMS: ${items.length}");
      debugPrint(
        "FIREBASE PATH: "
        "stores/${widget.storeCode}/inventory",
      );
      debugPrint(
        "FIELDS: "
        "name + original + normalized + price + offer",
      );
      debugPrint("QTY FIELD: NOT STORED");
      debugPrint("=================================");
      debugPrint("");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "تم تحديث مخزون المخزن بنجاح ✔\n"
            "عدد الأصناف: ${items.length}",
          ),
          backgroundColor: omanGreen,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(12),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint("");
      debugPrint("=================================");
      debugPrint(
        "WAREHOUSE INVENTORY "
        "UPLOAD FAILED",
      );
      debugPrint("ERROR: $e");
      debugPrint("STACK TRACE:");
      debugPrint(stackTrace.toString());
      debugPrint("=================================");
      debugPrint("");

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
          content: Text(
            "حدث خطأ أثناء رفع المخزون:\n"
            "$e",
          ),
          backgroundColor: omanRed,
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(12),
        ),
      );
    }
  }

  // ============================================================
  // PROGRESS CARD
  // ============================================================

  Widget _buildProgressCard() {
    final percent = (progress * 100).round();

    return Card(
      elevation: 1.5,
      color: omanWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: (uploading ? omanRed : omanGreen).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    uploading
                        ? Icons.cloud_upload_rounded
                        : Icons.check_circle_rounded,
                    color: uploading ? omanRed : omanGreen,
                    size: 25,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    currentStage.isEmpty ? status : currentStage,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textDark,
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                Text(
                  "$percent%",
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: omanRed,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 11,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(omanRed),
              ),
            ),

            const SizedBox(height: 13),

            if (totalItems > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "$processedItems / "
                    "$totalItems",
                    style: const TextStyle(
                      color: textGrey,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),

                  if (totalBatches > 0)
                    Text(
                      "Batch "
                      "$currentBatch / "
                      "$totalBatches",
                      style: const TextStyle(color: textGrey, fontSize: 12),
                    ),
                ],
              ),

            if (status.isNotEmpty) ...[
              const SizedBox(height: 10),

              Text(
                status,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: omanGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // IMPORT CARD
  // ============================================================

  Widget _buildImportCard() {
    return Card(
      elevation: 1.5,
      color: omanWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: omanRed.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                uploading ? Icons.sync_rounded : Icons.upload_file_rounded,
                size: 30,
                color: uploading ? omanGreen : omanRed,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Import Warehouse",
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: textDark,
                    ),
                  ),

                  SizedBox(height: 6),

                  Text(
                    "PDF / Excel / CSV",
                    style: TextStyle(color: textGrey, fontSize: 12),
                  ),

                  SizedBox(height: 5),

                  Text(
                    "Item Name + Price + Offer",
                    style: TextStyle(
                      color: omanGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            ElevatedButton(
              onPressed: uploading ? null : importInventory,
              style: ElevatedButton.styleFrom(
                backgroundColor: omanRed,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(uploading ? "Uploading..." : "Import"),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // FIREBASE INFO CARD
  // ============================================================

  Widget _buildInfoCard() {
    return Card(
      elevation: 1.5,
      color: omanWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: omanGreen.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.cloud_done_rounded,
                size: 30,
                color: omanGreen,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Firebase Inventory",
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: textDark,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    "Store: ${widget.storeCode}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: textGrey, fontSize: 12),
                  ),

                  const SizedBox(height: 5),

                  const Text(
                    "Name + Original + Normalized + Price + Offer",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: omanGreen,
                      fontSize: 12,
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

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBackground,

      // ========================================================
      // APP BAR
      // ========================================================
      appBar: AppBar(
        backgroundColor: omanRed,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Warehouse Inventory",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),

      body: Column(
        children: [
          // ======================================================
          // OMAN HEADER STRIPE
          // ======================================================

          Container(height: 5, color: omanGreen),

          // ======================================================
          // BODY
          // ======================================================
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),

                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),

                  child: Column(
                    children: [
                      // ==================================================
                      // HEADER
                      // ==================================================

                      Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          color: omanRed.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.inventory_2_rounded,
                          size: 43,
                          color: omanRed,
                        ),
                      ),

                      const SizedBox(height: 14),

                      const Text(
                        "Warehouse Inventory",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.bold,
                          color: textDark,
                        ),
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        "Import warehouse inventory "
                        "from PDF, Excel or CSV",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: textGrey, fontSize: 13),
                      ),

                      const SizedBox(height: 7),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: omanGreen.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "Store: ${widget.storeCode}",
                          style: const TextStyle(
                            color: omanGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ==================================================
                      // CARDS
                      // ==================================================
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final small = constraints.maxWidth < 750;

                          final importCard = _buildImportCard();

                          final infoCard = _buildInfoCard();

                          if (!small) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: importCard),

                                const SizedBox(width: 20),

                                Expanded(child: infoCard),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              importCard,

                              const SizedBox(height: 14),

                              infoCard,
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 18),

                      // ==================================================
                      // PROGRESS
                      // ==================================================
                      if (uploading || status.isNotEmpty) _buildProgressCard(),

                      const SizedBox(height: 20),

                      // ==================================================
                      // FIREBASE PATH
                      // ==================================================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.account_tree_outlined,
                              size: 18,
                              color: omanGreen,
                            ),

                            const SizedBox(width: 8),

                            Expanded(
                              child: Text(
                                "stores/"
                                "${widget.storeCode}"
                                "/inventory",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: textGrey,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
  bool uploading = false;

  String status = "";

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
        "PDF conversion using Tabula is currently configured for Windows.",
      );
    }

    // ============================================================
    // IMPORTANT
    //
    // نفس طريقة الـ EXE:
    //
    // app/
    //   stockgap2026.exe
    //   tools/
    //      tabula.jar
    //   jre/
    //      bin/
    //         java.exe
    //
    // ============================================================

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
        status = "Converting PDF...";
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
  // FIND ITEM NAME COLUMN
  // ============================================================

  int _findNameColumn(List<String> header) {
    const exactNames = [
      "item name",
      "product name",
      "name",
      "item",
      "description",
      "product",
      "item description",
      "product description",
    ];

    // ----------------------------------------------------------
    // EXACT
    // ----------------------------------------------------------

    for (int i = 0; i < header.length; i++) {
      final value = _normalizeHeader(header[i]);

      if (exactNames.contains(value)) {
        return i;
      }
    }

    // ----------------------------------------------------------
    // PARTIAL
    // ----------------------------------------------------------

    for (int i = 0; i < header.length; i++) {
      final value = _normalizeHeader(header[i]);

      if (value.contains("item name") ||
          value.contains("product name") ||
          value.contains("description")) {
        return i;
      }
    }

    // ----------------------------------------------------------
    // DEFAULT
    // ----------------------------------------------------------

    return 0;
  }

  // ============================================================
  // FIND PRICE COLUMNS
  // ============================================================

  List<int> _findPriceColumns(List<String> header) {
    final result = <int>[];

    for (int i = 0; i < header.length; i++) {
      final value = _normalizeHeader(header[i]);

      if (value.contains("wh price") ||
          value.contains("warehouse price") ||
          value.contains("purchase price") ||
          value.contains("buy price") ||
          value == "price" ||
          value.contains("price")) {
        result.add(i);
      }
    }

    return result;
  }

  // ============================================================
  // EXTRACT ITEM + PRICE
  //
  // IMPORTANT:
  //
  // NO QTY
  //
  // Result:
  //
  // {
  //   name: "...",
  //   price: 3.300
  // }
  //
  // ============================================================

  List<Map<String, dynamic>> extractItems(List<List<String>> rows) {
    if (rows.isEmpty) {
      return [];
    }

    final headerIndex = _findHeaderRow(rows);

    final header = rows[headerIndex];

    debugPrint("=================================");
    debugPrint("HEADER ROW INDEX: $headerIndex");
    debugPrint("HEADER: $header");
    debugPrint("=================================");

    final nameColumn = _findNameColumn(header);

    final priceColumns = _findPriceColumns(header);

    debugPrint("NAME COLUMN: $nameColumn");

    debugPrint("PRICE COLUMNS: $priceColumns");

    final items = <Map<String, dynamic>>[];

    int skipped = 0;

    // ==========================================================
    // READ ROWS
    // ==========================================================

    for (int i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];

      if (row.isEmpty) {
        skipped++;
        continue;
      }

      // --------------------------------------------------------
      // ITEM NAME
      // --------------------------------------------------------

      String name = "";

      if (nameColumn < row.length) {
        name = row[nameColumn].trim();
      }

      // --------------------------------------------------------
      // FALLBACK:
      // SEARCH FIRST NON-NUMERIC CELL
      // --------------------------------------------------------

      if (name.isEmpty) {
        for (final cell in row) {
          final value = cell.trim();

          if (value.isEmpty) {
            continue;
          }

          if (_parsePrice(value) != null) {
            continue;
          }

          name = value;

          break;
        }
      }

      if (name.isEmpty) {
        skipped++;
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
      // PRICE
      // --------------------------------------------------------

      double? price;

      // --------------------------------------------------------
      // 1. SEARCH KNOWN PRICE COLUMNS
      // --------------------------------------------------------

      for (final column in priceColumns) {
        if (column >= row.length) {
          continue;
        }

        final parsed = _parsePrice(row[column]);

        if (parsed == null) {
          continue;
        }

        if (price == null || parsed < price) {
          price = parsed;
        }
      }

      // --------------------------------------------------------
      // 2. FALLBACK:
      // SEARCH ALL COLUMNS
      // --------------------------------------------------------

      if (price == null) {
        for (int column = 0; column < row.length; column++) {
          if (column == nameColumn) {
            continue;
          }

          final parsed = _parsePrice(row[column]);

          if (parsed == null) {
            continue;
          }

          if (price == null || parsed < price) {
            price = parsed;
          }
        }
      }

      // --------------------------------------------------------
      // NO PRICE
      // --------------------------------------------------------

      if (price == null) {
        skipped++;

        debugPrint("SKIPPED - NO PRICE: $row");

        continue;
      }

      // --------------------------------------------------------
      // ADD ITEM
      // --------------------------------------------------------

      final item = {"name": name, "price": price, "active": true};

      items.add(item);

      if (items.length <= 10) {
        debugPrint(
          "ITEM ${items.length}: "
          "name='$name' | "
          "price=$price",
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
        status =
            "Deleting old inventory...\n"
            "$deleted old items deleted";
      });
    }

    debugPrint("OLD INVENTORY DELETE FINISHED: $deleted");
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
      debugPrint("WAREHOUSE INVENTORY UPLOAD STARTED");
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
        status = "Reading file...";
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

        if (!mounted) {
          return;
        }

        setState(() {
          status = "Reading Excel...";
        });

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
      // EXTRACT ITEM + PRICE
      // ========================================================

      if (!mounted) {
        return;
      }

      setState(() {
        status = "Detecting item names and prices...";
      });

      final items = extractItems(rows);

      // ========================================================
      // SAFETY
      // ========================================================

      if (items.isEmpty) {
        throw Exception(
          "No valid items found.\n\n"
          "The file must contain an item name and a price.",
        );
      }

      // ========================================================
      // EXTRA SAFETY
      //
      // Do not delete Firebase inventory
      // if extraction clearly failed.
      // ========================================================

      if (rows.length > 100 && items.length < 10) {
        throw Exception(
          "Extraction failed.\n\n"
          "Rows extracted: ${rows.length}\n"
          "Valid items: ${items.length}\n\n"
          "Old Firebase inventory was NOT deleted.",
        );
      }

      // ========================================================
      // FIREBASE
      // ========================================================

      final db = FirebaseFirestore.instance;

      final storeRef = db.collection("stores").doc(widget.storeCode);

      final inventoryRef = storeRef.collection("inventory");

      debugPrint("=================================");
      debugPrint("FIREBASE STORE: ${widget.storeCode}");
      debugPrint(
        "FIREBASE PATH: "
        "stores/${widget.storeCode}/inventory",
      );
      debugPrint("ITEMS TO UPLOAD: ${items.length}");
      debugPrint("=================================");

      // ========================================================
      // DELETE OLD INVENTORY
      // ========================================================

      if (!mounted) {
        return;
      }

      setState(() {
        status = "Removing old inventory...";
      });

      await deleteOldInventory(db, inventoryRef);

      // ========================================================
      // UPLOAD NEW INVENTORY
      // ========================================================

      int uploaded = 0;

      int batchNumber = 0;

      WriteBatch batch = db.batch();

      for (final item in items) {
        final name = item["name"].toString();

        final price = item["price"];

        final docRef = inventoryRef.doc();

        // ======================================================
        // SAME CONCEPT
        //
        // name
        // original
        // normalized
        // price
        // active
        // updatedAt
        //
        // NO QTY
        // ======================================================

        batch.set(docRef, {
          "name": name,
          "original": name,
          "normalized": Matcher.normalize(name),
          "price": price,
          "active": true,
          "updatedAt": FieldValue.serverTimestamp(),
        });

        uploaded++;

        // ======================================================
        // COMMIT EVERY 400
        // ======================================================

        if (uploaded % 400 == 0) {
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
              status =
                  "Uploading inventory...\n"
                  "$uploaded / ${items.length}";
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
              status =
                  "Uploading inventory...\n"
                  "$uploaded / ${items.length}";
            });
          }
        }
      }

      // ========================================================
      // COMMIT REMAINING
      // ========================================================

      if (uploaded % 400 != 0) {
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
          status = "Verifying Firebase inventory...";
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

          status =
              "Upload completed but verification failed.\n\n"
              "Expected: ${items.length}\n"
              "Firebase: "
              "${verifySnapshot.docs.length}";
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "تم الرفع ولكن العدد غير مطابق.\n"
              "المطلوب: ${items.length} | "
              "الموجود: "
              "${verifySnapshot.docs.length}",
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 7),
          ),
        );

        return;
      }

      // ========================================================
      // SUCCESS
      // ========================================================

      setState(() {
        uploading = false;

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
      debugPrint("FIELDS: name + price + normalized");
      debugPrint("QTY FIELD: NOT STORED");
      debugPrint("=================================");
      debugPrint("");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "تم تحديث مخزون المخزن بنجاح ✔\n"
            "عدد الأصناف: ${items.length}",
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
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

        status = "Upload failed:\n$e";
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
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Import Warehouse Inventory")),

      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.inventory_2,
                    size: 80,
                    color: Color(0xff0050c0),
                  ),

                  const SizedBox(height: 30),

                  const Text(
                    "Warehouse Inventory",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    "PDF / Excel → Item Name + Price → Firebase",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    "Store: ${widget.storeCode}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xff0050c0),
                    ),
                  ),

                  const SizedBox(height: 30),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: uploading ? null : importInventory,

                      icon: uploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.upload_file),

                      label: Text(
                        uploading ? "Uploading..." : "Upload PDF / Excel",
                      ),

                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff0050c0),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  if (status.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey.shade100,
                      ),
                      child: Text(
                        status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xff0050c0),
                          fontSize: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

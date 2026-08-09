import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
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

  // Firestore maximum is 500.
  // 200 is safer for slower connections.
  static const int batchSize = 200;

  // Do NOT run multiple Firebase commits at the same time.
  // Sequential commits are much more stable.
  static const int parallelBatches = 1;

  // Maximum time for one Firebase commit.
  static const Duration firebaseTimeout = Duration(seconds: 180);

  // Number of retry attempts.
  static const int maxRetries = 3;

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

        try {
          final value = cell.value;

          if (value == null) {
            return "";
          }

          return value.toString().trim();
        } catch (_) {
          return cell.toString().trim();
        }
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
          continue;
        }

        insideQuotes = !insideQuotes;
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
        .replaceAll("ر.ع.", "")
        .replaceAll("OMR", "")
        .replaceAll("omr", "")
        .replaceAll("RO", "")
        .replaceAll("ro", "")
        .replaceAll(" ", "")
        .trim();

    if (cleaned.isEmpty) {
      return null;
    }

    if (cleaned.contains("%")) {
      return null;
    }

    cleaned = cleaned.replaceAll(",", "");

    final number = double.tryParse(cleaned);

    if (number == null) {
      return null;
    }

    if (number <= 0) {
      return null;
    }

    if (number > 100000) {
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
          joined.contains("warehouse price") ||
          joined.contains("purchase price") ||
          joined.contains("wh price") ||
          joined == "item price" ||
          joined.contains("description")) {
        return i;
      }
    }

    return 0;
  }

  // ============================================================
  // FIND NAME COLUMN
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

    // Exact match
    for (int i = 0; i < header.length; i++) {
      final value = _normalizeHeader(header[i]);

      if (exactNames.contains(value)) {
        return i;
      }
    }

    // Partial match
    for (int i = 0; i < header.length; i++) {
      final value = _normalizeHeader(header[i]);

      if (value.contains("item name") ||
          value.contains("product name") ||
          value.contains("description")) {
        return i;
      }
    }

    return 0;
  }

  // ============================================================
  // FIND PRICE COLUMNS
  // ============================================================

  List<int> _findPriceColumns(List<String> header) {
    final priority = <int>[];

    final normal = <int>[];

    for (int i = 0; i < header.length; i++) {
      final value = _normalizeHeader(header[i]);

      // Highest priority
      if (value.contains("warehouse price") ||
          value.contains("wh price") ||
          value.contains("purchase price")) {
        priority.add(i);
        continue;
      }

      if (value == "price" ||
          value.contains("sale price") ||
          value.contains("unit price") ||
          value.contains("cost price") ||
          value.contains("price")) {
        normal.add(i);
      }
    }

    return [...priority, ...normal];
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

    debugPrint("HEADER ROW INDEX: $headerIndex");

    debugPrint("HEADER: $header");

    debugPrint("=================================");

    final nameColumn = _findNameColumn(header);

    final priceColumns = _findPriceColumns(header);

    debugPrint("NAME COLUMN: $nameColumn");

    debugPrint("PRICE COLUMNS: $priceColumns");

    final items = <Map<String, dynamic>>[];

    int skipped = 0;

    for (int i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];

      if (row.isEmpty) {
        skipped++;
        continue;
      }

      // ======================================================
      // NAME
      // ======================================================

      String name = "";

      if (nameColumn < row.length) {
        name = row[nameColumn].trim();
      }

      // ======================================================
      // FALLBACK NAME
      // ======================================================

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

      // ======================================================
      // IGNORE HEADER-LIKE ROWS
      // ======================================================

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

      // ======================================================
      // PRICE
      // ======================================================

      double? price;

      // ======================================================
      // PRICE COLUMNS
      // ======================================================

      for (final column in priceColumns) {
        if (column >= row.length) {
          continue;
        }

        final parsed = _parsePrice(row[column]);

        if (parsed == null) {
          continue;
        }

        if (price == null) {
          price = parsed;
        }
      }

      // ======================================================
      // FALLBACK PRICE
      // ======================================================

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

      items.add({"name": name, "price": price, "active": true});

      if (items.length <= 10) {
        debugPrint(
          "ITEM ${items.length}: "
          "name='$name' | price=$price",
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
        "$exeDir${Platform.pathSeparator}"
        "tools${Platform.pathSeparator}"
        "tabula.jar";

    final javaPath =
        "$exeDir${Platform.pathSeparator}"
        "jre${Platform.pathSeparator}"
        "bin${Platform.pathSeparator}"
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
      "store_inventory_",
    );

    final csvPath =
        "${tempDirectory.path}"
        "${Platform.pathSeparator}"
        "inventory.csv";

    try {
      if (mounted) {
        setState(() {
          currentStage = "Converting PDF...";

          status = "Converting PDF...";

          progress = 0;
        });
      }

      debugPrint("=================================");

      debugPrint("STORE INVENTORY PDF -> CSV");

      debugPrint("STORE CODE: ${widget.storeCode}");

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

      debugPrint(
        "TABULA EXIT CODE: "
        "${result.exitCode}",
      );

      if (result.exitCode != 0) {
        throw Exception(
          "Tabula failed:\n"
          "${result.stderr}",
        );
      }

      final csvFile = File(csvPath);

      if (!await csvFile.exists()) {
        throw Exception("Tabula did not create CSV file.");
      }

      final csvText = await csvFile.readAsString(encoding: utf8);

      if (csvText.trim().isEmpty) {
        throw Exception("Tabula returned an empty CSV.");
      }

      return readCsv(csvText);
    } finally {
      try {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  // ============================================================
  // SPLIT LIST
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
  // FIREBASE COMMIT WITH RETRY
  // ============================================================

  Future<void> _commitBatchWithRetry(
    WriteBatch batch,
    String operation,
    int batchNumber,
    int totalBatches,
  ) async {
    Object? lastError;

    StackTrace? lastStackTrace;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint("---------------------------------");

        debugPrint(
          "$operation "
          "BATCH $batchNumber/$totalBatches "
          "ATTEMPT $attempt/$maxRetries",
        );

        debugPrint(
          "TIMEOUT: "
          "${firebaseTimeout.inSeconds} seconds",
        );

        await batch.commit().timeout(firebaseTimeout);

        debugPrint(
          "$operation "
          "BATCH $batchNumber/$totalBatches "
          "SUCCESS",
        );

        return;
      } catch (e, stackTrace) {
        lastError = e;

        lastStackTrace = stackTrace;

        debugPrint("---------------------------------");

        debugPrint(
          "$operation "
          "BATCH $batchNumber/$totalBatches "
          "FAILED",
        );

        debugPrint("ATTEMPT: $attempt/$maxRetries");

        debugPrint("ERROR: $e");

        if (attempt < maxRetries) {
          final waitSeconds = attempt * 5;

          debugPrint(
            "RETRYING IN "
            "$waitSeconds SECONDS...",
          );

          if (mounted) {
            setState(() {
              currentStage = "$operation batch failed. Retrying...";

              status =
                  "$operation\n"
                  "Batch $batchNumber / "
                  "$totalBatches\n"
                  "Retry $attempt / "
                  "$maxRetries";
            });
          }

          await Future.delayed(Duration(seconds: waitSeconds));
        }
      }
    }

    debugPrint("=================================");

    debugPrint(
      "$operation BATCH FAILED "
      "AFTER $maxRetries ATTEMPTS",
    );

    debugPrint("ERROR: $lastError");

    debugPrint("STACK TRACE:");

    debugPrint(lastStackTrace.toString());

    debugPrint("=================================");

    throw Exception(
      "Firebase $operation timeout/error "
      "after $maxRetries attempts.\n"
      "Batch: $batchNumber/$totalBatches\n"
      "Last error: $lastError",
    );
  }

  // ============================================================
  // GET OLD DOCUMENTS WITH RETRY
  // ============================================================

  Future<List<QueryDocumentSnapshot>> _getOldInventoryWithRetry(
    CollectionReference inventoryRef,
  ) async {
    Object? lastError;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint(
          "READ OLD INVENTORY "
          "ATTEMPT $attempt/$maxRetries",
        );

        final snapshot = await inventoryRef.get().timeout(firebaseTimeout);

        debugPrint(
          "OLD INVENTORY READ SUCCESS: "
          "${snapshot.docs.length}",
        );

        return snapshot.docs;
      } catch (e) {
        lastError = e;

        debugPrint(
          "READ OLD INVENTORY FAILED "
          "ATTEMPT $attempt/$maxRetries",
        );

        debugPrint("ERROR: $e");

        if (attempt < maxRetries) {
          final waitSeconds = attempt * 5;

          await Future.delayed(Duration(seconds: waitSeconds));
        }
      }
    }

    throw Exception(
      "Firebase read timeout/error "
      "after $maxRetries attempts.\n"
      "Last error: $lastError",
    );
  }

  // ============================================================
  // DELETE OLD INVENTORY
  // ============================================================

  Future<int> deleteOldInventory(
    FirebaseFirestore db,
    CollectionReference inventoryRef,
  ) async {
    try {
      if (mounted) {
        setState(() {
          currentStage = "Reading old inventory...";

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

      // ======================================================
      // READ OLD DOCUMENTS
      // ======================================================

      final oldDocs = await _getOldInventoryWithRetry(inventoryRef);

      final total = oldDocs.length;

      debugPrint("=================================");

      debugPrint("OLD INVENTORY COUNT: $total");

      debugPrint("=================================");

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

      // ======================================================
      // SPLIT
      // ======================================================

      final chunks = _splitIntoChunks(oldDocs, batchSize);

      totalBatches = chunks.length;

      debugPrint(
        "DELETE BATCHES: "
        "${chunks.length}",
      );

      debugPrint("BATCH SIZE: $batchSize");

      debugPrint(
        "PARALLEL BATCHES: "
        "$parallelBatches",
      );

      // ======================================================
      // DELETE
      // ======================================================

      int deleted = 0;

      for (int start = 0; start < chunks.length; start += parallelBatches) {
        final end = (start + parallelBatches < chunks.length)
            ? start + parallelBatches
            : chunks.length;

        final currentChunks = chunks.sublist(start, end);

        debugPrint("=================================");

        debugPrint(
          "START DELETE GROUP "
          "${start + 1}-$end / "
          "${chunks.length}",
        );

        debugPrint("=================================");

        final futures = <Future<int>>[];

        for (int i = 0; i < currentChunks.length; i++) {
          final chunk = currentChunks[i];

          final batchNumber = start + i + 1;

          futures.add(
            _deleteInventoryBatch(db, chunk, batchNumber, chunks.length),
          );
        }

        final results = await Future.wait(futures);

        for (final count in results) {
          deleted += count;
        }

        // ====================================================
        // UPDATE PROGRESS
        // ====================================================

        if (mounted) {
          setState(() {
            processedItems = deleted;

            totalItems = total;

            currentBatch = (deleted / batchSize).ceil();

            totalBatches = chunks.length;

            progress = (deleted / total).clamp(0.0, 1.0);

            currentStage = "Removing old inventory...";

            status =
                "Removing old inventory...\n"
                "$deleted / $total";
          });
        }

        debugPrint(
          "DELETE PROGRESS: "
          "$deleted / $total",
        );
      }

      // ======================================================
      // FINISHED
      // ======================================================

      debugPrint("=================================");

      debugPrint(
        "OLD INVENTORY DELETE FINISHED: "
        "$deleted",
      );

      debugPrint("=================================");

      if (mounted) {
        setState(() {
          currentStage = "Old inventory removed";

          status =
              "Old inventory removed\n"
              "$deleted documents deleted";

          progress = 1.0;

          processedItems = deleted;

          totalItems = total;
        });
      }

      return deleted;
    } catch (e, stackTrace) {
      debugPrint("=================================");

      debugPrint("DELETE OLD INVENTORY FAILED");

      debugPrint("ERROR: $e");

      debugPrint("STACK TRACE:");

      debugPrint(stackTrace.toString());

      debugPrint("=================================");

      rethrow;
    }
  }

  // ============================================================
  // DELETE ONE BATCH
  // ============================================================

  Future<int> _deleteInventoryBatch(
    FirebaseFirestore db,
    List<QueryDocumentSnapshot> docs,
    int batchNumber,
    int totalBatches,
  ) async {
    debugPrint(
      "START DELETE BATCH "
      "$batchNumber/$totalBatches "
      "(${docs.length} docs)",
    );

    // IMPORTANT:
    // Create the batch ONCE.
    //
    // If commit times out and we retry,
    // we use the same document references.
    // Delete is therefore safe/idempotent.

    final batch = db.batch();

    for (final doc in docs) {
      batch.delete(doc.reference);
    }

    await _commitBatchWithRetry(batch, "DELETE", batchNumber, totalBatches);

    debugPrint(
      "DELETE BATCH "
      "$batchNumber/$totalBatches "
      "COMPLETED "
      "(${docs.length} docs)",
    );

    return docs.length;
  }

  // ============================================================
  // UPLOAD NEW INVENTORY
  // ============================================================

  Future<int> uploadNewInventory(
    FirebaseFirestore db,
    CollectionReference inventoryRef,
    List<Map<String, dynamic>> items,
  ) async {
    final total = items.length;

    if (total == 0) {
      return 0;
    }

    final chunks = _splitIntoChunks(items, batchSize);

    totalBatches = chunks.length;

    int uploaded = 0;

    // ========================================================
    // UPLOAD
    // ========================================================

    for (int start = 0; start < chunks.length; start += parallelBatches) {
      final end = (start + parallelBatches < chunks.length)
          ? start + parallelBatches
          : chunks.length;

      final currentChunks = chunks.sublist(start, end);

      debugPrint("=================================");

      debugPrint(
        "START UPLOAD GROUP "
        "${start + 1}-$end / "
        "${chunks.length}",
      );

      debugPrint("=================================");

      final futures = <Future<int>>[];

      for (int i = 0; i < currentChunks.length; i++) {
        final chunk = currentChunks[i];

        final batchNumber = start + i + 1;

        futures.add(
          _uploadInventoryBatch(
            db,
            inventoryRef,
            chunk,
            batchNumber,
            chunks.length,
          ),
        );
      }

      final results = await Future.wait(futures);

      for (final count in results) {
        uploaded += count;
      }

      // ======================================================
      // PROGRESS
      // ======================================================

      if (mounted) {
        setState(() {
          processedItems = uploaded;

          totalItems = total;

          currentBatch = (uploaded / batchSize).ceil();

          totalBatches = chunks.length;

          progress = (uploaded / total).clamp(0.0, 1.0);

          currentStage = "Uploading inventory...";

          status =
              "Uploading inventory...\n"
              "$uploaded / $total";
        });
      }

      debugPrint(
        "UPLOAD PROGRESS: "
        "$uploaded / $total",
      );
    }

    debugPrint("=================================");

    debugPrint("UPLOAD FINISHED: $uploaded");

    debugPrint("=================================");

    return uploaded;
  }

  // ============================================================
  // UPLOAD ONE BATCH
  // ============================================================

  Future<int> _uploadInventoryBatch(
    FirebaseFirestore db,
    CollectionReference inventoryRef,
    List<Map<String, dynamic>> items,
    int batchNumber,
    int totalBatches,
  ) async {
    debugPrint(
      "START UPLOAD BATCH "
      "$batchNumber/$totalBatches "
      "(${items.length} docs)",
    );

    // IMPORTANT:
    // Document IDs are generated ONCE.
    //
    // If commit times out and retry happens,
    // the exact same document references
    // are used again.
    //
    // This prevents duplicate documents.

    final batch = db.batch();

    for (final item in items) {
      final docRef = inventoryRef.doc();

      batch.set(docRef, {
        "name": item["name"].toString(),

        "price": item["price"],

        "active": true,

        "updatedAt": FieldValue.serverTimestamp(),
      });
    }

    await _commitBatchWithRetry(batch, "UPLOAD", batchNumber, totalBatches);

    debugPrint(
      "UPLOAD BATCH "
      "$batchNumber/$totalBatches "
      "COMPLETED "
      "(${items.length} docs)",
    );

    return items.length;
  }

  // ============================================================
  // VERIFY FIREBASE WITH RETRY
  // ============================================================

  Future<int> _verifyInventory(CollectionReference inventoryRef) async {
    Object? lastError;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint(
          "VERIFY INVENTORY "
          "ATTEMPT $attempt/$maxRetries",
        );

        final snapshot = await inventoryRef.get().timeout(firebaseTimeout);

        return snapshot.docs.length;
      } catch (e) {
        lastError = e;

        debugPrint("VERIFY FAILED: $e");

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 5));
        }
      }
    }

    throw Exception(
      "Firebase verification failed "
      "after $maxRetries attempts.\n"
      "Last error: $lastError",
    );
  }

  // ============================================================
  // MAIN UPLOAD
  // ============================================================

  Future<void> uploadInventory() async {
    if (uploading) {
      return;
    }

    try {
      // ======================================================
      // PICK FILE
      // ======================================================

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

      debugPrint("=================================");

      debugPrint("OPENING STORE INVENTORY");

      debugPrint(
        "STORE CODE = "
        "${widget.storeCode}",
      );

      debugPrint(
        "FILE NAME = "
        "${file.name}",
      );

      debugPrint(
        "FILE EXTENSION = "
        "$extension",
      );

      debugPrint(
        "INVENTORY PATH = "
        "stores/${widget.storeCode}/inventory",
      );

      debugPrint("=================================");

      // ======================================================
      // READ FILE
      // ======================================================

      List<List<String>> rows;

      if (extension == "pdf") {
        rows = await convertPdfToRows(filePath);
      } else if (extension == "csv") {
        if (mounted) {
          setState(() {
            currentStage = "Reading CSV...";

            status = "Reading CSV...";

            progress = 0;
          });
        }

        final csvText = await File(filePath).readAsString(encoding: utf8);

        rows = readCsv(csvText);
      } else {
        if (mounted) {
          setState(() {
            currentStage = "Reading Excel...";

            status = "Reading Excel...";

            progress = 0;
          });
        }

        Uint8List? bytes = file.bytes;

        if (bytes == null || bytes.isEmpty) {
          bytes = await File(filePath).readAsBytes();
        }

        if (bytes.isEmpty) {
          throw Exception("Could not read Excel file.");
        }

        rows = await readExcel(bytes);
      }

      // ======================================================
      // CHECK ROWS
      // ======================================================

      debugPrint("=================================");

      debugPrint(
        "ROWS EXTRACTED: "
        "${rows.length}",
      );

      if (rows.isNotEmpty) {
        debugPrint(
          "FIRST ROW: "
          "${rows.first}",
        );
      }

      if (rows.length > 1) {
        debugPrint(
          "SECOND ROW: "
          "${rows[1]}",
        );
      }

      debugPrint("=================================");

      if (rows.isEmpty) {
        throw Exception("No rows were extracted from the file.");
      }

      // ======================================================
      // EXTRACT ITEMS
      // ======================================================

      if (mounted) {
        setState(() {
          currentStage = "Detecting item names and prices...";

          status = "Detecting item names and prices...";

          progress = 0;
        });
      }

      final items = extractItems(rows);

      // ======================================================
      // SAFETY CHECK
      // ======================================================

      if (items.isEmpty) {
        throw Exception(
          "No valid items found.\n\n"
          "The file must contain an item name "
          "and a price.",
        );
      }

      if (rows.length > 100 && items.length < 10) {
        throw Exception(
          "Extraction failed.\n\n"
          "Rows extracted: "
          "${rows.length}\n"
          "Valid items: "
          "${items.length}\n\n"
          "Old Firebase inventory "
          "was NOT deleted.",
        );
      }

      debugPrint("=================================");

      debugPrint(
        "ITEMS READY FOR FIREBASE: "
        "${items.length}",
      );

      debugPrint("=================================");

      // ======================================================
      // FIREBASE
      // ======================================================

      final db = FirebaseFirestore.instance;

      final storeRef = db.collection("stores").doc(widget.storeCode);

      final inventoryRef = storeRef.collection("inventory");

      // ======================================================
      // DELETE OLD
      // ======================================================

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

      final deleted = await deleteOldInventory(db, inventoryRef);

      debugPrint(
        "OLD DOCUMENTS DELETED: "
        "$deleted",
      );

      // ======================================================
      // UPLOAD NEW
      // ======================================================

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

      final uploaded = await uploadNewInventory(db, inventoryRef, items);

      // ======================================================
      // CHECK UPLOAD COUNT
      // ======================================================

      if (uploaded != items.length) {
        throw Exception(
          "Upload count mismatch.\n"
          "Expected: "
          "${items.length}\n"
          "Uploaded: "
          "$uploaded",
        );
      }

      // ======================================================
      // UPDATE STORE
      // ======================================================

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

      // ======================================================
      // FINAL VERIFICATION
      // ======================================================

      if (mounted) {
        setState(() {
          currentStage = "Verifying inventory...";

          status = "Verifying Firebase inventory...";

          progress = 0.99;
        });
      }

      final firebaseCount = await _verifyInventory(inventoryRef);

      debugPrint("=================================");

      debugPrint("FIREBASE VERIFICATION");

      debugPrint(
        "EXPECTED: "
        "${items.length}",
      );

      debugPrint(
        "FIREBASE: "
        "$firebaseCount",
      );

      debugPrint("=================================");

      if (firebaseCount != items.length) {
        throw Exception(
          "Firebase verification failed.\n"
          "Expected: ${items.length}\n"
          "Firebase: $firebaseCount",
        );
      }

      // ======================================================
      // SUCCESS
      // ======================================================

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
            "Firebase documents: "
            "$firebaseCount";
      });

      debugPrint("=================================");

      debugPrint("STORE INVENTORY UPLOAD SUCCESS");

      debugPrint(
        "UPLOADED ITEMS: "
        "${items.length}",
      );

      debugPrint(
        "FIREBASE DOCUMENTS: "
        "$firebaseCount",
      );

      debugPrint(
        "FIREBASE PATH: "
        "stores/${widget.storeCode}/inventory",
      );

      debugPrint(
        "FIELDS: "
        "name + price + active + updatedAt",
      );

      debugPrint("QTY FIELD: NOT STORED");

      debugPrint("=================================");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "تم تحديث المخزون بنجاح ✔\n"
            "عدد الأصناف: "
            "${items.length}",
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
          content: Text(
            "حدث خطأ أثناء رفع المخزون:\n"
            "$e",
          ),
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
                  "Store: "
                  "${widget.storeCode}",
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
                    "$processedItems / "
                    "$totalItems",
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

                  Text(
                    "Excel / PDF / CSV",
                    style: TextStyle(color: Colors.grey),
                  ),

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

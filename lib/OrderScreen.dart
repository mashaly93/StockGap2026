import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'matcher.dart';

class OrderScreen extends StatefulWidget {
  static const routeName = "orderScreen";

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  List<List<String>> inventoryRows = [];
  List<List<String>> orderRows = [];

  Uint8List? generatedFileBytes;

  String? inventoryFileName;
  String? orderFileName;

  String statusText = "";

  List<List<String>> excelToRows(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) return [];

    final table = excel.tables.values.first;

    return table.rows
        .map((row) => row.map((e) => e?.value.toString() ?? "").toList())
        .toList();
  }

  Future<List<List<String>>> processFile(File file) async {
    final path = file.path.toLowerCase();

    if (path.endsWith(".xlsx")) {
      final bytes = await file.readAsBytes();
      return excelToRows(bytes);
    }

    if (path.endsWith(".pdf")) {
      final csv = await convertPdfToCsv(file);
      return await csvToRows(csv);
    }

    throw Exception("Only Excel or PDF files are supported.");
  }

  Future<void> pickInventory() async {
    final type = XTypeGroup(
      label: "Files",
      extensions: ["xlsx", "pdf"],
    );

    final xfile = await openFile(acceptedTypeGroups: [type]);

    if (xfile == null) return;

    inventoryRows = await processFile(File(xfile.path));
    inventoryFileName = xfile.name;

    setState(() {});
  }

  Future<void> pickOrder() async {
    final type = XTypeGroup(
      label: "Files",
      extensions: ["xlsx", "pdf"],
    );

    final xfile = await openFile(acceptedTypeGroups: [type]);

    if (xfile == null) return;

    orderRows = await processFile(File(xfile.path));
    orderFileName = xfile.name;

    setState(() {});
  }

  Future<void> generateOrder() async {
    if (inventoryRows.isEmpty || orderRows.isEmpty) {
      setState(() {
        statusText = "Please select both files.";
      });
      return;
    }

    setState(() {
      statusText = "Processing...";
    });

    List<String> storeItems = [];

    for (int i = 1; i < orderRows.length; i++) {
      final row = orderRows[i];

      if (row.isEmpty) continue;

      String item = Matcher.normalize(row[0]);
      item = item.replaceAll(RegExp(r'\d+'), '').trim();

      if (item.isNotEmpty) {
        storeItems.add(item);
      }
    }

    final excel = Excel.createExcel();

    final resultSheet = excel['Sheet1'];
    final missingSheet = excel['Missing'];

    resultSheet.appendRow([
      TextCellValue("Item"),
      TextCellValue("Qty"),
      TextCellValue("Matched Item"),
      TextCellValue("Score"),
    ]);

    missingSheet.appendRow([
      TextCellValue("Item"),
      TextCellValue("Qty"),
    ]);

    for (int i = 1; i < inventoryRows.length; i++) {
      final row = inventoryRows[i];

      if (row.isEmpty) continue;

      String item = Matcher.normalize(row[0]);
      item = item.replaceAll(RegExp(r'\d+'), '').trim();

      int qty = 0;

      if (row.length > 1) {
        qty =
            int.tryParse(row[1].replaceAll(RegExp(r'[^0-9]'), "")) ?? 0;
      }

      final result = Matcher.findBestMatch(item, storeItems);

      if (result.matchedItem != null && result.score >= 60) {
        resultSheet.appendRow([
          TextCellValue(item),
          TextCellValue(qty.toString()),
          TextCellValue(result.matchedItem!),
          TextCellValue("${result.score.toStringAsFixed(0)}%"),
        ]);
      } else {
        missingSheet.appendRow([
          TextCellValue(item),
          TextCellValue(qty.toString()),
        ]);
      }
    }

    generatedFileBytes = Uint8List.fromList(excel.encode()!);

    setState(() {
      statusText = "Done ✔";
    });
  }
  // =========================
  // 💾 DOWNLOAD (WINDOWS SAFE)
  // =========================
  Future<void> downloadFile(Uint8List bytes) async {
    final location = await getSaveLocation(
      suggestedName: "final_order.xlsx",
    );

    if (location == null) return;

    final file = File(location.path);
    await file.writeAsBytes(bytes);

    setState(() {
      statusText = "Saved Successfully ✔";
    });
  }

  // =========================
  // 📄 PDF → CSV (Windows only)
  // =========================
  Future<File> convertPdfToCsv(File pdfFile) async {
    final outputPath = "${pdfFile.path}.csv";

    final result = await Process.run(
      "java",
      [
        "-jar",
        "tools/tabula.jar",
        "--pages",
        "all",
        "--format",
        "CSV",
        pdfFile.path,
        "--outfile",
        outputPath,
      ],
    );

    if (result.exitCode != 0) {
      throw Exception("PDF conversion failed: ${result.stderr}");
    }

    return File(outputPath);
  }

  // =========================
  // 📄 CSV READER
  // =========================
  Future<List<List<String>>> csvToRows(File file) async {
    final text = await file.readAsString();

    return text
        .split("\n")
        .where((e) => e.trim().isNotEmpty)
        .map((line) => line
        .split(",")
        .map((e) => e.replaceAll('"', '').trim())
        .toList())
        .toList();
  }

  // =========================
  // 🖥️ UI
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 80),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: pickInventory,
                    child: Text(
                      inventoryFileName ?? "Upload Inventory",
                    ),
                  ),
                ),

                const SizedBox(width: 20),

                Expanded(
                  child: ElevatedButton(
                    onPressed: pickOrder,
                    child: Text(
                      orderFileName ?? "Upload Order",
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),

            ElevatedButton(
              onPressed: generateOrder,
              child: const Text("Generate Order"),
            ),

            const SizedBox(height: 20),

            if (generatedFileBytes != null)
              ElevatedButton.icon(
                onPressed: () => downloadFile(generatedFileBytes!),
                icon: const Icon(Icons.download),
                label: const Text("Save File"),
              ),

            const SizedBox(height: 20),

            Text(statusText),
          ],
        ),
      ),
    );
  }
}
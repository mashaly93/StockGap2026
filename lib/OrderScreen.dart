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
    try {
      final type = XTypeGroup(
        label: "Files",
        extensions: ["xlsx", "pdf"],
      );

      final xfile = await openFile(acceptedTypeGroups: [type]);

      if (xfile == null) return;

      inventoryRows = await processFile(File(xfile.path));
      inventoryFileName = xfile.name;

      setState(() {
        statusText = "Missing Items Loaded Successfully";
      });
    } catch (e) {
      setState(() {
        statusText = e.toString();
      });
    }
  }

  Future<void> pickOrder() async {
    try {
      final type = XTypeGroup(
        label: "Files",
        extensions: ["xlsx", "pdf"],
      );

      final xfile = await openFile(acceptedTypeGroups: [type]);

      if (xfile == null) return;

      orderRows = await processFile(File(xfile.path));
      orderFileName = xfile.name;


      setState(() {
        statusText = "Store List  Loaded Successfully";
      });
    } catch (e) {
      setState(() {
        statusText = e.toString();
      });
    }




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

    List<Map<String, String>> storeItems = [];


    for (int i = 1; i < orderRows.length; i++) {
      final row = orderRows[i];

      if (row.isEmpty) continue;

      String original = "";

// تجاهل الرقم الأول (code)
      for (int i = 1; i < row.length; i++) {
        final cell = row[i].trim();

        // وقف عند أول رقم (بداية الأسعار)
        if (RegExp(r'^\d+(\.\d+)?$').hasMatch(cell)) {
          break;
        }

        original += "$cell ";
      }

      original = original.trim();
      if (original.isEmpty) continue;

      storeItems.add({
        "original": original,
        "normalized": Matcher.normalize(original),
      });
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

      final originalItem = row[0].trim();
      final normalizedItem = Matcher.normalize(originalItem);

      int qty = 0;

      if (row.length > 1) {
        qty = int.tryParse(row[1].replaceAll(RegExp(r'[^0-9]'), "")) ?? 0;
      }

      final result = Matcher.findBestMatch(normalizedItem, storeItems);



      if (result.matchedItem != null && result.score >= 60) {
        resultSheet.appendRow([
          TextCellValue(originalItem),
          TextCellValue(qty.toString()),
          TextCellValue(result.matchedItem!),
          TextCellValue("${result.score.toStringAsFixed(0)}%"),
        ]);
      } else {
        missingSheet.appendRow([
          TextCellValue(originalItem),
          TextCellValue(qty.toString()),
        ]);
      }
    }

    generatedFileBytes = Uint8List.fromList(excel.encode()!);

    setState(() {
      statusText = "Done ✔";
    });
  }

  Future<void> downloadFile(Uint8List bytes) async {
    final location = await getSaveLocation(
      suggestedName: "final_order.xlsx",
    );

    if (location == null) return;

    final filePath = location.path.endsWith('.xlsx')
        ? location.path
        : '${location.path}.xlsx';

    final file = File(filePath);
    await file.writeAsBytes(bytes);

    setState(() {
      statusText = "Saved Successfully ✔";
    });


    await Process.run('cmd', ['/c', 'start', '', filePath]);
  }


  Future<File> convertPdfToCsv(File pdfFile) async {
    final outputPath = "${pdfFile.path}.csv";

    final result = await Process.run(
      "java",
      [
        "-jar",
        "tools/tabula.jar",
        "-p",
        "all",
        "-f",
        "CSV",
        "-o",
        outputPath,
        pdfFile.path,
      ],
    );

    print("STDOUT: ${result.stdout}");
    print("STDERR: ${result.stderr}");

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }

    return File(outputPath);
  }



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
                      inventoryFileName ?? "Upload Missing Items",
                    ),
                  ),
                ),

                const SizedBox(width: 20),

                Expanded(
                  child: ElevatedButton(
                    onPressed: pickOrder,
                    child: Text(
                      orderFileName ?? "Upload List",
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
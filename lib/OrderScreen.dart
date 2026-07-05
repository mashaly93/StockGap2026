import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'matcher.dart';

class OrderScreen extends StatefulWidget {
  static const routeName = "orderScreen";
   final String storeCode;
  const OrderScreen({
    super.key,
    required this.storeCode,
  });
  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  late final storeCode = widget.storeCode;
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
      final type = XTypeGroup(label: "Files", extensions: ["xlsx", "pdf"]);

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
      final type = XTypeGroup(label: "Files", extensions: ["xlsx", "pdf"]);

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

    // =========================
    // 1. تجهيز store items
    // =========================
    for (int i = 1; i < orderRows.length; i++) {
      final row = orderRows[i];

      if (row.isEmpty) continue;

      String original = "";

      for (int j = 1; j < row.length; j++) {
        final cell = row[j].trim();

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

    // =========================
    // 2. Excel setup
    // =========================
    final excel = Excel.createExcel();
    final resultSheet = excel['Sheet1'];
    final missingSheet = excel['Missing'];

    resultSheet.appendRow([
      TextCellValue("Item"),
      TextCellValue("Qty"),
      TextCellValue("Matched Item"),
      TextCellValue("Score"),
      TextCellValue("Price"),
      TextCellValue("Total"),
    ]);

    missingSheet.appendRow([
      TextCellValue("Item"),
      TextCellValue("Qty"),
    ]);

    // =========================
    // 3. استخراج الأسعار
    // =========================
    List<double> extractPrices(List<String> row) {
      final prices = <double>[];

      for (final cell in row) {
        final text = cell.toString().trim();

        // ❌ تجاهل النسب المئوية
        if (text.contains('%')) continue;

        // استخراج الرقم
        final cleaned = text
            .replaceAll(',', '')
            .replaceAll(RegExp(r'[^0-9.]'), '')
            .trim();

        final value = double.tryParse(cleaned);

        if (value == null) continue;

        // 🔥 فلترة مهمة جدًا
        if (value <= 0) continue;

        // ❌ استبعاد الأرقام الكبيرة اللي غالبًا totals
        if (value > 1000) continue;

        prices.add(value);
      }

      prices.sort();
      return prices;
    }

    // =========================
    // 4. Loop inventory
    // =========================
    for (int i = 1; i < inventoryRows.length; i++) {
      final row = inventoryRows[i];

      if (row.isEmpty) continue;

      final originalItem = row[0].trim();
      final normalizedItem = Matcher.normalize(originalItem);

      // qty
      int qty = 0;
      if (row.length > 1) {
        qty = int.tryParse(row[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      }

      // prices
      final prices = extractPrices(row);
      if (prices.isEmpty) continue;

      double price = prices.last; // أعلى سعر
      double total = price * qty;

      // match
      final result = Matcher.findBestMatch(normalizedItem, storeItems);

      if (result.matchedItem != null && result.score >= 60) {
        resultSheet.appendRow([
          TextCellValue(originalItem),
          TextCellValue(qty.toString()),
          TextCellValue(result.matchedItem!),
          TextCellValue("${result.score.toStringAsFixed(0)}%"),
          TextCellValue(price.toStringAsFixed(3)),
          TextCellValue(total.toStringAsFixed(3)),
        ]);
      } else {
        missingSheet.appendRow([
          TextCellValue(originalItem),
          TextCellValue(qty.toString()),
        ]);
      }
    }

    // =========================
    // 5. Save file bytes
    // =========================
    generatedFileBytes = Uint8List.fromList(excel.encode()!);

    setState(() {
      statusText = "Done ✔";
    });
  }

  Future<void> downloadFile(Uint8List bytes) async {
    final location = await getSaveLocation(suggestedName: "final_order.xlsx");

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

    final result = await Process.run("java", [
      "-jar",
      "tools/tabula.jar",
      "-p",
      "all",
      "-f",
      "CSV",
      "-o",
      outputPath,
      pdfFile.path,
    ]);

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
        .map(
          (line) =>
              line.split(",").map((e) => e.replaceAll('"', '').trim()).toList(),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
        icon: const Icon(Icons.arrow_back,color: Color(0xff0050c0),), // 👈 غيّر هنا
    onPressed: () {
    Navigator.pop(context);
    },
        ),
        backgroundColor: Colors.grey.shade100,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          "Stock Gap Generator",
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      backgroundColor: Colors.grey.shade100,
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 800,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),

                  const Text(
                    "Stock Gap Generator",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 40),

                  Row(
                    children: [
                      Expanded(
                        child: _buildUploadCard(
                          title: "Missing Items",
                          fileName: inventoryFileName,
                          icon: Icons.inventory,
                          onPressed: pickInventory,
                          iconColor: Color(0xff0050c0),
                        ),
                      ),

                      const SizedBox(width: 20),

                      Expanded(
                        child: _buildUploadCard(
                          title: "Price List",
                          fileName: orderFileName,
                          icon: Icons.receipt_long,
                          onPressed: pickOrder,
                          iconColor: Color(0xff0050c0),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  SizedBox(
                    height: 55,
                    width: double.infinity,
                    child: ElevatedButton.icon(



                      onPressed:
                          (inventoryFileName != null && orderFileName != null)
                          ? generateOrder
                          : null,
                      icon: Icon(
                        Icons.play_arrow,
                        color:
                            (inventoryFileName != null && orderFileName != null)
                            ? Colors.white
                            : Colors.white,
                      ),
                      label: const Text(
                        "Generate Order",
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:  Colors.green,

                        disabledBackgroundColor: Color(0xff0050c0),
                        foregroundColor: Color(0xff0050c0),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  if (generatedFileBytes != null)
                    SizedBox(
                      height: 55,
                      child: ElevatedButton.icon(
                        onPressed: () => downloadFile(generatedFileBytes!),
                        icon: const Icon(Icons.download,color:Color(0xff0050c0) ,),
                        label: Center(
                          child: const Text(
                            "Save Excel",
                            style: TextStyle(color: Color(0xff0050c0)),
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 30),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          statusText,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xff0050c0),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              storeCode,
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              "Date: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildUploadCard({
  required String title,
  required String? fileName,
  required IconData icon,
  required Color iconColor,
  required VoidCallback onPressed,
}) {
  final uploaded = fileName != null;

  return Card(
    elevation: 4,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(
            uploaded ? Icons.check_circle : icon,
            size: 50,
            color: uploaded ? Colors.green : Color(0xff0050c0),
          ),
          const SizedBox(height: 15),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            fileName ?? "No file selected",
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: onPressed,
            child: Text(
              uploaded ? "Change File" : "Upload",
              style: TextStyle(color: Color(0xff0050c0)),
            ),
          ),
        ],
      ),
    ),
  );
}

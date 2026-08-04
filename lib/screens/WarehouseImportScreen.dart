import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class WarehouseImportScreen extends StatefulWidget {
  final String storeCode;

  const WarehouseImportScreen({super.key, required this.storeCode});

  @override
  State<WarehouseImportScreen> createState() => _WarehouseImportScreenState();
}

class _WarehouseImportScreenState extends State<WarehouseImportScreen> {
  bool uploading = false;

  String status = "";

  // ==========================
  // Read Excel
  // ==========================

  Future<List<List<String>>> readExcel(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) return [];

    final sheet = excel.tables.values.first;

    return sheet.rows.map((row) {
      return row.map((cell) {
        return cell?.value.toString().trim() ?? "";
      }).toList();
    }).toList();
  }

  // ==========================
  // Import
  // ==========================

  Future<void> importInventory() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,

        allowedExtensions: ["xlsx", "xls"],

        withData: true,
      );

      if (result == null) return;

      setState(() {
        uploading = true;

        status = "Reading Excel...";
      });

      final bytes = result.files.first.bytes;

      if (bytes == null) throw Exception("File error");

      final rows = await readExcel(bytes);

      if (rows.length <= 1) throw Exception("Excel is empty");

      int count = 0;

      final db = FirebaseFirestore.instance;

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        if (row.length < 4) continue;

        final name = row[0].trim();

        if (name.isEmpty) continue;

        final qty = int.tryParse(row[1]) ?? 0;

        final purchasePrice = double.tryParse(row[2].replaceAll(",", "")) ?? 0;

        final salePrice = double.tryParse(row[3].replaceAll(",", "")) ?? 0;

        await db
            .collection("stores")
            .doc(widget.storeCode)
            .collection("inventory")
            .add({
              "name": name,

              "qty": qty,

              "purchasePrice": purchasePrice,

              "salePrice": salePrice,

              "active": true,

              "updatedAt": Timestamp.now(),
            });

        count++;

        setState(() {
          status = "Uploading $count items...";
        });
      }

      setState(() {
        uploading = false;

        status = "$count Items Uploaded ✔";
      });
    } catch (e) {
      setState(() {
        uploading = false;

        status = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Import Inventory")),

      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),

          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,

            children: [
              const Icon(Icons.inventory, size: 80, color: Color(0xff0050c0)),

              const SizedBox(height: 30),

              ElevatedButton.icon(
                onPressed: uploading ? null : importInventory,

                icon: uploading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Icon(Icons.upload_file),

                label: Text(uploading ? "Uploading..." : "Upload Excel"),
              ),

              const SizedBox(height: 30),

              Text(
                status,

                textAlign: TextAlign.center,

                style: const TextStyle(
                  fontWeight: FontWeight.bold,

                  color: Color(0xff0050c0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

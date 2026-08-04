import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
  bool loading = false;

  String status = "";

  Future<void> uploadInventory() async {
    try {
      setState(() {
        loading = true;
        status = "Reading file...";
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["xlsx"],
      );

      if (result == null) {
        setState(() {
          loading = false;
        });

        return;
      }

      final file = File(result.files.single.path!);

      final bytes = await file.readAsBytes();

      final excel = Excel.decodeBytes(bytes);

      if (excel.tables.isEmpty) {
        throw Exception("Empty Excel file");
      }

      final sheet = excel.tables.values.first;

      List<Map<String, dynamic>> items = [];

      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];

        if (row.isEmpty) continue;

        final name = row[0]?.value.toString().trim() ?? "";

        final qty =
            int.tryParse(
              row.length > 1 ? row[1]?.value.toString() ?? "0" : "0",
            ) ??
            0;

        if (name.isEmpty) continue;

        items.add({"name": name, "qty": qty});
      }

      setState(() {
        status = "Uploading ${items.length} items...";
      });

      final storeRef = FirebaseFirestore.instance
          .collection("stores")
          .doc(widget.storeCode);

      // تحديث بيانات المخزن بدون حذف بيانات الحساب

      await storeRef.set({
        "storeCode": widget.storeCode,

        "lastUpdated": FieldValue.serverTimestamp(),

        "itemsCount": items.length,
      }, SetOptions(merge: true));

      // حذف المخزون القديم

      final oldItems = await storeRef.collection("inventory").get();

      WriteBatch deleteBatch = FirebaseFirestore.instance.batch();

      for (final doc in oldItems.docs) {
        deleteBatch.delete(doc.reference);
      }

      await deleteBatch.commit();

      // إضافة المخزون الجديد

      WriteBatch batch = FirebaseFirestore.instance.batch();

      int counter = 0;

      for (final item in items) {
        final ref = storeRef.collection("inventory").doc();

        batch.set(ref, {"name": item["name"], "qty": item["qty"]});

        counter++;

        if (counter == 450) {
          await batch.commit();

          batch = FirebaseFirestore.instance.batch();

          counter = 0;
        }
      }

      if (counter > 0) {
        await batch.commit();
      }

      setState(() {
        loading = false;

        status = "Uploaded Successfully ✔";
      });
    } catch (e) {
      setState(() {
        loading = false;

        status = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Store Inventory")),

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Text(
              "Store : ${widget.storeCode}",

              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 30),

            ElevatedButton.icon(
              onPressed: loading ? null : uploadInventory,

              icon: const Icon(Icons.upload_file),

              label: Text(loading ? "Uploading..." : "Upload Inventory"),
            ),

            const SizedBox(height: 20),

            Text(status),
          ],
        ),
      ),

      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(15),

        child: Text(
          widget.expireDate != null
              ? "Valid Until: ${widget.expireDate!.toDate().day}/${widget.expireDate!.toDate().month}/${widget.expireDate!.toDate().year}"
              : "",

          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

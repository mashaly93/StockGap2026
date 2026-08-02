import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../service/drug_update_service.dart';

class ImportDrugScreen extends StatefulWidget {
  const ImportDrugScreen({super.key});

  @override
  State<ImportDrugScreen> createState() => _ImportDrugScreenState();
}

class _ImportDrugScreenState extends State<ImportDrugScreen> {
  bool loading = false;

  String status = "";

  final DrugUpdateService _updateService = DrugUpdateService();

  Future<void> importExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,

      allowedExtensions: ["xlsx", "xls"],
    );

    if (result == null) return;

    final file = File(result.files.single.path!);

    setState(() {
      loading = true;

      status = "Updating drugs...\nPlease wait";
    });

    try {
      final bytes = await file.readAsBytes();

      final count = await _updateService.updateExcel(bytes);

      setState(() {
        loading = false;

        status = "Finished ✔\n$count drugs updated";
      });
    } catch (e) {
      setState(() {
        loading = false;

        status = "Error:\n$e";
      });

      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Update Drug Excel")),

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            ElevatedButton.icon(
              onPressed: loading ? null : importExcel,

              icon: const Icon(Icons.upload_file),

              label: const Text("Select Excel"),
            ),

            const SizedBox(height: 20),

            if (loading) const CircularProgressIndicator(),

            const SizedBox(height: 20),

            Text(status, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

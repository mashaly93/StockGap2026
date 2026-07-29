import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../service/drug_import_service.dart';

class ImportDrugScreen extends StatefulWidget {
  const ImportDrugScreen({super.key});

  @override
  State<ImportDrugScreen> createState() => _ImportDrugScreenState();
}

class _ImportDrugScreenState extends State<ImportDrugScreen> {
  bool loading = false;

  String status = "";

  Future<void> importPdf() async {
    const typeGroup = XTypeGroup(label: "PDF", extensions: ["pdf"]);

    final file = await openFile(acceptedTypeGroups: [typeGroup]);

    if (file == null) return;

    if (!mounted) return;

    setState(() {
      loading = true;

      status = "Converting PDF...";
    });

    try {
      final csvFile = await convertPdfToCsv(File(file.path));

      if (!mounted) return;

      setState(() {
        status = "Creating Excel...";
      });

      final excelBytes = await csvToExcel(csvFile);

      if (!mounted) return;

      setState(() {
        status = "Uploading Firebase...";
      });

      final count = await DrugImportService().importExcel(excelBytes);

      if (!mounted) return;

      setState(() {
        status = "Done ✔\nUploaded $count drugs";
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        status = "Error: $e";
      });
    }

    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }

  Future<File> convertPdfToCsv(File pdfFile) async {
    final tempDir = Directory.systemTemp;

    final outputPath =
        "${tempDir.path}\\drugs_${DateTime.now().millisecondsSinceEpoch}.csv";

    final exeDir = File(Platform.resolvedExecutable).parent.path;

    final javaPath = "$exeDir\\jre\\bin\\java.exe";

    final tabulaPath = "$exeDir\\tools\\tabula.jar";

    final result = await Process.run(javaPath, [
      "-jar",

      tabulaPath,

      "-p",

      "all",

      "-f",

      "CSV",

      "-o",

      outputPath,

      pdfFile.path,
    ]);

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }

    return File(outputPath);
  }

  Future<Uint8List> csvToExcel(File csvFile) async {
    final text = await csvFile.readAsString();

    final excel = Excel.createExcel();

    final sheet = excel['Sheet1'];

    for (final line in text.split("\n")) {
      if (line.trim().isEmpty) continue;

      final cells = line
          .split(",")
          .map((e) => TextCellValue(e.replaceAll('"', '').trim()))
          .toList();

      sheet.appendRow(cells);
    }

    return Uint8List.fromList(excel.encode()!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Import Drug PDF")),

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            ElevatedButton.icon(
              onPressed: loading ? null : importPdf,

              icon: const Icon(Icons.picture_as_pdf),

              label: const Text("Select Drug PDF"),
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

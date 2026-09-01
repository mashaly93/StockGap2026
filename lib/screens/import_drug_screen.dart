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
  // STATE
  // ============================================================

  bool loading = false;

  String status = "";

  final DrugUpdateService _updateService = DrugUpdateService();

  // ============================================================
  // IMPORT EXCEL
  // ============================================================

  Future<void> importExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["xlsx", "xls"],
    );

    if (result == null) return;

    final filePath = result.files.single.path;

    if (filePath == null || filePath.isEmpty) {
      return;
    }

    final file = File(filePath);

    if (!mounted) return;

    setState(() {
      loading = true;

      status = "Updating drugs...\nPlease wait";
    });

    try {
      final bytes = await file.readAsBytes();

      final count = await _updateService.updateExcel(bytes);

      if (!mounted) return;

      setState(() {
        loading = false;

        status = "Finished ✔\n$count drugs updated";
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text("$count drugs updated successfully"),
            backgroundColor: omanGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(12),
          ),
        );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;

        status = "Error:\n$e";
      });

      debugPrint(e.toString());

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text("Failed to update drug database."),
            backgroundColor: omanRed,
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
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final bool hasStatus = status.trim().isNotEmpty;

    final bool success = status.startsWith("Finished");

    final bool error = status.startsWith("Error");

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
          "Update Drug Excel",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),

      body: Column(
        children: [
          // ======================================================
          // OMAN GREEN STRIPE
          // ======================================================

          Container(height: 5, color: omanGreen),

          // ======================================================
          // CONTENT
          // ======================================================
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),

                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),

                  child: Column(
                    children: [
                      // ==================================================
                      // MAIN CARD
                      // ==================================================

                      Card(
                        color: Colors.white,

                        elevation: 2,

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),

                          side: BorderSide(color: Colors.grey.shade200),
                        ),

                        child: Padding(
                          padding: const EdgeInsets.all(24),

                          child: Column(
                            children: [
                              // ========================================
                              // ICON
                              // ========================================

                              Container(
                                width: 90,
                                height: 90,

                                decoration: BoxDecoration(
                                  color: omanRed.withOpacity(0.08),

                                  shape: BoxShape.circle,

                                  border: Border.all(
                                    color: omanRed.withOpacity(0.12),
                                  ),
                                ),

                                child: const Icon(
                                  Icons.table_view_rounded,
                                  size: 46,
                                  color: omanRed,
                                ),
                              ),

                              const SizedBox(height: 18),

                              // ========================================
                              // TITLE
                              // ========================================
                              const Text(
                                "Update Drug Database",

                                textAlign: TextAlign.center,

                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                  color: textDark,
                                ),
                              ),

                              const SizedBox(height: 8),

                              // ========================================
                              // DESCRIPTION
                              // ========================================
                              Text(
                                "Select an Excel file to update "
                                "the drug database.",

                                textAlign: TextAlign.center,

                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: textGrey,
                                ),
                              ),

                              const SizedBox(height: 24),

                              // ========================================
                              // SELECT BUTTON
                              // ========================================
                              SizedBox(
                                width: double.infinity,

                                height: 52,

                                child: ElevatedButton.icon(
                                  onPressed: loading ? null : importExcel,

                                  icon: loading
                                      ? const SizedBox(
                                          width: 21,
                                          height: 21,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.upload_file_rounded),

                                  label: Text(
                                    loading ? "Updating..." : "Select Excel",

                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),

                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: omanRed,

                                    foregroundColor: Colors.white,

                                    disabledBackgroundColor:
                                        Colors.grey.shade400,

                                    disabledForegroundColor: Colors.white,

                                    elevation: 0,

                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 18),

                              // ========================================
                              // LOADING
                              // ========================================
                              if (loading)
                                Column(
                                  children: [
                                    const LinearProgressIndicator(
                                      color: omanGreen,
                                      backgroundColor: Color(0xffE8F2EC),
                                    ),

                                    const SizedBox(height: 12),

                                    Text(
                                      "Updating drugs...\n"
                                      "Please wait",

                                      textAlign: TextAlign.center,

                                      style: TextStyle(
                                        color: textGrey,
                                        fontSize: 13,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),

                              // ========================================
                              // STATUS
                              // ========================================
                              if (hasStatus && !loading)
                                Container(
                                  width: double.infinity,

                                  margin: const EdgeInsets.only(top: 6),

                                  padding: const EdgeInsets.all(14),

                                  decoration: BoxDecoration(
                                    color: success
                                        ? omanGreen.withOpacity(0.08)
                                        : error
                                        ? omanRed.withOpacity(0.08)
                                        : Colors.grey.withOpacity(0.08),

                                    borderRadius: BorderRadius.circular(12),

                                    border: Border.all(
                                      color: success
                                          ? omanGreen.withOpacity(0.18)
                                          : error
                                          ? omanRed.withOpacity(0.18)
                                          : Colors.grey.shade200,
                                    ),
                                  ),

                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,

                                    children: [
                                      Icon(
                                        success
                                            ? Icons.check_circle_rounded
                                            : error
                                            ? Icons.error_outline_rounded
                                            : Icons.info_outline_rounded,

                                        color: success ? omanGreen : omanRed,

                                        size: 23,
                                      ),

                                      const SizedBox(width: 10),

                                      Expanded(
                                        child: Text(
                                          status,

                                          style: TextStyle(
                                            color: success
                                                ? omanGreen
                                                : error
                                                ? omanRed
                                                : textDark,

                                            fontWeight: FontWeight.w600,

                                            height: 1.5,
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

                      const SizedBox(height: 16),

                      // ==================================================
                      // INFORMATION
                      // ==================================================
                      Container(
                        width: double.infinity,

                        padding: const EdgeInsets.all(14),

                        decoration: BoxDecoration(
                          color: Colors.white,

                          borderRadius: BorderRadius.circular(14),

                          border: Border.all(color: Colors.grey.shade200),
                        ),

                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Container(
                              width: 34,
                              height: 34,

                              decoration: BoxDecoration(
                                color: omanGreen.withOpacity(0.10),

                                borderRadius: BorderRadius.circular(9),
                              ),

                              child: const Icon(
                                Icons.info_outline_rounded,
                                size: 19,
                                color: omanGreen,
                              ),
                            ),

                            const SizedBox(width: 10),

                            Expanded(
                              child: Text(
                                "Supported files: .xlsx and .xls",

                                style: TextStyle(
                                  color: textGrey,
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ==================================================
                      // OMAN COLORS FOOTER
                      // ==================================================
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,

                        children: [
                          Container(
                            width: 45,
                            height: 4,
                            decoration: BoxDecoration(
                              color: omanRed,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),

                          const SizedBox(width: 5),

                          Container(
                            width: 45,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),

                              border: Border.all(color: Colors.grey.shade300),
                            ),
                          ),

                          const SizedBox(width: 5),

                          Container(
                            width: 45,
                            height: 4,
                            decoration: BoxDecoration(
                              color: omanGreen,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ],
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

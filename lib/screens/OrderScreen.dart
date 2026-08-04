import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'Homescreen.dart';
import 'history_screen.dart';
import '../matcher/matcher.dart';

class OrderScreen extends StatefulWidget {
  static const routeName = "orderScreen";

  final String storeCode;

  final Timestamp? expireDate;

  const OrderScreen({super.key, required this.storeCode, this.expireDate});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  late final storeCode = widget.storeCode;

  // Missing Items Excel

  List<List<String>> inventoryRows = [];

  // Warehouse Firebase Inventory

  List<List<String>> orderRows = [];

  Uint8List? generatedFileBytes;

  bool isGenerating = false;

  String? inventoryFileName;

  String statusText = "";

  // Warehouses

  List<Map<String, dynamic>> warehouses = [];

  String? selectedWarehouseId;

  bool loadingWarehouses = false;

  @override
  void initState() {
    super.initState();

    loadWarehouses();
  }

  // ==========================
  // Logout
  // ==========================

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove("username");

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,

      MaterialPageRoute(builder: (_) => Homescreen()),

      (route) => false,
    );
  }

  // ==========================
  // Load Warehouses
  // ==========================

  Future<void> loadWarehouses() async {
    setState(() {
      loadingWarehouses = true;
    });

    final snap = await FirebaseFirestore.instance
        .collection("stores")
        .where("role", isEqualTo: "store")
        .get();

    warehouses = snap.docs.map((doc) {
      final data = doc.data();

      return {"id": doc.id, "name": data["name"] ?? doc.id};
    }).toList();

    setState(() {
      loadingWarehouses = false;
    });
  }

  // ==========================
  // Load Warehouse Inventory
  // ==========================

  Future<void> loadWarehouseItems(String warehouseId) async {
    setState(() {
      statusText = "Loading warehouse inventory...";
    });

    final snap = await FirebaseFirestore.instance
        .collection("stores")
        .doc(warehouseId)
        .collection("inventory")
        .get();

    orderRows = snap.docs.map((doc) {
      final data = doc.data();

      return [
        data["name"]?.toString() ?? "",

        data["qty"]?.toString() ?? "0",

        data["purchasePrice"]?.toString() ?? "",

        data["salePrice"]?.toString() ?? "",
      ];
    }).toList();

    setState(() {
      statusText = "${orderRows.length} items loaded ✔";
    });
  }

  // ==========================
  // Excel Reader
  // ==========================

  List<List<String>> excelToRows(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) return [];

    final table = excel.tables.values.first;

    return table.rows.map((row) {
      return row.map((cell) {
        return cell?.value.toString() ?? "";
      }).toList();
    }).toList();
  }

  // ==========================
  // Upload Missing Items
  // ==========================

  Future<void> pickInventory() async {
    try {
      final type = XTypeGroup(label: "Excel", extensions: ["xlsx"]);

      final file = await openFile(acceptedTypeGroups: [type]);

      if (file == null) return;

      final bytes = await File(file.path).readAsBytes();

      inventoryRows = excelToRows(bytes);

      inventoryFileName = file.name;

      setState(() {
        statusText = "Missing Items Loaded Successfully ✔";
      });
    } catch (e) {
      setState(() {
        statusText = e.toString();
      });
    }
  }

  // ==========================
  // Generate Order
  // ==========================

  Future<void> generateOrder() async {
    if (inventoryRows.isEmpty || orderRows.isEmpty) {
      setState(() {
        statusText = "Upload Missing Items and select Warehouse";
      });

      return;
    }

    setState(() {
      isGenerating = true;

      statusText = "Processing...";
    });

    final excel = Excel.createExcel();

    final resultSheet = excel["Sheet1"];

    final missingSheet = excel["Missing"];

    resultSheet.appendRow([
      TextCellValue("Item"),

      TextCellValue("Qty"),

      TextCellValue("Matched Item"),

      TextCellValue("Purchase Price"),

      TextCellValue("Sale Price"),

      TextCellValue("Total"),
    ]);

    double totalSale = 0;

    // دمج الأصناف المتكررة

    final Map<String, dynamic> merged = {};

    for (int i = 1; i < inventoryRows.length; i++) {
      final row = inventoryRows[i];

      if (row.isEmpty) continue;

      String item = "";

      int qty = 0;

      for (final c in row) {
        if (RegExp(r'^\d+$').hasMatch(c.trim())) {
          qty = int.tryParse(c.trim()) ?? 0;

          break;
        }

        item += "$c ";
      }

      item = item.trim();

      if (item.isEmpty) continue;

      final key = Matcher.normalize(item);

      if (merged.containsKey(key)) {
        merged[key]["qty"] += qty;
      } else {
        merged[key] = {"item": item, "qty": qty};
      }
    }

    final similarItems = <Map<String, dynamic>>[];

    final notFound = <Map<String, dynamic>>[];

    for (final data in merged.values) {
      final item = data["item"];

      final qty = data["qty"];

      bool found = false;

      double best = 0;

      String bestItem = "";

      for (final warehouse in orderRows) {
        final warehouseItem = warehouse[0];

        final result = Matcher.findBestMatch(Matcher.normalize(item), [
          {
            "original": warehouseItem,

            "normalized": Matcher.normalize(warehouseItem),
          },
        ]);

        if (result.score > best) {
          best = result.score.toDouble();

          bestItem = warehouseItem;
        }

        if (result.score >= 60) {
          double purchase = 0;

          double sale = 0;

          double total = 0;

          if (warehouse.length >= 4) {
            purchase = double.tryParse(warehouse[2]) ?? 0;

            sale = double.tryParse(warehouse[3]) ?? 0;

            total = sale * qty;

            totalSale += total;
          }

          resultSheet.appendRow([
            TextCellValue(item),

            TextCellValue(qty.toString()),

            TextCellValue(warehouseItem),

            TextCellValue(purchase.toString()),

            TextCellValue(sale.toString()),

            TextCellValue(total.toString()),
          ]);

          found = true;

          break;
        }
      }

      if (!found) {
        final m = {
          "item": item,

          "qty": qty,

          "similar": bestItem,

          "score": best.toStringAsFixed(0),
        };

        if (best >= 40)
          similarItems.add(m);
        else
          notFound.add(m);
      }
    }
    // ==========================
    // Missing Sheet
    // ==========================

    missingSheet.appendRow([
      TextCellValue("Item"),

      TextCellValue("Qty"),

      TextCellValue("Similar Item"),

      TextCellValue("Match %"),
    ]);

    missingSheet.appendRow([TextCellValue("POSSIBLE MATCHES")]);

    for (final e in similarItems) {
      missingSheet.appendRow([
        TextCellValue(e["item"]),

        TextCellValue(e["qty"].toString()),

        TextCellValue(e["similar"]),

        TextCellValue("${e["score"]}%"),
      ]);
    }

    missingSheet.appendRow([]);

    missingSheet.appendRow([TextCellValue("NOT MATCHED ITEMS")]);

    for (final e in notFound) {
      missingSheet.appendRow([
        TextCellValue(e["item"]),

        TextCellValue(e["qty"].toString()),

        TextCellValue(e["similar"]),

        TextCellValue("${e["score"]}%"),
      ]);
    }

    resultSheet.appendRow([]);

    resultSheet.appendRow([
      TextCellValue(""),

      TextCellValue(""),

      TextCellValue("TOTAL"),

      TextCellValue(""),

      TextCellValue(""),

      TextCellValue(totalSale.toStringAsFixed(3)),
    ]);

    generatedFileBytes = Uint8List.fromList(excel.encode()!);

    setState(() {
      isGenerating = false;

      statusText = "Done ✔";
    });
  }

  // ==========================
  // Reset
  // ==========================

  void resetScreen() {
    setState(() {
      inventoryRows.clear();

      orderRows.clear();

      generatedFileBytes = null;

      inventoryFileName = null;

      selectedWarehouseId = null;

      statusText = "Ready";
    });
  }

  // ==========================
  // Save History
  // ==========================

  Future<void> saveOrderLocally({
    required String fileName,

    required String filePath,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final history = prefs.getStringList("orders") ?? [];

    final order = {
      "fileName": fileName,

      "filePath": filePath,

      "date": DateFormat("yyyy-MM-dd").format(DateTime.now()),

      "items": inventoryRows.length,
    };

    history.add(jsonEncode(order));

    await prefs.setStringList("orders", history);
  }

  // ==========================
  // Download Excel
  // ==========================

  Future<void> downloadFile(Uint8List bytes) async {
    final location = await getSaveLocation(suggestedName: "Order.xlsx");

    if (location == null) return;

    final path = location.path.endsWith(".xlsx")
        ? location.path
        : "${location.path}.xlsx";

    final file = File(path);

    await file.writeAsBytes(bytes);

    await saveOrderLocally(fileName: path.split("\\").last, filePath: path);

    setState(() {
      statusText = "Saved Successfully ✔";
    });

    await Process.run('cmd', ['/c', 'start', '', path]);

    resetScreen();
  }

  // ==========================
  // BUILD UI
  // ==========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,

      appBar: AppBar(
        backgroundColor: Colors.grey.shade100,

        elevation: 0,

        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xff0050c0)),

          onPressed: () {
            Navigator.pop(context);
          },
        ),

        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Color(0xff0050c0)),

            onPressed: () {
              Navigator.push(
                context,

                MaterialPageRoute(builder: (_) => HistoryScreen()),
              );
            },
          ),

          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xff0050c0)),

            onPressed: logout,
          ),
        ],
      ),

      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 800,

            child: Padding(
              padding: const EdgeInsets.all(24),

              child: Column(
                children: [
                  const Text(
                    "Stock Gap Generator",

                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 40),

                  _buildUploadCard(
                    title: "Missing Items",

                    fileName: inventoryFileName,

                    icon: Icons.inventory,

                    onPressed: pickInventory,
                  ),

                  const SizedBox(height: 25),

                  Card(
                    elevation: 4,

                    child: Padding(
                      padding: const EdgeInsets.all(20),

                      child: Column(
                        children: [
                          const Text(
                            "Select Warehouse",

                            style: TextStyle(
                              fontSize: 18,

                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 15),

                          loadingWarehouses
                              ? const CircularProgressIndicator()
                              : DropdownButtonFormField<String>(
                                  value: selectedWarehouseId,

                                  hint: const Text("Choose Warehouse"),

                                  items: warehouses.map((w) {
                                    return DropdownMenuItem<String>(
                                      value: w["id"],

                                      child: Text(w["name"]),
                                    );
                                  }).toList(),

                                  onChanged: (value) async {
                                    if (value == null) return;

                                    setState(() {
                                      selectedWarehouseId = value;
                                    });

                                    await loadWarehouseItems(value);
                                  },
                                ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  SizedBox(
                    width: double.infinity,

                    height: 55,

                    child: ElevatedButton.icon(
                      onPressed:
                          inventoryRows.isNotEmpty &&
                              orderRows.isNotEmpty &&
                              !isGenerating
                          ? generateOrder
                          : null,

                      icon: isGenerating
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Icon(Icons.play_arrow),

                      label: Text(
                        isGenerating ? "Processing..." : "Generate Order",
                      ),

                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,

                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  if (generatedFileBytes != null)
                    ElevatedButton.icon(
                      onPressed: () => downloadFile(generatedFileBytes!),

                      icon: const Icon(Icons.download),

                      label: const Text("Save Excel"),
                    ),

                  const SizedBox(height: 20),

                  Text(
                    statusText,

                    style: const TextStyle(
                      color: Color(0xff0050c0),

                      fontWeight: FontWeight.bold,
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

  Widget _buildUploadCard({
    required String title,

    required String? fileName,

    required IconData icon,

    required VoidCallback onPressed,
  }) {
    return Card(
      elevation: 4,

      child: Padding(
        padding: const EdgeInsets.all(20),

        child: Row(
          children: [
            Icon(
              fileName != null ? Icons.check_circle : icon,
              size: 50,
              color: fileName != null
                  ? Colors.green
                  : const Color(0xff0050c0),
            ),

            const SizedBox(width: 20),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    fileName ?? "No file selected",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 15),

            ElevatedButton(
              onPressed: onPressed,
              child: Text(
                fileName == null ? "Upload" : "Change",
              ),
            ),
          ],
        ),
      ),
    );
  }
}

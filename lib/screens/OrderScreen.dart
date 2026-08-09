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
  State createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  late final String storeCode = widget.storeCode;

  // ==========================
  // Pharmacy Missing Items
  // ==========================

  List<List<String>> inventoryRows = [];

  // ==========================
  // Warehouse Firebase Inventory
  // ==========================

  List<List<String>> orderRows = [];

  Uint8List? generatedFileBytes;

  bool isGenerating = false;

  String? inventoryFileName;

  String statusText = "";

  // ==========================
  // Warehouses
  // ==========================

  List<Map<String, dynamic>> warehouses = [];

  String? selectedWarehouseId;

  bool loadingWarehouses = false;

  // ==========================
  // INIT
  // ==========================

  @override
  void initState() {
    super.initState();

    loadWarehouses();
  }

  // ==========================
  // Logout
  // ==========================

  Future logout() async {
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

  Future loadWarehouses() async {
    if (!mounted) return;

    setState(() {
      loadingWarehouses = true;
      statusText = "Loading warehouses...";
    });

    try {
      debugPrint("=================================");
      debugPrint("LOADING WAREHOUSES");
      debugPrint("=================================");

      final snap = await FirebaseFirestore.instance
          .collection("stores")
          .where("role", isEqualTo: "store")
          .get();

      debugPrint("Warehouse documents found: ${snap.docs.length}");

      final loadedWarehouses = <Map<String, dynamic>>[];

      for (final doc in snap.docs) {
        final data = doc.data();


        final name = data["name"]?.toString().trim() ?? "";

        loadedWarehouses.add({
          "id": doc.id,
          "name": name.isNotEmpty ? name : doc.id,
        });
      }



      if (!mounted) return;

      setState(() {
        warehouses = loadedWarehouses;
        loadingWarehouses = false;

        statusText = loadedWarehouses.isEmpty ? "No warehouses found." : "";
      });
    } catch (e, stackTrace) {


      if (!mounted) return;

      setState(() {
        loadingWarehouses = false;
        statusText = "Failed to load warehouses:\n$e";
      });
    }
  }

  // ==========================
  // Load Warehouse Inventory
  // ==========================

  Future loadWarehouseItems(String warehouseId) async {
    if (!mounted) return;

    setState(() {
      orderRows.clear();
      statusText = "Loading warehouse inventory...";
    });

    try {
      debugPrint("=================================");
      debugPrint("LOADING WAREHOUSE INVENTORY");
      debugPrint("Warehouse ID: $warehouseId");
      debugPrint("=================================");

      final inventoryRef = FirebaseFirestore.instance
          .collection("stores")
          .doc(warehouseId)
          .collection("inventory");

      final snap = await inventoryRef.get();

      debugPrint("Inventory documents found: ${snap.docs.length}");

      final loadedRows = <List<String>>[];

      for (final doc in snap.docs) {
        final data = doc.data();

        debugPrint("---------------------------------");
        debugPrint("Inventory ID: ${doc.id}");
        debugPrint("Inventory data: $data");

        // ==========================
        // Item Name
        // ==========================

        final name = data["name"]?.toString().trim() ?? "";

        if (name.isEmpty) {
          debugPrint("Skipped ${doc.id}: name is empty");
          continue;
        }

        // ==========================
        // PRICE
        // ==========================

        double price = 0;

        final rawPrice = data["price"];

        if (rawPrice is num) {
          price = rawPrice.toDouble();
        } else {
          price =
              double.tryParse(
                rawPrice?.toString().replaceAll(",", "").trim() ?? "",
              ) ??
              0;
        }

        debugPrint("ITEM: $name | PRICE: $price");

        // ==========================
        // Warehouse Row
        // ==========================
        //
        // [0] Item
        // [1] Qty - not used
        // [2] Purchase Price
        // [3] Sale Price
        //

        loadedRows.add([name, "0", price.toString(), price.toString()]);
      }

      debugPrint("---------------------------------");
      debugPrint("Warehouse items loaded: ${loadedRows.length}");

      if (loadedRows.isNotEmpty) {
        debugPrint("First warehouse item: ${loadedRows.first}");
      }

      debugPrint("=================================");

      if (!mounted) return;

      setState(() {
        orderRows = loadedRows;

        statusText = "${orderRows.length} warehouse items loaded ✔";
      });
    } catch (e, stackTrace) {
      debugPrint("=================================");
      debugPrint("FAILED TO LOAD WAREHOUSE INVENTORY");
      debugPrint("Error: $e");
      debugPrint("StackTrace: $stackTrace");
      debugPrint("=================================");

      if (!mounted) return;

      setState(() {
        orderRows.clear();

        statusText = "Failed to load warehouse inventory:\n$e";
      });
    }
  }

  // ==========================
  // Excel Reader
  // ==========================

  List<List<String>> excelToRows(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) {
      return [];
    }

    final table = excel.tables.values.first;

    return table.rows.map((row) {
      return row.map((cell) {
        return cell?.value.toString().trim() ?? "";
      }).toList();
    }).toList();
  }

  // ==========================
  // Pick Missing Items
  // ==========================

  Future pickInventory() async {
    try {
      final type = XTypeGroup(label: "Excel", extensions: ["xlsx"]);

      final file = await openFile(acceptedTypeGroups: [type]);

      if (file == null) return;

      final bytes = await File(file.path).readAsBytes();

      final rows = excelToRows(bytes);

      if (rows.length <= 1) {
        throw Exception("Excel file is empty.");
      }

      debugPrint("=================================");
      debugPrint("MISSING FILE LOADED");
      debugPrint("File: ${file.name}");
      debugPrint("Rows: ${rows.length}");
      debugPrint("=================================");

      for (int i = 0; i < rows.length && i < 5; i++) {
        debugPrint("ROW $i: ${rows[i]}");
      }

      if (!mounted) return;

      setState(() {
        inventoryRows = rows;

        inventoryFileName = file.name;

        generatedFileBytes = null;

        statusText = "Missing Items Loaded Successfully ✔";
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        statusText = "Failed to read Excel:\n$e";
      });
    }
  }

  // ==========================
  // Find Qty Column
  // ==========================

  int findQtyColumn(List<String> header) {
    for (int i = 0; i < header.length; i++) {
      final value = header[i]
          .toString()
          .trim()
          .toLowerCase()
          .replaceAll("_", " ")
          .replaceAll("-", " ");

      if (value == "qty" ||
          value == "quantity" ||
          value == "quantities" ||
          value == "required qty" ||
          value == "required quantity" ||
          value == "order qty" ||
          value == "order quantity") {
        return i;
      }
    }

    return -1;
  }

  // ==========================
  // Extract Missing Items
  // ==========================
  //
  // IMPORTANT:
  //
  // We NEVER search for a number inside
  // the Item name.
  //
  // The Qty is taken from the Qty column.
  //
  // If there is no Qty header:
  // first column = Item
  // second column = Qty
  //

  Map<String, Map<String, dynamic>> buildMergedMissingItems() {
    final Map<String, Map<String, dynamic>> merged = {};

    if (inventoryRows.isEmpty) {
      return merged;
    }

    // ==========================
    // Detect Qty Header
    // ==========================

    final header = inventoryRows.first;

    int qtyColumnIndex = findQtyColumn(header);

    debugPrint("=================================");
    debugPrint("MISSING FILE ANALYSIS");
    debugPrint("Header: $header");
    debugPrint("Detected Qty Column: $qtyColumnIndex");
    debugPrint("=================================");

    // ==========================
    // Process Rows
    // ==========================

    for (int i = 1; i < inventoryRows.length; i++) {
      final row = inventoryRows[i];

      if (row.isEmpty) {
        continue;
      }

      String item = "";
      int qty = 0;

      // ==================================================
      // CASE 1
      // Qty column was found from Header
      // ==================================================

      if (qtyColumnIndex >= 0 && qtyColumnIndex < row.length) {
        final qtyText = row[qtyColumnIndex].toString().trim().replaceAll(
          ",",
          "",
        );

        qty = int.tryParse(qtyText) ?? 0;

        final itemParts = <String>[];

        for (int x = 0; x < row.length; x++) {
          if (x == qtyColumnIndex) {
            continue;
          }

          final value = row[x].trim();

          if (value.isEmpty) {
            continue;
          }

          itemParts.add(value);
        }

        item = itemParts.join(" ").trim();
      }
      // ==================================================
      // CASE 2
      // No Qty header
      //
      // First column = Item
      // Second column = Qty
      // ==================================================
      else if (row.length >= 2) {
        item = row[0].trim();

        final qtyText = row[1].trim().replaceAll(",", "");

        qty = int.tryParse(qtyText) ?? 0;

        // لو فيه أعمدة إضافية تخص اسم الصنف
        if (row.length > 2) {
          final extraParts = <String>[];

          for (int x = 2; x < row.length; x++) {
            final value = row[x].trim();

            if (value.isNotEmpty) {
              extraParts.add(value);
            }
          }

          if (extraParts.isNotEmpty) {
            item = "$item ${extraParts.join(" ")}".trim();
          }
        }
      }

      // ==================================================
      // Invalid Row
      // ==================================================

      if (item.isEmpty) {
        debugPrint("SKIPPED ROW $i: Item is empty");
        continue;
      }

      // ==========================
      // Normalize Item
      // ==========================

      final key = Matcher.normalize(item);

      // ==========================
      // Merge Duplicate Items
      // ==========================

      if (merged.containsKey(key)) {
        merged[key]!["qty"] = (merged[key]!["qty"] as int) + qty;

        debugPrint("MERGED: $item | +$qty");
      } else {
        merged[key] = {"item": item, "qty": qty};

        debugPrint("MISSING ITEM: $item | QTY: $qty");
      }
    }

    debugPrint("=================================");
    debugPrint("MERGED MISSING ITEMS: ${merged.length}");
    debugPrint("=================================");

    for (final data in merged.values) {
      debugPrint("${data["item"]} | QTY = ${data["qty"]}");
    }

    return merged;
  }

  // ==========================
  // Generate Order
  // ==========================

  Future generateOrder() async {
    if (inventoryRows.isEmpty) {
      setState(() {
        statusText = "Please upload Missing Items first.";
      });

      return;
    }

    if (orderRows.isEmpty) {
      setState(() {
        statusText = "Please select a Warehouse first.";
      });

      return;
    }

    if (isGenerating) return;

    setState(() {
      isGenerating = true;
      statusText = "Processing order...";
      generatedFileBytes = null;
    });

    try {
      final excel = Excel.createExcel();

      final resultSheet = excel["Sheet1"];

      final missingSheet = excel["Missing"];

      // ==========================
      // Result Headers
      // ==========================

      resultSheet.appendRow([
        TextCellValue("Item"),
        TextCellValue("Qty"),
        TextCellValue("Matched Item"),
        TextCellValue("Purchase Price"),

        TextCellValue("Total"),
      ]);

      double totalSale = 0;

      // ==========================
      // Build Missing Items
      // ==========================

      final merged = buildMergedMissingItems();

      if (merged.isEmpty) {
        throw Exception("No valid items found in Missing file.");
      }

      // ==========================
      // Match Lists
      // ==========================

      final similarItems = <Map<String, dynamic>>[];

      final notFound = <Map<String, dynamic>>[];

      // ==========================
      // Match Every Item
      // ==========================

      int processed = 0;

      for (final data in merged.values) {
        final String item = data["item"].toString();

        final int qty = data["qty"] as int;

        bool found = false;

        double bestScore = 0;

        String bestItem = "";

        List<String>? bestWarehouse;

        // ==========================
        // Find BEST Match
        // ==========================

        for (final warehouse in orderRows) {
          if (warehouse.isEmpty) {
            continue;
          }

          final warehouseItem = warehouse[0].trim();

          if (warehouseItem.isEmpty) {
            continue;
          }

          final result = Matcher.findBestMatch(Matcher.normalize(item), [
            {
              "original": warehouseItem,
              "normalized": Matcher.normalize(warehouseItem),
            },
          ]);

          if (result.score > bestScore) {
            bestScore = result.score.toDouble();

            bestItem = warehouseItem;

            bestWarehouse = warehouse;
          }
        }

        // ==========================
        // Match >= 60
        // ==========================

        if (bestScore >= 60 && bestWarehouse != null) {
          final warehouse = bestWarehouse;

          double purchase = 0;

          double sale = 0;

          // ==========================
          // Purchase Price
          // ==========================

          if (warehouse.length >= 3) {
            purchase =
                double.tryParse(warehouse[2].replaceAll(",", "").trim()) ?? 0;
          }

          // ==========================
          // Sale Price
          // ==========================

          if (warehouse.length >= 4) {
            sale =
                double.tryParse(warehouse[3].replaceAll(",", "").trim()) ?? 0;
          }

          // ==========================
          // Total
          // ==========================

          final total = sale * qty;

          debugPrint(
            "MATCHED ITEM: $bestItem | "
            "SCORE: $bestScore | "
            "PURCHASE: $purchase | "
            "SALE: $sale | "
            "QTY: $qty | "
            "TOTAL: $total",
          );

          totalSale += total;

          resultSheet.appendRow([
            TextCellValue(item),
            TextCellValue(qty.toString()),
            TextCellValue(bestItem),
            TextCellValue(purchase.toStringAsFixed(3)),

            TextCellValue(total.toStringAsFixed(3)),
          ]);

          found = true;
        }

        // ==========================
        // Not Found
        // ==========================

        if (!found) {
          final matchData = {
            "item": item,
            "qty": qty,
            "similar": bestItem,
            "score": bestScore.toStringAsFixed(0),
          };

          if (bestScore >= 40) {
            similarItems.add(matchData);
          } else {
            notFound.add(matchData);
          }
        }

        processed++;

        if (mounted) {
          setState(() {
            statusText = "Processing $processed / ${merged.length}...";
          });
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

      // ==========================
      // Possible Matches
      // ==========================

      missingSheet.appendRow([TextCellValue("POSSIBLE MATCHES")]);

      for (final item in similarItems) {
        missingSheet.appendRow([
          TextCellValue(item["item"].toString()),
          TextCellValue(item["qty"].toString()),
          TextCellValue(item["similar"].toString()),
          TextCellValue("${item["score"]}%"),
        ]);
      }

      // ==========================
      // Empty Row
      // ==========================

      missingSheet.appendRow([]);

      // ==========================
      // Not Matched
      // ==========================

      missingSheet.appendRow([TextCellValue("NOT MATCHED ITEMS")]);

      missingSheet.appendRow([
        TextCellValue("Item"),
        TextCellValue("Qty"),
        TextCellValue("Similar Item"),
        TextCellValue("Match %"),
      ]);

      for (final item in notFound) {
        missingSheet.appendRow([
          TextCellValue(item["item"].toString()),
          TextCellValue(item["qty"].toString()),
          TextCellValue(item["similar"].toString()),
          TextCellValue("${item["score"]}%"),
        ]);
      }

      // ==========================
      // Total
      // ==========================

      resultSheet.appendRow([]);

      resultSheet.appendRow([
        TextCellValue(""),
        TextCellValue(""),
        TextCellValue("TOTAL"),
        TextCellValue(""),
        TextCellValue(""),
        TextCellValue(totalSale.toStringAsFixed(3)),
      ]);

      // ==========================
      // Generate Excel Bytes
      // ==========================

      final encoded = excel.encode();

      if (encoded == null) {
        throw Exception("Could not generate Excel file.");
      }

      generatedFileBytes = Uint8List.fromList(encoded);

      if (!mounted) return;

      setState(() {
        isGenerating = false;

        statusText = "Order generated successfully ✔";
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isGenerating = false;

        statusText = "Error generating order:\n$e";
      });
    }
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

  Future saveOrderLocally({
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
  // Save Generated Excel
  // ==========================

  Future downloadFile(Uint8List bytes) async {
    try {
      final location = await getSaveLocation(suggestedName: "Order.xlsx");

      if (location == null) {
        return;
      }

      final path = location.path.endsWith(".xlsx")
          ? location.path
          : "${location.path}.xlsx";

      final file = File(path);

      await file.writeAsBytes(bytes);

      final fileName = path.split(Platform.pathSeparator).last;

      await saveOrderLocally(fileName: fileName, filePath: path);

      if (!mounted) return;

      setState(() {
        statusText = "Saved Successfully ✔";
      });

      await Process.run('cmd', ['/c', 'start', '', path]);

      resetScreen();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        statusText = "Error saving file:\n$e";
      });
    }
  }

  // ==========================
  // BUILD
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

        title: const Text(
          "Stock Gap",
          style: TextStyle(
            color: Color(0xff0050c0),
            fontWeight: FontWeight.bold,
          ),
        ),

        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Color(0xff0050c0)),
            tooltip: "History",
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
          padding: const EdgeInsets.all(24),

          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),

            child: Column(
              children: [
                // ==================================================
                // TITLE
                // ==================================================
                const Text(
                  "Stock Gap Generator",
                  textAlign: TextAlign.center,

                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff0050c0),
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  "Upload missing items and select a warehouse",
                  textAlign: TextAlign.center,

                  style: TextStyle(color: Colors.grey, fontSize: 15),
                ),

                const SizedBox(height: 35),

                // ==================================================
                // UPLOAD + WAREHOUSE ROW
                // ==================================================
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isSmall = constraints.maxWidth < 750;

                    final uploadCard = _buildUploadCard(
                      title: "Missing Items",
                      fileName: inventoryFileName,
                      icon: Icons.inventory_2,
                      onPressed: pickInventory,
                    );

                    final warehouseCard = Card(
                      elevation: 4,

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),

                      child: Padding(
                        padding: const EdgeInsets.all(20),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Row(
                              children: [
                                Icon(
                                  selectedWarehouseId != null
                                      ? Icons.check_circle
                                      : Icons.warehouse,

                                  size: 50,

                                  color: selectedWarehouseId != null
                                      ? Colors.green
                                      : const Color(0xff0050c0),
                                ),

                                const SizedBox(width: 15),

                                const Expanded(
                                  child: Text(
                                    "Select Warehouse",

                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),

                            loadingWarehouses
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : DropdownButtonFormField<String>(
                                    value: selectedWarehouseId,

                                    isExpanded: true,

                                    decoration: InputDecoration(
                                      labelText: "Warehouse",

                                      prefixIcon: const Icon(
                                        Icons.warehouse,
                                        color: Color(0xff0050c0),
                                      ),

                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),

                                    hint: const Text("Choose Warehouse"),

                                    items: warehouses.map((warehouse) {
                                      return DropdownMenuItem<String>(
                                        value: warehouse["id"].toString(),

                                        child: Text(
                                          warehouse["name"].toString(),

                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),

                                    onChanged: (value) async {
                                      if (value == null) {
                                        return;
                                      }

                                      setState(() {
                                        selectedWarehouseId = value;

                                        orderRows.clear();

                                        statusText =
                                            "Loading warehouse inventory...";
                                      });

                                      await loadWarehouseItems(value);
                                    },
                                  ),

                            const SizedBox(height: 15),

                            if (selectedWarehouseId != null)
                              Row(
                                children: [
                                  Icon(
                                    orderRows.isNotEmpty
                                        ? Icons.check_circle
                                        : Icons.sync,

                                    size: 18,

                                    color: orderRows.isNotEmpty
                                        ? Colors.green
                                        : const Color(0xff0050c0),
                                  ),

                                  const SizedBox(width: 8),

                                  Expanded(
                                    child: Text(
                                      orderRows.isNotEmpty
                                          ? "${orderRows.length} warehouse items loaded ✔"
                                          : statusText,

                                      style: TextStyle(
                                        color: orderRows.isNotEmpty
                                            ? Colors.green
                                            : const Color(0xff0050c0),

                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );

                    // ==================================================
                    // DESKTOP / LARGE SCREEN
                    // ==================================================

                    if (!isSmall) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Expanded(child: uploadCard),

                          const SizedBox(width: 20),

                          Expanded(child: warehouseCard),
                        ],
                      );
                    }

                    // ==================================================
                    // SMALL SCREEN
                    // ==================================================

                    return Column(
                      children: [
                        uploadCard,

                        const SizedBox(height: 20),

                        warehouseCard,
                      ],
                    );
                  },
                ),

                const SizedBox(height: 30),

                // ==================================================
                // GENERATE BUTTON
                // ==================================================
                SizedBox(
                  width: double.infinity,

                  height: 58,

                  child: ElevatedButton.icon(
                    onPressed:
                        inventoryRows.isNotEmpty &&
                            orderRows.isNotEmpty &&
                            !isGenerating
                        ? generateOrder
                        : null,

                    icon: isGenerating
                        ? const SizedBox(
                            width: 22,
                            height: 22,

                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.play_arrow, size: 25),

                    label: Text(
                      isGenerating ? "Processing..." : "Generate Order",

                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,

                      foregroundColor: Colors.white,

                      disabledBackgroundColor: Colors.grey.shade400,

                      disabledForegroundColor: Colors.white,

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ==================================================
                // SAVE EXCEL
                // ==================================================
                if (generatedFileBytes != null)
                  SizedBox(
                    width: double.infinity,

                    height: 52,

                    child: OutlinedButton.icon(
                      onPressed: () {
                        downloadFile(generatedFileBytes!);
                      },

                      icon: const Icon(Icons.download),

                      label: const Text(
                        "Save Excel",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),

                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xff0050c0),

                        side: const BorderSide(color: Color(0xff0050c0)),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 20),

                // ==================================================
                // STATUS
                // ==================================================
                if (statusText.isNotEmpty)
                  Container(
                    width: double.infinity,

                    padding: const EdgeInsets.all(16),

                    decoration: BoxDecoration(
                      color: Colors.white,

                      borderRadius: BorderRadius.circular(12),
                    ),

                    child: Text(
                      statusText,

                      textAlign: TextAlign.center,

                      style: const TextStyle(
                        color: Color(0xff0050c0),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================
  // Upload Card
  // ==========================

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

              color: fileName != null ? Colors.green : const Color(0xff0050c0),
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

              child: Text(fileName == null ? "Upload" : "Change"),
            ),
          ],
        ),
      ),
    );
  }
}

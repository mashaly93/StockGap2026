import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'Homescreen.dart';
import 'history_screen.dart';

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

  // ============================================================
  // PHARMACY MISSING ITEMS
  // ============================================================

  List<List<String>> inventoryRows = [];

  // ============================================================
  // WAREHOUSE INVENTORY
  // ============================================================

  List<List<String>> orderRows = [];

  // ============================================================
  // GENERATED FILE
  // ============================================================

  Uint8List? generatedFileBytes;

  bool isGenerating = false;

  String? inventoryFileName;

  String statusText = "";

  // ============================================================
  // WAREHOUSES
  // ============================================================

  List<Map<String, dynamic>> warehouses = [];

  String? selectedWarehouseId;

  Map<String, dynamic>? selectedWarehouse;

  bool loadingWarehouses = false;

  // ============================================================
  // SEARCH RESULTS
  // ============================================================

  List<Map<String, dynamic>> warehouseSearchResults = [];

  bool searchingWarehouse = false;

  // ============================================================
  // SELECTED MATCHING ITEMS
  // ============================================================

  final List<Map<String, dynamic>> selectedItems = [];

  // ============================================================
  // DRUG DETAILS ITEMS
  //
  // هذه القائمة مختلفة تماماً عن Missing Items
  // ============================================================

  List<Map<String, dynamic>> drugDetailsItems = [];

  bool loadingDrugDetailsItems = false;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    loadWarehouses();

    loadDrugDetailsItems();
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ============================================================
  // LOGOUT
  // ============================================================

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

  // ============================================================
  // LOAD WAREHOUSES
  // ============================================================

  Future<void> loadWarehouses() async {
    if (!mounted) return;

    setState(() {
      loadingWarehouses = true;
      statusText = "Loading warehouses...";
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection("stores")
          .where("role", isEqualTo: "store")
          .get();

      final loadedWarehouses = <Map<String, dynamic>>[];

      for (final doc in snap.docs) {
        final data = doc.data();

        final name = data["name"]?.toString().trim() ?? "";

        loadedWarehouses.add({
          "id": doc.id,
          "name": name.isNotEmpty ? name : doc.id,
          "whatsapp": data["whatsapp"]?.toString().trim() ?? "",
          "phone": data["phone"]?.toString().trim() ?? "",
          "address": data["address"]?.toString().trim() ?? "",
        });
      }

      if (!mounted) return;

      setState(() {
        warehouses = loadedWarehouses;

        loadingWarehouses = false;

        statusText = loadedWarehouses.isEmpty ? "No warehouses found." : "";
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loadingWarehouses = false;

        statusText = "Failed to load warehouses:\n$e";
      });
    }
  }

  // ============================================================
  // LOAD DRUG DETAILS ITEMS
  //
  // العناصر القادمة من DrugDetailsScreen
  // ============================================================

  Future<void> loadDrugDetailsItems() async {
    if (!mounted) return;

    setState(() {
      loadingDrugDetailsItems = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      final savedItems = prefs.getStringList("drug_details_order_items") ?? [];

      final loadedItems = <Map<String, dynamic>>[];

      for (final item in savedItems) {
        try {
          final decoded = jsonDecode(item);

          if (decoded is Map) {
            loadedItems.add(Map<String, dynamic>.from(decoded));
          }
        } catch (e) {
          debugPrint("ERROR DECODING DRUG DETAIL ITEM: $e");
        }
      }

      if (!mounted) return;

      setState(() {
        drugDetailsItems = loadedItems;

        loadingDrugDetailsItems = false;
      });

      debugPrint("DRUG DETAILS ITEMS LOADED = ${loadedItems.length}");
    } catch (e) {
      if (!mounted) return;

      setState(() {
        drugDetailsItems = [];
        loadingDrugDetailsItems = false;
      });

      debugPrint("ERROR LOADING DRUG DETAILS ITEMS: $e");
    }
  }

  // ============================================================
  // DELETE DRUG DETAILS ITEMS
  // ============================================================

  Future<void> clearDrugDetailsItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove("drug_details_order_items");

      if (!mounted) return;

      setState(() {
        drugDetailsItems.clear();
      });

      _showMessage("Drug Details items cleared.");
    } catch (e) {
      _showMessage("Could not clear Drug Details items: $e");
    }
  }

  // ============================================================
  // WHATSAPP
  // ============================================================

  Future<void> openWarehouseWhatsApp() async {
    final whatsapp = selectedWarehouse?["whatsapp"]?.toString().trim() ?? "";

    if (whatsapp.isEmpty) {
      _showMessage("WhatsApp number is not available for this warehouse.");
      return;
    }

    final cleanNumber = whatsapp.replaceAll(RegExp(r"[^0-9]"), "");

    final uri = Uri.parse("https://wa.me/$cleanNumber");

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        _showMessage("Could not open WhatsApp.");
      }
    } catch (e) {
      if (!mounted) return;

      _showMessage("Could not open WhatsApp: $e");
    }
  }

  // ============================================================
  // LOAD WAREHOUSE INVENTORY
  // ============================================================

  Future<void> loadWarehouseItems(String warehouseId) async {
    if (!mounted) return;

    setState(() {
      orderRows.clear();

      warehouseSearchResults.clear();

      selectedItems.clear();

      statusText = "Loading warehouse inventory...";
    });

    try {
      final inventoryRef = FirebaseFirestore.instance
          .collection("stores")
          .doc(warehouseId)
          .collection("inventory");

      final snap = await inventoryRef.get();

      final loadedRows = <List<String>>[];

      for (final doc in snap.docs) {
        final data = doc.data();

        final name = data["name"]?.toString().trim() ?? "";

        if (name.isEmpty) {
          continue;
        }

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

        loadedRows.add([name, "0", price.toString(), price.toString()]);
      }

      if (!mounted) return;

      setState(() {
        orderRows = loadedRows;

        statusText = "${orderRows.length} warehouse items loaded ✔";
      });

      if (inventoryRows.isNotEmpty && orderRows.isNotEmpty) {
        searchAllMissingItems();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        orderRows.clear();

        statusText = "Failed to load warehouse inventory:\n$e";
      });
    }
  }

  // ============================================================
  // EXCEL READER
  // ============================================================

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

  // ============================================================
  // PICK INVENTORY
  // ============================================================

  Future<void> pickInventory() async {
    try {
      final type = XTypeGroup(label: "Excel", extensions: ["xlsx"]);

      final file = await openFile(acceptedTypeGroups: [type]);

      if (file == null) return;

      final bytes = await File(file.path).readAsBytes();

      final rows = excelToRows(bytes);

      if (rows.length <= 1) {
        throw Exception("Excel file is empty.");
      }

      if (!mounted) return;

      setState(() {
        inventoryRows = rows;

        inventoryFileName = file.name;

        generatedFileBytes = null;

        warehouseSearchResults.clear();

        selectedItems.clear();

        statusText = "Missing Items Loaded Successfully ✔";
      });

      if (orderRows.isNotEmpty) {
        searchAllMissingItems();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        statusText = "Failed to read Excel:\n$e";
      });
    }
  }

  // ============================================================
  // FIND QTY COLUMN
  // ============================================================

  int findQtyColumn(List<String> header) {
    for (int i = 0; i < header.length; i++) {
      final value = header[i]
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

  // ============================================================
  // MERGE MISSING ITEMS
  // ============================================================

  Map<String, Map<String, dynamic>> buildMergedMissingItems() {
    final Map<String, Map<String, dynamic>> merged = {};

    if (inventoryRows.isEmpty) {
      return merged;
    }

    final header = inventoryRows.first;

    final qtyColumnIndex = findQtyColumn(header);

    for (int i = 1; i < inventoryRows.length; i++) {
      final row = inventoryRows[i];

      if (row.isEmpty) {
        continue;
      }

      String item = "";

      int qty = 0;

      if (qtyColumnIndex >= 0 && qtyColumnIndex < row.length) {
        final qtyText = row[qtyColumnIndex].replaceAll(",", "").trim();

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
      } else if (row.length >= 2) {
        item = row[0].trim();

        final qtyText = row[1].replaceAll(",", "").trim();

        qty = int.tryParse(qtyText) ?? 0;
      }

      if (item.isEmpty) {
        continue;
      }

      final key = normalizeForSearch(item);

      if (merged.containsKey(key)) {
        merged[key]!["qty"] = (merged[key]!["qty"] as int) + qty;
      } else {
        merged[key] = {"item": item, "qty": qty};
      }
    }

    return merged;
  }

  // ============================================================
  // NORMALIZE
  // ============================================================

  String normalizeForSearch(String text) {
    String value = text.toLowerCase().trim();

    value = value.replaceAll(RegExp(r'[-_/\\.,()\[\]{}]+'), ' ');

    value = value.replaceAll(RegExp(r'\s+'), ' ');

    value = value.replaceAll(RegExp(r'\btablets?\b'), 'tab');

    value = value.replaceAll(RegExp(r'\bcapsules?\b'), 'cap');

    value = value.replaceAll(RegExp(r'\btab(s)?\b'), 'tab');

    value = value.replaceAll(RegExp(r'\bcap(s)?\b'), 'cap');

    value = value.replaceAll(RegExp(r'\bampoules?\b'), 'amp');

    value = value.replaceAll(RegExp(r'\binjections?\b'), 'inj');

    return value.trim();
  }

  // ============================================================
  // WORD SIMILARITY
  // ============================================================

  double wordSimilaritySimple(String a, String b) {
    if (a == b) {
      return 100;
    }

    if (a.isEmpty || b.isEmpty) {
      return 0;
    }

    final len = a.length > b.length ? a.length : b.length;

    int distance = 0;

    for (int i = 0; i < len; i++) {
      if (i >= a.length || i >= b.length) {
        distance++;
      } else if (a[i] != b[i]) {
        distance++;
      }
    }

    return 100 - ((distance / len) * 100);
  }

  // ============================================================
  // MATCH SCORE
  // ============================================================

  double calculateMatchScore(String item1, String item2) {
    final a = normalizeForSearch(item1);

    final b = normalizeForSearch(item2);

    if (a.isEmpty || b.isEmpty) {
      return 0;
    }

    if (a == b) {
      return 100;
    }

    final wordsA = a.split(" ").where((e) => e.isNotEmpty).toList();

    final wordsB = b.split(" ").where((e) => e.isNotEmpty).toList();

    if (wordsA.isEmpty || wordsB.isEmpty) {
      return 0;
    }

    final firstScore = wordSimilaritySimple(wordsA.first, wordsB.first);

    if (firstScore < 60) {
      return 0;
    }

    int matchedWords = 0;

    final usedIndexes = <int>{};

    for (final wordA in wordsA) {
      double best = 0;

      int bestIndex = -1;

      for (int i = 0; i < wordsB.length; i++) {
        if (usedIndexes.contains(i)) {
          continue;
        }

        final wordB = wordsB[i];

        final score = wordSimilaritySimple(wordA, wordB);

        if (score > best) {
          best = score;
          bestIndex = i;
        }
      }

      if (best >= 70 && bestIndex >= 0) {
        matchedWords++;

        usedIndexes.add(bestIndex);
      }
    }

    final maxWords = wordsA.length > wordsB.length
        ? wordsA.length
        : wordsB.length;

    double score = (matchedWords / maxWords) * 70;

    final numbersA = RegExp(
      r'\d+(?:\.\d+)?',
    ).allMatches(a).map((e) => e.group(0)!).toSet();

    final numbersB = RegExp(
      r'\d+(?:\.\d+)?',
    ).allMatches(b).map((e) => e.group(0)!).toSet();

    if (numbersA.isNotEmpty && numbersB.isNotEmpty) {
      if (numbersA.intersection(numbersB).isNotEmpty) {
        score += 20;
      } else {
        score -= 15;
      }
    }

    if (wordsA.first == wordsB.first) {
      score += 10;
    }

    if (score < 0) {
      score = 0;
    }

    if (score > 100) {
      score = 100;
    }

    return score;
  }

  // ============================================================
  // SEARCH ALL MISSING ITEMS
  // ============================================================

  void searchAllMissingItems() {
    if (inventoryRows.isEmpty || orderRows.isEmpty) {
      return;
    }

    if (!mounted) return;

    setState(() {
      searchingWarehouse = true;
    });

    final merged = buildMergedMissingItems();

    final results = <Map<String, dynamic>>[];

    for (final data in merged.values) {
      final item = data["item"].toString();

      final qty = data["qty"] as int;

      double bestScore = 0;

      String bestWarehouseItem = "";

      List<String>? bestWarehouseRow;

      for (final warehouse in orderRows) {
        if (warehouse.isEmpty) {
          continue;
        }

        final warehouseItem = warehouse[0].trim();

        if (warehouseItem.isEmpty) {
          continue;
        }

        final score = calculateMatchScore(item, warehouseItem);

        if (score > bestScore) {
          bestScore = score;

          bestWarehouseItem = warehouseItem;

          bestWarehouseRow = warehouse;
        }
      }

      if (bestScore >= 60 && bestWarehouseRow != null) {
        double purchase = 0;

        double sale = 0;

        if (bestWarehouseRow.length >= 3) {
          purchase =
              double.tryParse(bestWarehouseRow[2].replaceAll(",", "").trim()) ??
              0;
        }

        if (bestWarehouseRow.length >= 4) {
          sale =
              double.tryParse(bestWarehouseRow[3].replaceAll(",", "").trim()) ??
              0;
        }

        results.add({
          "item": item,
          "qty": qty,
          "matchedItem": bestWarehouseItem,
          "score": bestScore,
          "purchase": purchase,
          "sale": sale,
          "warehouseId": selectedWarehouseId,
          "warehouseName":
              selectedWarehouse?["name"]?.toString() ??
              selectedWarehouseId ??
              "",
          "added": isItemSelected(item, bestWarehouseItem),
        });
      }
    }

    results.sort(
      (a, b) => (b["score"] as double).compareTo(a["score"] as double),
    );

    if (!mounted) return;

    setState(() {
      warehouseSearchResults = results;

      searchingWarehouse = false;

      statusText = "${results.length} matching items found ✔";
    });
  }

  // ============================================================
  // CHECK SELECTED
  // ============================================================

  bool isItemSelected(String item, String matchedItem) {
    return selectedItems.any(
      (x) => x["item"] == item && x["matchedItem"] == matchedItem,
    );
  }

  // ============================================================
  // ADD SELECTED ITEM
  // ============================================================

  void addSelectedItem(Map<String, dynamic> result) {
    final exists = isItemSelected(
      result["item"].toString(),
      result["matchedItem"].toString(),
    );

    if (exists) {
      _showMessage("Item already added.");
      return;
    }

    setState(() {
      selectedItems.add({...result, "added": true});

      result["added"] = true;
    });

    _showMessage("${result["item"]} added ✔");
  }

  // ============================================================
  // REMOVE SELECTED ITEM
  // ============================================================

  void removeSelectedItem(Map<String, dynamic> result) {
    setState(() {
      selectedItems.removeWhere(
        (x) =>
            x["item"] == result["item"] &&
            x["matchedItem"] == result["matchedItem"],
      );

      result["added"] = false;
    });
  }

  // ============================================================
  // WAREHOUSE SEARCH RESULTS
  // ============================================================

  Widget buildWarehouseSearchResults() {
    if (inventoryRows.isEmpty || orderRows.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.search, color: Color(0xff0050c0)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Warehouse Matches",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xff0050c0),
                    ),
                  ),
                ),
                Text(
                  "${warehouseSearchResults.length}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 15),

            if (searchingWarehouse)
              const Center(child: CircularProgressIndicator())
            else if (warehouseSearchResults.isEmpty)
              const Padding(
                padding: EdgeInsets.all(15),
                child: Center(
                  child: Text(
                    "No items matched at 60% or higher.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ...warehouseSearchResults.map((result) => _buildMatchRow(result)),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MATCH ROW
  // ============================================================

  Widget _buildMatchRow(Map<String, dynamic> result) {
    final score = result["score"] as double;

    final added = result["added"] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: added ? Colors.green.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result["item"].toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(
                      Icons.arrow_forward,
                      size: 15,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        result["matchedItem"].toString(),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  children: [
                    Text(
                      "Qty: ${result["qty"]}",
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      "Price: ${result["sale"]}",
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "${score.toStringAsFixed(0)}%",
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  onPressed: added
                      ? () {
                          removeSelectedItem(result);
                        }
                      : () {
                          addSelectedItem(result);
                        },
                  icon: Icon(added ? Icons.remove : Icons.add, size: 16),
                  label: Text(added ? "Remove" : "Add"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: added ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DRUG DETAILS CARD
  // ============================================================

  Widget buildDrugDetailsItemsCard() {
    if (loadingDrugDetailsItems) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: const [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text("Loading Drug Details items..."),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.medication, color: Color(0xff0050c0)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Drug Details Items",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xff0050c0),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${drugDetailsItems.length}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xff0050c0),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            const Text(
              "These items come from Drug Details and will be placed in a separate Excel sheet.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),

            const SizedBox(height: 12),

            if (drugDetailsItems.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  "No Drug Details items added.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ...drugDetailsItems.asMap().entries.map((entry) {
                final index = entry.key;

                final item = entry.value;

                return _buildDrugDetailsRow(item, index);
              }),

            if (drugDetailsItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: OutlinedButton.icon(
                  onPressed: clearDrugDetailsItems,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text("Clear Drug Details Items"),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DRUG DETAILS ROW
  // ============================================================

  Widget _buildDrugDetailsRow(Map<String, dynamic> item, int index) {
    final name = item["item"]?.toString() ?? "";

    final qty = item["qty"]?.toString() ?? "0";

    final warehouse = item["warehouse"]?.toString() ?? "";

    final matched = item["matchedItem"]?.toString() ?? "";

    final score = double.tryParse(item["matchPercent"]?.toString() ?? "") ?? 0;

    final price = double.tryParse(item["sale"]?.toString() ?? "") ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),

      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xff0050c0).withOpacity(0.10),
            child: Text(
              "${index + 1}",
              style: const TextStyle(
                color: Color(0xff0050c0),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  "Warehouse: $warehouse",
                  style: const TextStyle(fontSize: 12),
                ),

                Text(
                  "Matched: $matched",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "Qty: $qty",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),

              Text(
                "${price.toStringAsFixed(3)} OMR",
                style: const TextStyle(color: Colors.green, fontSize: 12),
              ),

              Text(
                "${score.toStringAsFixed(0)}%",
                style: const TextStyle(color: Color(0xff0050c0), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // GENERATE ORDER
  // ============================================================

  Future<void> generateOrder() async {
    if (inventoryRows.isEmpty && drugDetailsItems.isEmpty) {
      setState(() {
        statusText =
            "Please upload Missing Items or add items from Drug Details.";
      });

      return;
    }

    if (orderRows.isEmpty && drugDetailsItems.isEmpty) {
      setState(() {
        statusText = "Please select a Warehouse first.";
      });

      return;
    }

    if (isGenerating) return;

    // ==========================================================
    // REFRESH DRUG DETAILS ITEMS
    // ==========================================================

    await loadDrugDetailsItems();

    if (!mounted) return;

    setState(() {
      isGenerating = true;

      statusText = "Generating order...";

      generatedFileBytes = null;
    });

    try {
      final excel = Excel.createExcel();

      // ========================================================
      // SHEETS
      // ========================================================

      final resultSheet = excel["Sheet1"];

      final missingSheet = excel["Missing"];

      final drugDetailsSheet = excel["Drug Details Items"];

      // ========================================================
      // RESULT HEADERS
      // ========================================================

      resultSheet.appendRow([
        TextCellValue("Item"),
        TextCellValue("Qty"),
        TextCellValue("Matched Item"),
        TextCellValue("Purchase Price"),
        TextCellValue("Total"),
      ]);

      double totalSale = 0;

      // ========================================================
      // NORMAL MISSING ITEMS
      //
      // هنا فقط inventoryRows
      // ========================================================

      final merged = buildMergedMissingItems();

      final similarItems = <Map<String, dynamic>>[];

      final notFound = <Map<String, dynamic>>[];

      int processed = 0;

      for (final data in merged.values) {
        final item = data["item"].toString();

        final qty = data["qty"] as int;

        double bestScore = 0;

        String bestItem = "";

        List<String>? bestWarehouse;

        for (final warehouse in orderRows) {
          if (warehouse.isEmpty) {
            continue;
          }

          final warehouseItem = warehouse[0].trim();

          if (warehouseItem.isEmpty) {
            continue;
          }

          final score = calculateMatchScore(item, warehouseItem);

          if (score > bestScore) {
            bestScore = score;

            bestItem = warehouseItem;

            bestWarehouse = warehouse;
          }
        }

        if (bestScore >= 60 && bestWarehouse != null) {
          double purchase = 0;

          double sale = 0;

          if (bestWarehouse.length >= 3) {
            purchase =
                double.tryParse(bestWarehouse[2].replaceAll(",", "").trim()) ??
                0;
          }

          if (bestWarehouse.length >= 4) {
            sale =
                double.tryParse(bestWarehouse[3].replaceAll(",", "").trim()) ??
                0;
          }

          final total = sale * qty;

          totalSale += total;

          resultSheet.appendRow([
            TextCellValue(item),
            TextCellValue(qty.toString()),
            TextCellValue(bestItem),
            TextCellValue(purchase.toStringAsFixed(3)),
            TextCellValue(total.toStringAsFixed(3)),
          ]);
        } else {
          final dataMap = {
            "item": item,
            "qty": qty,
            "similar": bestItem,
            "score": bestScore.toStringAsFixed(0),
          };

          if (bestScore >= 40) {
            similarItems.add(dataMap);
          } else {
            notFound.add(dataMap);
          }
        }

        processed++;

        if (mounted) {
          setState(() {
            statusText =
                "Processing Missing Items $processed / ${merged.length}...";
          });
        }
      }

      // ========================================================
      // MISSING SHEET
      //
      // فقط أصناف ملف Excel
      // ========================================================

      missingSheet.appendRow([
        TextCellValue("Item"),
        TextCellValue("Qty"),
        TextCellValue("Similar Item"),
        TextCellValue("Match %"),
      ]);

      missingSheet.appendRow([TextCellValue("POSSIBLE MATCHES")]);

      for (final item in similarItems) {
        missingSheet.appendRow([
          TextCellValue(item["item"].toString()),
          TextCellValue(item["qty"].toString()),
          TextCellValue(item["similar"].toString()),
          TextCellValue("${item["score"]}%"),
        ]);
      }

      missingSheet.appendRow([]);

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

      // ========================================================
      // TOTAL NORMAL ORDER
      // ========================================================

      resultSheet.appendRow([]);

      resultSheet.appendRow([
        TextCellValue(""),
        TextCellValue(""),
        TextCellValue("TOTAL"),
        TextCellValue(""),
        TextCellValue(totalSale.toStringAsFixed(3)),
      ]);

      // ========================================================
      // SELECTED ITEMS SHEET
      //
      // العناصر التي ضغط المستخدم Add من نتائج Missing
      // ========================================================

      final selectedSheet = excel["Selected Items"];

      selectedSheet.appendRow([
        TextCellValue("Item"),
        TextCellValue("Qty"),
        TextCellValue("Warehouse"),
        TextCellValue("Matched Item"),
        TextCellValue("Match %"),
        TextCellValue("Purchase Price"),
        TextCellValue("Sale Price"),
        TextCellValue("Total"),
      ]);

      double selectedTotal = 0;

      for (final item in selectedItems) {
        final originalItem = item["item"].toString();

        final qty = item["qty"] as int;

        final warehouseName = item["warehouseName"].toString();

        final matchedItem = item["matchedItem"].toString();

        final score = item["score"] as double;

        final purchase = (item["purchase"] as num).toDouble();

        final sale = (item["sale"] as num).toDouble();

        final total = sale * qty;

        selectedTotal += total;

        selectedSheet.appendRow([
          TextCellValue(originalItem),
          TextCellValue(qty.toString()),
          TextCellValue(warehouseName),
          TextCellValue(matchedItem),
          TextCellValue("${score.toStringAsFixed(0)}%"),
          TextCellValue(purchase.toStringAsFixed(3)),
          TextCellValue(sale.toStringAsFixed(3)),
          TextCellValue(total.toStringAsFixed(3)),
        ]);
      }

      selectedSheet.appendRow([]);

      selectedSheet.appendRow([
        TextCellValue(""),
        TextCellValue(""),
        TextCellValue(""),
        TextCellValue(""),
        TextCellValue(""),
        TextCellValue(""),
        TextCellValue("TOTAL"),
        TextCellValue(selectedTotal.toStringAsFixed(3)),
      ]);

      // ========================================================
      // DRUG DETAILS ITEMS SHEET
      //
      // مستقل تماماً عن Missing
      // ========================================================

      drugDetailsSheet.appendRow([
        TextCellValue("Item"),
        TextCellValue("Qty"),
        TextCellValue("Warehouse"),
        TextCellValue("Matched Item"),
        TextCellValue("Match %"),
        TextCellValue("Purchase Price"),
        TextCellValue("Sale Price"),
        TextCellValue("Total"),
        TextCellValue("Registration"),
        TextCellValue("Manufacturer"),
      ]);

      double drugDetailsTotal = 0;

      for (final item in drugDetailsItems) {
        final originalItem = item["item"]?.toString() ?? "";

        final qty = int.tryParse(item["qty"]?.toString() ?? "") ?? 0;

        final warehouse = item["warehouse"]?.toString() ?? "";

        final matchedItem = item["matchedItem"]?.toString() ?? "";

        final matchPercent =
            double.tryParse(item["matchPercent"]?.toString() ?? "") ?? 0;

        final purchase =
            double.tryParse(item["purchase"]?.toString() ?? "") ?? 0;

        final sale = double.tryParse(item["sale"]?.toString() ?? "") ?? 0;

        final registration = item["registration"]?.toString() ?? "";

        final manufacturer = item["manufacturer"]?.toString() ?? "";

        final total = sale * qty;

        drugDetailsTotal += total;

        drugDetailsSheet.appendRow([
          TextCellValue(originalItem),
          TextCellValue(qty.toString()),
          TextCellValue(warehouse),
          TextCellValue(matchedItem),
          TextCellValue("${matchPercent.toStringAsFixed(0)}%"),
          TextCellValue(purchase.toStringAsFixed(3)),
          TextCellValue(sale.toStringAsFixed(3)),
          TextCellValue(total.toStringAsFixed(3)),
          TextCellValue(registration),
          TextCellValue(manufacturer),
        ]);
      }

      // ========================================================
      // DRUG DETAILS TOTAL
      // ========================================================

      drugDetailsSheet.appendRow([]);

      drugDetailsSheet.appendRow([
        TextCellValue(""),
        TextCellValue(""),
        TextCellValue(""),
        TextCellValue(""),
        TextCellValue(""),
        TextCellValue(""),
        TextCellValue("TOTAL"),
        TextCellValue(drugDetailsTotal.toStringAsFixed(3)),
        TextCellValue(""),
        TextCellValue(""),
      ]);

      // ========================================================
      // ENCODE
      // ========================================================

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

  // ============================================================
  // SAVE HISTORY
  // ============================================================

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
      "items": inventoryRows.length + drugDetailsItems.length,
    };

    history.add(jsonEncode(order));

    await prefs.setStringList("orders", history);
  }

  // ============================================================
  // SAVE FILE
  // ============================================================

  Future<void> downloadFile(Uint8List bytes) async {
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

      // ========================================================
      // بعد الحفظ نحذف Drug Details items
      // ========================================================

      final prefs = await SharedPreferences.getInstance();

      await prefs.remove("drug_details_order_items");

      if (!mounted) return;

      setState(() {
        drugDetailsItems.clear();

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

  // ============================================================
  // RESET
  // ============================================================

  void resetScreen() {
    setState(() {
      inventoryRows.clear();

      orderRows.clear();

      warehouseSearchResults.clear();

      selectedItems.clear();

      generatedFileBytes = null;

      inventoryFileName = null;

      selectedWarehouseId = null;

      selectedWarehouse = null;

      drugDetailsItems.clear();

      statusText = "Ready";
    });
  }

  // ============================================================
  // BUILD
  // ============================================================

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

                const SizedBox(height: 30),

                // ==================================================
                // MISSING UPLOAD
                // ==================================================
                _buildUploadCard(
                  title: "Missing Items",
                  fileName: inventoryFileName,
                  icon: Icons.inventory_2,
                  onPressed: pickInventory,
                ),

                const SizedBox(height: 20),

                // ==================================================
                // DRUG DETAILS ITEMS
                //
                // مستقل عن Missing
                // ==================================================
                buildDrugDetailsItemsCard(),

                const SizedBox(height: 20),

                // ==================================================
                // WAREHOUSE
                // ==================================================
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              selectedWarehouseId != null
                                  ? Icons.check_circle
                                  : Icons.warehouse,
                              size: 45,
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
                            ? const CircularProgressIndicator()
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

                                  final warehouse = warehouses.firstWhere(
                                    (w) => w["id"].toString() == value,
                                    orElse: () => <String, dynamic>{},
                                  );

                                  setState(() {
                                    selectedWarehouseId = value;

                                    selectedWarehouse = warehouse;

                                    orderRows.clear();

                                    warehouseSearchResults.clear();

                                    selectedItems.clear();

                                    statusText =
                                        "Loading warehouse inventory...";
                                  });

                                  await loadWarehouseItems(value);
                                },
                              ),
                      ],
                    ),
                  ),
                ),

                // ==================================================
                // WAREHOUSE INFO
                // ==================================================
                if (selectedWarehouse != null) ...[
                  const SizedBox(height: 15),
                  _buildWarehouseInfoCard(),
                ],

                const SizedBox(height: 20),

                // ==================================================
                // SEARCH RESULTS
                // ==================================================
                buildWarehouseSearchResults(),

                // ==================================================
                // SELECTED COUNT
                // ==================================================
                if (selectedItems.isNotEmpty) ...[
                  const SizedBox(height: 15),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          "${selectedItems.length} items selected",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 25),

                // ==================================================
                // GENERATE
                // ==================================================
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton.icon(
                    onPressed:
                        (inventoryRows.isNotEmpty ||
                                drugDetailsItems.isNotEmpty) &&
                            !isGenerating &&
                            (orderRows.isNotEmpty ||
                                drugDetailsItems.isNotEmpty)
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ==================================================
                // SAVE
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

  // ============================================================
  // WAREHOUSE INFO CARD
  // ============================================================

  Widget _buildWarehouseInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Warehouse Information",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xff0050c0),
              ),
            ),

            const SizedBox(height: 10),

            _buildWarehouseInfoRow(
              Icons.warehouse,
              "Name",
              selectedWarehouse!["name"]?.toString() ?? "-",
            ),

            const SizedBox(height: 6),

            _buildWarehouseInfoRow(
              Icons.tag,
              "Store Code",
              selectedWarehouse!["id"]?.toString() ?? "-",
            ),

            if ((selectedWarehouse!["phone"]?.toString() ?? "").isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildWarehouseInfoRow(
                Icons.phone,
                "Phone",
                selectedWarehouse!["phone"].toString(),
              ),
            ],

            if ((selectedWarehouse!["address"]?.toString() ?? "")
                .isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildWarehouseInfoRow(
                Icons.location_on,
                "Address",
                selectedWarehouse!["address"].toString(),
              ),
            ],

            if ((selectedWarehouse!["whatsapp"]?.toString() ?? "")
                .isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: openWarehouseWhatsApp,
                  icon: const Icon(Icons.chat, size: 18),
                  label: const Text("Contact Warehouse on WhatsApp"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // INFO ROW
  // ============================================================

  Widget _buildWarehouseInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xff0050c0), size: 20),

        const SizedBox(width: 8),

        Text(
          "$label:",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),

        const SizedBox(width: 8),

        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  // ============================================================
  // UPLOAD CARD
  // ============================================================

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

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
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  // ============================================================
  // OMAN COLORS
  // ============================================================

  static const Color omanRed = Color(0xffC8102E);
  static const Color omanGreen = Color(0xff009A44);
  static const Color omanWhite = Colors.white;

  static const Color background = Color(0xffF5F7F8);
  static const Color surface = Colors.white;
  static const Color textDark = Color(0xff172033);
  static const Color textMuted = Color(0xff6B7280);

  static const Color success = omanGreen;
  static const Color danger = omanRed;

  static const double cardRadius = 15;

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

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          backgroundColor: textDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
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

    if (cleanNumber.isEmpty) {
      _showMessage("Invalid WhatsApp number.");
      return;
    }

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

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBox(Icons.search_rounded, omanRed),

              const SizedBox(width: 9),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Warehouse Matches",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textDark,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Items matched with warehouse inventory.",
                      style: TextStyle(fontSize: 10, color: textMuted),
                    ),
                  ],
                ),
              ),

              _countBadge("${warehouseSearchResults.length}", omanGreen),
            ],
          ),

          const SizedBox(height: 13),

          if (searchingWarehouse)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: omanGreen,
                ),
              ),
            )
          else if (warehouseSearchResults.isEmpty)
            _emptyBox("No items matched at 60% or higher.")
          else
            ...warehouseSearchResults.map((result) => _buildMatchRow(result)),
        ],
      ),
    );
  }

  // ============================================================
  // MATCH ROW
  // ============================================================

  Widget _buildMatchRow(Map<String, dynamic> result) {
    final score = result["score"] as double;

    final added = result["added"] == true;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: added ? Colors.green.shade50 : const Color(0xffF8FAFD),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: added
                  ? omanGreen.withOpacity(.10)
                  : omanRed.withOpacity(.07),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              added ? Icons.check_rounded : Icons.medication_outlined,
              color: added ? omanGreen : omanRed,
              size: 18,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result["item"].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: textDark,
                  ),
                ),

                const SizedBox(height: 4),

                Row(
                  children: [
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 13,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        result["matchedItem"].toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: textMuted, fontSize: 11),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    _smallBadge(
                      Icons.production_quantity_limits,
                      "Qty ${result["qty"]}",
                    ),
                    _smallBadge(
                      Icons.payments_outlined,
                      "${result["sale"]} OMR",
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 9),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: added
                      ? omanGreen.withOpacity(.12)
                      : omanRed.withOpacity(.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "${score.toStringAsFixed(0)}%",
                  style: TextStyle(
                    color: added ? omanGreen : omanRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),

              const SizedBox(height: 6),

              SizedBox(
                height: 32,
                child: ElevatedButton.icon(
                  onPressed: added
                      ? () => removeSelectedItem(result)
                      : () => addSelectedItem(result),
                  icon: Icon(
                    added ? Icons.remove_rounded : Icons.add_rounded,
                    size: 15,
                  ),
                  label: Text(
                    added ? "Remove" : "Add",
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: added ? omanRed : omanGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
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
      return _card(
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: omanGreen,
              ),
            ),
            SizedBox(width: 10),
            Text("Loading Drug Details items..."),
          ],
        ),
      );
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.medication_rounded, color: omanGreen, size: 20),

              const SizedBox(width: 8),

              const Expanded(
                child: Text(
                  "Drug Details Items",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textDark,
                  ),
                ),
              ),

              _countBadge("${drugDetailsItems.length}", omanGreen),
            ],
          ),

          const SizedBox(height: 10),

          const Text(
            "These items come from Drug Details and will be placed in a separate Excel sheet.",
            style: TextStyle(color: textMuted, fontSize: 11),
          ),

          const SizedBox(height: 11),

          if (drugDetailsItems.isEmpty)
            _emptyBox("No Drug Details items added.")
          else
            ...drugDetailsItems.asMap().entries.map(
              (entry) => _buildDrugDetailsRow(entry.value, entry.key),
            ),

          if (drugDetailsItems.isNotEmpty) ...[
            const SizedBox(height: 7),
            SizedBox(
              width: double.infinity,
              height: 37,
              child: OutlinedButton.icon(
                onPressed: clearDrugDetailsItems,
                icon: const Icon(Icons.delete_outline, size: 17),
                label: const Text(
                  "Clear Drug Details Items",
                  style: TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: omanRed,
                  side: BorderSide(color: omanRed.withOpacity(.25)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
          ],
        ],
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
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFD),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: omanGreen.withOpacity(.08),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                "${index + 1}",
                style: const TextStyle(
                  color: omanGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 3),

                if (warehouse.isNotEmpty)
                  Text(
                    "Warehouse: $warehouse",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: textMuted),
                  ),

                if (matched.isNotEmpty)
                  Text(
                    "Matched: $matched",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: textMuted, fontSize: 10),
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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                "${price.toStringAsFixed(3)} OMR",
                style: const TextStyle(color: omanGreen, fontSize: 10),
              ),

              Text(
                "${score.toStringAsFixed(0)}%",
                style: const TextStyle(color: omanRed, fontSize: 10),
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

    await loadDrugDetailsItems();

    if (!mounted) return;

    setState(() {
      isGenerating = true;
      statusText = "Generating order...";
      generatedFileBytes = null;
    });

    try {
      final excel = Excel.createExcel();

      final resultSheet = excel["Sheet1"];

      final missingSheet = excel["Missing"];

      final drugDetailsSheet = excel["Drug Details Items"];

      resultSheet.appendRow([
        TextCellValue("Item"),
        TextCellValue("Qty"),
        TextCellValue("Matched Item"),
        TextCellValue("Purchase Price"),
        TextCellValue("Total"),
      ]);

      double totalSale = 0;

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

      resultSheet.appendRow([]);

      resultSheet.appendRow([
        TextCellValue(""),
        TextCellValue(""),
        TextCellValue("TOTAL"),
        TextCellValue(""),
        TextCellValue(totalSale.toStringAsFixed(3)),
      ]);

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
  // UI HELPERS
  // ============================================================

  Widget _card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(15),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 37,
      height: 37,
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 19),
    );
  }

  Widget _countBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _emptyBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFD),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: textMuted, fontSize: 12),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,

        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: omanRed),
          onPressed: () => Navigator.pop(context),
        ),

        titleSpacing: 4,

        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xfffff3f4),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                color: omanRed,
                size: 21,
              ),
            ),

            const SizedBox(width: 10),

            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Full Stock",
                  style: TextStyle(
                    color: textDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                Text(
                  "Order Generator",
                  style: TextStyle(
                    color: omanGreen,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .4,
                  ),
                ),
              ],
            ),
          ],
        ),

        actions: [
          IconButton(
            tooltip: "Order History",
            icon: const Icon(Icons.history_rounded, color: omanGreen),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),

          IconButton(
            tooltip: "Logout",
            icon: const Icon(Icons.logout_rounded, color: omanRed),
            onPressed: logout,
          ),

          const SizedBox(width: 8),
        ],
      ),

      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPageHeader(),

                const SizedBox(height: 18),

                _buildSteps(),

                const SizedBox(height: 22),

                _sectionTitle(
                  icon: Icons.input_rounded,
                  title: "Order Input",
                  subtitle:
                      "Add missing items or select items from Drug Details.",
                ),

                const SizedBox(height: 11),

                _buildInputCards(),

                const SizedBox(height: 22),

                _sectionTitle(
                  icon: Icons.warehouse_rounded,
                  title: "Warehouse",
                  subtitle: "Choose the warehouse you want to order from.",
                ),

                const SizedBox(height: 11),

                _buildWarehouseCard(),

                if (selectedWarehouse != null) ...[
                  const SizedBox(height: 9),
                  _buildWarehouseInfoCard(),
                ],

                if (inventoryRows.isNotEmpty && orderRows.isNotEmpty) ...[
                  const SizedBox(height: 22),

                  _sectionTitle(
                    icon: Icons.compare_arrows_rounded,
                    title: "Matched Items",
                    subtitle:
                        "Review the items matched with the warehouse inventory.",
                  ),

                  const SizedBox(height: 11),

                  buildWarehouseSearchResults(),
                ],

                if (selectedItems.isNotEmpty) ...[
                  const SizedBox(height: 15),
                  _buildSelectedSummary(),
                ],

                const SizedBox(height: 22),

                _buildGenerateArea(),

                if (statusText.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildStatusCard(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // PAGE HEADER
  // ============================================================

  Widget _buildPageHeader() {
    final itemCount = inventoryRows.length + drugDetailsItems.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.045),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xfffff3f4),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.shopping_cart_checkout_rounded,
              color: omanRed,
              size: 28,
            ),
          ),

          const SizedBox(width: 14),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Create New Order",
                  style: TextStyle(
                    color: textDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                SizedBox(height: 4),

                Text(
                  "Upload missing items, choose a warehouse and generate your order.",
                  style: TextStyle(
                    color: textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),

          if (itemCount > 0) _countBadge("$itemCount", omanGreen),
        ],
      ),
    );
  }

  // ============================================================
  // STEPS
  // ============================================================

  Widget _buildSteps() {
    final step1 = inventoryRows.isNotEmpty || drugDetailsItems.isNotEmpty;

    final step2 = selectedWarehouseId != null;

    final step3 =
        warehouseSearchResults.isNotEmpty ||
        (drugDetailsItems.isNotEmpty && step2);

    final step4 = generatedFileBytes != null;

    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          _buildStepItem(number: "1", title: "Items", active: step1),

          _buildStepLine(step2),

          _buildStepItem(number: "2", title: "Warehouse", active: step2),

          _buildStepLine(step3),

          _buildStepItem(number: "3", title: "Review", active: step3),

          _buildStepLine(step4),

          _buildStepItem(number: "4", title: "Generate", active: step4),
        ],
      ),
    );
  }

  Widget _buildStepItem({
    required String number,
    required String title,
    required bool active,
  }) {
    return Expanded(
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: active ? omanGreen : const Color(0xffF1F4F8),
              shape: BoxShape.circle,
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: omanGreen.withOpacity(.16),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: active
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 18,
                    )
                  : Text(
                      number,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 6),

          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: active ? FontWeight.bold : FontWeight.w500,
              color: active ? omanGreen : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepLine(bool active) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 2,
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          color: active ? omanGreen : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // ============================================================
  // SECTION TITLE
  // ============================================================

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _iconBox(icon, omanRed),

        const SizedBox(width: 10),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                subtitle,
                style: const TextStyle(color: textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // INPUT CARDS
  // ============================================================

  Widget _buildInputCards() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildInputCard(
            title: "Missing Items",
            subtitle: inventoryRows.isEmpty
                ? "Upload Excel file"
                : "${inventoryRows.length - 1} rows loaded",
            icon: Icons.upload_file_rounded,
            active: inventoryRows.isNotEmpty,
            buttonText: inventoryRows.isEmpty ? "Upload" : "Change",
            onPressed: pickInventory,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(child: _buildDrugDetailsCompactCard()),
      ],
    );
  }

  Widget _buildInputCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool active,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return _card(
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: active ? Colors.green.shade50 : omanRed.withOpacity(.07),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              active ? Icons.check_rounded : icon,
              color: active ? omanGreen : omanRed,
              size: 22,
            ),
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: textDark,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: textMuted, fontSize: 10),
                ),
              ],
            ),
          ),

          const SizedBox(width: 7),

          OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: omanRed,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: omanRed.withOpacity(.22)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            child: Text(
              buttonText,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DRUG DETAILS COMPACT
  // ============================================================

  Widget _buildDrugDetailsCompactCard() {
    final count = drugDetailsItems.length;

    return _card(
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: omanGreen.withOpacity(.07),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.medication_rounded,
              color: omanGreen,
              size: 22,
            ),
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        "Drug Details",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: textDark,
                        ),
                      ),
                    ),

                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      _countBadge("$count", omanGreen),
                    ],
                  ],
                ),

                const SizedBox(height: 4),

                Text(
                  count == 0
                      ? "No items added"
                      : "$count items ready for order",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: textMuted, fontSize: 10),
                ),
              ],
            ),
          ),

          if (count > 0)
            IconButton(
              tooltip: "Clear",
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: omanRed,
                size: 19,
              ),
              onPressed: clearDrugDetailsItems,
            ),
        ],
      ),
    );
  }

  // ============================================================
  // WAREHOUSE CARD
  // ============================================================

  Widget _buildWarehouseCard() {
    return _card(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selectedWarehouseId != null
                      ? Colors.green.shade50
                      : omanGreen.withOpacity(.07),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  selectedWarehouseId != null
                      ? Icons.check_rounded
                      : Icons.warehouse_rounded,
                  color: selectedWarehouseId != null ? omanGreen : omanGreen,
                  size: 22,
                ),
              ),

              const SizedBox(width: 11),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Select Warehouse",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: textDark,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      "Choose where the order will be supplied from.",
                      style: TextStyle(color: textMuted, fontSize: 10),
                    ),
                  ],
                ),
              ),

              if (orderRows.isNotEmpty)
                _countBadge("${orderRows.length}", omanGreen),
            ],
          ),

          const SizedBox(height: 13),

          loadingWarehouses
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: omanGreen,
                    ),
                  ),
                )
              : DropdownButtonFormField<String>(
                  value: selectedWarehouseId,
                  isExpanded: true,

                  decoration: InputDecoration(
                    labelText: "Warehouse",
                    labelStyle: const TextStyle(fontSize: 12, color: textMuted),
                    prefixIcon: const Icon(
                      Icons.warehouse_outlined,
                      color: omanGreen,
                      size: 19,
                    ),
                    filled: true,
                    fillColor: const Color(0xffF8FAFD),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 11,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: omanGreen,
                        width: 1.4,
                      ),
                    ),
                  ),

                  hint: const Text(
                    "Choose Warehouse",
                    style: TextStyle(fontSize: 12),
                  ),

                  items: warehouses.map((warehouse) {
                    return DropdownMenuItem<String>(
                      value: warehouse["id"].toString(),
                      child: Text(
                        warehouse["name"].toString(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
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

                      statusText = "Loading warehouse inventory...";
                    });

                    await loadWarehouseItems(value);
                  },
                ),
        ],
      ),
    );
  }

  // ============================================================
  // WAREHOUSE INFO CARD
  // ============================================================

  Widget _buildWarehouseInfoCard() {
    final warehouse = selectedWarehouse!;

    final name = warehouse["name"]?.toString() ?? "-";

    final code = warehouse["id"]?.toString() ?? "-";

    final phone = warehouse["phone"]?.toString() ?? "";

    final whatsapp = warehouse["whatsapp"]?.toString() ?? "";

    final address = warehouse["address"]?.toString() ?? "";

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFD),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _iconBox(Icons.info_outline_rounded, omanGreen),

              const SizedBox(width: 8),

              const Expanded(
                child: Text(
                  "Warehouse Information",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: textDark,
                  ),
                ),
              ),

              if (orderRows.isNotEmpty)
                _countBadge("${orderRows.length} items", omanGreen),
            ],
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _buildInfoChip(Icons.warehouse_outlined, name),

              _buildInfoChip(Icons.tag_rounded, code),

              if (phone.isNotEmpty) _buildInfoChip(Icons.phone_outlined, phone),

              if (address.isNotEmpty)
                _buildInfoChip(Icons.location_on_outlined, address),
            ],
          ),

          if (whatsapp.isNotEmpty) ...[
            const SizedBox(height: 9),

            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: openWarehouseWhatsApp,
                icon: const Icon(Icons.chat_rounded, size: 16),
                label: const Text(
                  "WhatsApp Warehouse",
                  style: TextStyle(fontSize: 11),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: omanGreen,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: omanGreen.withOpacity(.25)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // INFO CHIP
  // ============================================================

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: omanGreen),

          const SizedBox(width: 5),

          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Color(0xff374151)),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SMALL BADGE
  // ============================================================

  Widget _smallBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.grey.shade600),

          const SizedBox(width: 4),

          Text(text, style: const TextStyle(fontSize: 9, color: textMuted)),
        ],
      ),
    );
  }

  // ============================================================
  // SELECTED SUMMARY
  // ============================================================

  Widget _buildSelectedSummary() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Container(
            width: 37,
            height: 37,
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: omanGreen, size: 20),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Selected Items",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: omanGreen,
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  "${selectedItems.length} items selected manually",
                  style: TextStyle(color: Colors.green.shade700, fontSize: 10),
                ),
              ],
            ),
          ),

          Text(
            "${selectedItems.length}",
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: omanGreen,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // GENERATE AREA
  // ============================================================

  Widget _buildGenerateArea() {
    final canGenerate =
        (inventoryRows.isNotEmpty || drugDetailsItems.isNotEmpty) &&
        !isGenerating &&
        (orderRows.isNotEmpty || drugDetailsItems.isNotEmpty);

    return _card(
      child: Column(
        children: [
          Row(
            children: [
              _iconBox(Icons.file_download_outlined, omanRed),

              const SizedBox(width: 9),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Order File",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: textDark,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Generate an Excel order from the selected items.",
                      style: TextStyle(color: textMuted, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: canGenerate ? generateOrder : null,
              icon: isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_rounded, size: 19),
              label: Text(
                isGenerating ? "Generating Order..." : "Generate Order",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: omanGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade600,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ),

          if (generatedFileBytes != null) ...[
            const SizedBox(height: 9),

            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () {
                  downloadFile(generatedFileBytes!);
                },
                icon: const Icon(Icons.save_alt_rounded, size: 18),
                label: const Text(
                  "Save Excel File",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: omanRed,
                  side: const BorderSide(color: omanRed),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // STATUS
  // ============================================================

  Widget _buildStatusCard() {
    final bool isSuccess = statusText.contains("✔");

    final bool isError =
        statusText.toLowerCase().contains("failed") ||
        statusText.toLowerCase().contains("error");

    final color = isSuccess
        ? omanGreen
        : isError
        ? omanRed
        : omanRed;

    final background = isSuccess
        ? Colors.green.shade50
        : isError
        ? Colors.red.shade50
        : const Color(0xfffff3f4);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess
                ? Icons.check_circle_rounded
                : isError
                ? Icons.error_outline_rounded
                : Icons.info_outline_rounded,
            color: color,
            size: 18,
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

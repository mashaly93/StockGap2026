import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  // COLORS
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
  static const double matchThreshold = 60;

  late final String storeCode = widget.storeCode;

  // ============================================================
  // MISSING ITEMS EXCEL
  //
  // SOURCE #1
  //
  // Used ONLY for:
  // Order + Missing Items
  // ============================================================

  List<List<String>> inventoryRows = [];

  // ============================================================
  // WAREHOUSE INVENTORY
  //
  // SOURCE FOR MATCHING / PRICES / STOCK ONLY
  //
  // NEVER USED AS AN ORDER SOURCE BY ITSELF.
  // ============================================================

  List<Map<String, dynamic>> orderRows = [];

  // ============================================================
  // GENERATED FILE
  // ============================================================

  Uint8List? generatedFileBytes;

  bool isGenerating = false;
  bool isSavingFile = false;

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
  // SELECTED ITEMS
  //
  // UI ONLY
  //
  // NEVER USED BY GENERATE ORDER
  // ============================================================

  final List<Map<String, dynamic>> selectedItems = [];

  // ============================================================
  // DRUG DETAILS
  //
  // SOURCE #2
  //
  // INDEPENDENT FROM MISSING ITEMS.
  //
  // NEVER CLEARED WHEN EXCEL IS SAVED.
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
  // SAVE DRUG DETAILS ITEMS
  // ============================================================

  Future<void> saveDrugDetailsItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final encoded = drugDetailsItems.map((item) => jsonEncode(item)).toList();

      await prefs.setStringList("drug_details_order_items", encoded);

      debugPrint("DRUG DETAILS ITEMS SAVED = ${encoded.length}");
    } catch (e) {
      debugPrint("ERROR SAVING DRUG DETAILS ITEMS: $e");
      rethrow;
    }
  }

  // ============================================================
  // CLEAR DRUG DETAILS
  //
  // ONLY CALLED BY USER
  // ============================================================

  Future<void> clearDrugDetailsItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove("drug_details_order_items");

      if (mounted) {
        setState(() {
          drugDetailsItems.clear();
        });
      }
    } catch (_) {
      // Do not stop the page if clearing fails.
    }
  }

  // ============================================================
  // DRUG DETAILS WAREHOUSE MATCH
  // ============================================================

  bool _isDrugDetailsForSelectedWarehouse(Map<String, dynamic> item) {
    if (selectedWarehouseId == null) {
      return false;
    }

    final selectedId = selectedWarehouseId!.trim().toLowerCase();

    final selectedName =
        selectedWarehouse?["name"]?.toString().trim().toLowerCase() ?? "";

    final possibleWarehouseValues = [
      item["warehouse"],
      item["warehouseId"],
      item["warehouseName"],
      item["storeId"],
      item["storeName"],
    ];

    final values = possibleWarehouseValues
        .where((value) => value != null)
        .map((value) => value.toString().trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList();

    // If the saved Drug Details item has no warehouse information,
    // allow it for the currently selected warehouse.
    if (values.isEmpty) {
      return true;
    }

    return values.any(
      (value) =>
          value == selectedId ||
          (selectedName.isNotEmpty && value == selectedName),
    );
  }

  // ============================================================
  // VISIBLE DRUG DETAILS
  // ============================================================

  List<Map<String, dynamic>> get visibleDrugDetailsItems {
    if (selectedWarehouseId == null) {
      return [];
    }

    return drugDetailsItems.where(_isDrugDetailsForSelectedWarehouse).toList();
  }

  // ============================================================
  // EDIT DRUG DETAILS QTY
  // ============================================================

  Future<void> editDrugDetailsQuantity(Map<String, dynamic> item) async {
    final controller = TextEditingController(
      text: _toInt(item["qty"]).toString(),
    );

    final stock = item["stock"] == null ? null : _toInt(item["stock"]);

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.edit_rounded, color: omanGreen),
              SizedBox(width: 8),
              Text(
                "Edit Quantity",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item["item"]?.toString() ?? "",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textDark,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Quantity",
                  prefixIcon: const Icon(
                    Icons.production_quantity_limits,
                    color: omanGreen,
                  ),
                  filled: true,
                  fillColor: const Color(0xffF8FAFD),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              if (stock != null) ...[
                const SizedBox(height: 8),
                Text(
                  "Stock: $stock",
                  style: const TextStyle(fontSize: 11, color: textMuted),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                final qty = int.tryParse(controller.text.trim());

                if (qty == null || qty <= 0) {
                  return;
                }

                if (stock != null && qty > stock) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Quantity cannot exceed stock ($stock)."),
                      backgroundColor: omanRed,
                    ),
                  );

                  return;
                }

                Navigator.pop(context, qty);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: omanGreen,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null) {
      return;
    }

    try {
      final originalIndex = drugDetailsItems.indexOf(item);

      if (originalIndex < 0) {
        return;
      }

      setState(() {
        drugDetailsItems[originalIndex]["qty"] = result;

        generatedFileBytes = null;
      });

      await saveDrugDetailsItems();

      if (mounted) {
        setState(() {
          statusText = "Drug Details quantity updated ✔";
        });
      }

      _showMessage("Quantity updated successfully.");
    } catch (e) {
      _showMessage("Could not save quantity: $e");
    }
  }

  // ============================================================
  // DELETE DRUG DETAILS ITEM
  // ============================================================

  Future<void> deleteDrugDetailsItem(Map<String, dynamic> item) async {
    final name = item["item"]?.toString() ?? "this item";

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            "Delete Item?",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text("Remove \"$name\" from Drug Details order?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel", style: TextStyle(color: textMuted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: omanRed,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    try {
      setState(() {
        drugDetailsItems.remove(item);
        generatedFileBytes = null;
      });

      await saveDrugDetailsItems();

      if (mounted) {
        setState(() {
          statusText = "Drug Details item deleted ✔";
        });
      }

      _showMessage("Drug Details item deleted.");
    } catch (e) {
      _showMessage("Could not delete item: $e");
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
  // STOCK
  // ============================================================

  dynamic _getStock(dynamic data) {
    if (data is! Map) {
      return null;
    }

    const keys = [
      "stock",
      "quantity",
      "qty",
      "availableQuantity",
      "availableStock",
      "currentStock",
      "balance",
      "onHand",
    ];

    for (final key in keys) {
      if (!data.containsKey(key)) {
        continue;
      }

      final value = data[key];

      if (value == null) {
        continue;
      }

      if (value is num) {
        return value.toInt();
      }

      final parsed = int.tryParse(value.toString().replaceAll(",", "").trim());

      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  // ============================================================
  // OFFER
  // ============================================================

  String _getOfferText(dynamic data) {
    if (data is! Map) {
      return "";
    }

    const keys = [
      "offer",
      "offers",
      "offerText",
      "promotion",
      "promotions",
      "discountOffer",
      "specialOffer",
      "promo",
    ];

    for (final key in keys) {
      if (!data.containsKey(key)) {
        continue;
      }

      final value = data[key];

      final formatted = _formatOfferValue(value);

      if (formatted.isNotEmpty) {
        return formatted;
      }
    }

    return "";
  }

  String _formatOfferValue(dynamic value) {
    if (value == null) {
      return "";
    }

    if (value is String) {
      return value.trim();
    }

    if (value is num || value is bool) {
      return value.toString();
    }

    if (value is List) {
      return value
          .map(_formatOfferValue)
          .where((x) => x.isNotEmpty)
          .join(" / ");
    }

    if (value is Map) {
      final parts = <String>[];

      value.forEach((key, val) {
        final formatted = _formatOfferValue(val);

        if (formatted.isNotEmpty) {
          parts.add("${key.toString()}: $formatted");
        }
      });

      return parts.join(" | ");
    }

    return value.toString().trim();
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
      generatedFileBytes = null;
      statusText = "Loading warehouse inventory...";
    });

    try {
      final inventoryRef = FirebaseFirestore.instance
          .collection("stores")
          .doc(warehouseId)
          .collection("inventory");

      final snap = await inventoryRef.get();

      final loadedRows = <Map<String, dynamic>>[];

      for (final doc in snap.docs) {
        final data = doc.data();

        final name = data["name"]?.toString().trim() ?? "";

        if (name.isEmpty) {
          continue;
        }

        final purchase = _toDouble(
          data["purchasePrice"] ??
              data["purchase_price"] ??
              data["costPrice"] ??
              data["cost_price"] ??
              data["buyPrice"] ??
              data["buy_price"] ??
              data["purchase"] ??
              data["price"],
        );

        final sale = _toDouble(
          data["salePrice"] ??
              data["sale_price"] ??
              data["sellingPrice"] ??
              data["selling_price"] ??
              data["sellPrice"] ??
              data["sell_price"] ??
              data["sale"] ??
              data["price"],
        );

        loadedRows.add({
          "id": doc.id,
          "name": name,
          "purchase": purchase,
          "sale": sale,
          "stock": _getStock(data),
          "offer": _getOfferText(data),
        });
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
  // PICK MISSING ITEMS EXCEL
  // ============================================================

  Future<void> pickInventory() async {
    try {
      final type = XTypeGroup(label: "Excel", extensions: ["xlsx"]);

      final file = await openFile(acceptedTypeGroups: [type]);

      if (file == null) {
        return;
      }

      final bytes = await File(file.path).readAsBytes();

      if (bytes.isEmpty) {
        throw Exception("Selected Excel file is empty.");
      }

      final rows = excelToRows(bytes);

      if (rows.length <= 1) {
        throw Exception("Excel file is empty or contains no data rows.");
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
  // FIND ITEM COLUMN
  // ============================================================

  int findItemColumn(List<String> header) {
    for (int i = 0; i < header.length; i++) {
      final value = header[i]
          .trim()
          .toLowerCase()
          .replaceAll("_", " ")
          .replaceAll("-", " ");

      if (value == "item" ||
          value == "items" ||
          value == "name" ||
          value == "product" ||
          value == "product name" ||
          value == "drug" ||
          value == "drug name" ||
          value == "medicine" ||
          value == "medicine name" ||
          value == "description" ||
          value == "item name") {
        return i;
      }
    }

    return 0;
  }

  // ============================================================
  // MERGE MISSING ITEMS
  //
  // SOURCE #1 ONLY
  //
  // inventoryRows = uploaded Excel
  //
  // NEVER:
  // Drug Details
  // Selected Items
  // Warehouse
  // ============================================================

  Map<String, Map<String, dynamic>> buildMergedMissingItems() {
    final Map<String, Map<String, dynamic>> merged = {};

    if (inventoryRows.length <= 1) {
      return merged;
    }

    final header = inventoryRows.first;

    final itemColumnIndex = findItemColumn(header);

    final qtyColumnIndex = findQtyColumn(header);

    for (int i = 1; i < inventoryRows.length; i++) {
      final row = inventoryRows[i];

      if (row.isEmpty || itemColumnIndex >= row.length) {
        continue;
      }

      final item = row[itemColumnIndex].trim();

      if (item.isEmpty) {
        continue;
      }

      int qty = 1;

      if (qtyColumnIndex >= 0 && qtyColumnIndex < row.length) {
        final qtyText = row[qtyColumnIndex].replaceAll(",", "").trim();

        qty = int.tryParse(qtyText) ?? 1;
      } else if (row.length > 1) {
        final qtyText = row[1].replaceAll(",", "").trim();

        qty = int.tryParse(qtyText) ?? 1;
      }

      if (qty <= 0) {
        qty = 1;
      }

      final key = normalizeForSearch(item);

      if (key.isEmpty) {
        continue;
      }

      if (merged.containsKey(key)) {
        merged[key]!["qty"] = _toInt(merged[key]!["qty"]) + qty;
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

    value = value.replaceAll(RegExp(r'\bsyrup\b'), 'syr');

    value = value.replaceAll(RegExp(r'\bsyp\b'), 'syr');

    value = value.replaceAll(RegExp(r'\bcream\b'), 'crm');

    value = value.replaceAll(RegExp(r'\bointment\b'), 'oint');

    value = value.replaceAll(RegExp(r'\bsuspension\b'), 'susp');

    value = value.replaceAll(RegExp(r'\bsolution\b'), 'sol');

    value = value.replaceAll(RegExp(r'\bdrops?\b'), 'drop');

    value = value.replaceAll(RegExp(r'\bsachets?\b'), 'sach');

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

        final score = wordSimilaritySimple(wordA, wordsB[i]);

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
  //
  // UI ONLY
  //
  // This creates Warehouse Matches.
  //
  // It does NOT define what Generate uses.
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
      final item = data["item"]?.toString() ?? "";

      final qty = _toInt(data["qty"]);

      double bestScore = 0;

      Map<String, dynamic>? bestWarehouse;

      for (final warehouse in orderRows) {
        final warehouseItem = warehouse["name"]?.toString().trim() ?? "";

        if (warehouseItem.isEmpty) {
          continue;
        }

        final score = calculateMatchScore(item, warehouseItem);

        if (score > bestScore) {
          bestScore = score;
          bestWarehouse = warehouse;
        }
      }

      if (bestScore >= matchThreshold && bestWarehouse != null) {
        final bestWarehouseItem = bestWarehouse["name"]?.toString() ?? "";

        results.add({
          "item": item,
          "qty": qty,
          "matchedItem": bestWarehouseItem,
          "score": bestScore,
          "purchase": _toDouble(bestWarehouse["purchase"]),
          "sale": _toDouble(bestWarehouse["sale"]),
          "stock": bestWarehouse["stock"],
          "offer": bestWarehouse["offer"]?.toString() ?? "",
          "itemId": bestWarehouse["id"]?.toString() ?? "",
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
  // ADD SELECTED
  //
  // UI ONLY
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

    final stock = result["stock"];

    final qty = _toInt(result["qty"]);

    if (stock != null && qty > _toInt(stock)) {
      _showMessage(
        "Requested quantity ($qty) exceeds stock (${_toInt(stock)}).",
      );
      return;
    }

    setState(() {
      selectedItems.add({...result, "added": true});

      result["added"] = true;

      generatedFileBytes = null;
    });

    _showMessage("${result["item"]} added ✔");
  }

  // ============================================================
  // REMOVE SELECTED
  //
  // UI ONLY
  // ============================================================

  void removeSelectedItem(Map<String, dynamic> result) {
    setState(() {
      selectedItems.removeWhere(
        (x) =>
            x["item"] == result["item"] &&
            x["matchedItem"] == result["matchedItem"],
      );

      result["added"] = false;

      generatedFileBytes = null;
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
            _emptyBox(
              "No items matched at ${matchThreshold.toStringAsFixed(0)}% or higher.",
            )
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
    final score = _toDouble(result["score"]);

    final added = result["added"] == true;

    final stock = result["stock"];

    final offer = result["offer"]?.toString() ?? "";

    final sale = _toDouble(result["sale"]);

    final qty = _toInt(result["qty"]);

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
                    _smallBadge(Icons.production_quantity_limits, "Qty $qty"),
                    _smallBadge(
                      Icons.payments_outlined,
                      "${sale.toStringAsFixed(3)} OMR",
                    ),
                    if (stock != null)
                      _smallBadge(
                        Icons.inventory_2_outlined,
                        "Stock ${_toInt(stock)}",
                      ),
                    if (offer.isNotEmpty)
                      _smallBadge(Icons.local_offer_outlined, offer),
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
    if (selectedWarehouseId == null) {
      return const SizedBox.shrink();
    }

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

    final visibleItems = visibleDrugDetailsItems;

    final total = _calculateDrugDetailsTotal(visibleItems);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBox(Icons.medication_rounded, omanGreen),
              const SizedBox(width: 9),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Drug Details Items",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textDark,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Items selected from Drug Details for this warehouse.",
                      style: TextStyle(fontSize: 10, color: textMuted),
                    ),
                  ],
                ),
              ),
              _countBadge("${visibleItems.length}", omanGreen),
            ],
          ),
          const SizedBox(height: 12),
          if (visibleItems.isEmpty)
            _emptyBox("No Drug Details items for this warehouse.")
          else
            ...visibleItems.asMap().entries.map(
              (entry) => _buildDrugDetailsRow(entry.value, entry.key),
            ),
          if (visibleItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildDrugDetailsTotalCard(total),
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              height: 37,
              child: OutlinedButton.icon(
                onPressed: clearDrugDetailsItems,
                icon: const Icon(Icons.delete_outline, size: 17),
                label: const Text(
                  "Clear All Drug Details Items",
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

    final qty = _toInt(item["qty"]);

    final warehouse = item["warehouse"]?.toString() ?? "";

    final matched = item["matchedItem"]?.toString() ?? "";

    final score = _toDouble(item["matchPercent"]);

    final sale = _toDouble(item["sale"]);

    final total = sale * qty;

    final stock = item["stock"];

    final offer = item["offer"]?.toString() ?? "";

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFD),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 3),
                if (matched.isNotEmpty)
                  Text(
                    "Matched: $matched",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: textMuted, fontSize: 10),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    _smallBadge(Icons.production_quantity_limits, "Qty $qty"),
                    _smallBadge(
                      Icons.shopping_cart_outlined,
                      "Sale ${sale.toStringAsFixed(3)}",
                    ),
                    if (stock != null)
                      _smallBadge(
                        Icons.inventory_2_outlined,
                        "Stock ${_toInt(stock)}",
                      ),
                    if (offer.isNotEmpty)
                      _smallBadge(Icons.local_offer_outlined, offer),
                    if (score > 0)
                      _smallBadge(
                        Icons.compare_arrows_rounded,
                        "${score.toStringAsFixed(0)}%",
                      ),
                  ],
                ),
                if (warehouse.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    "Warehouse: $warehouse",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                "Total",
                style: TextStyle(color: textMuted, fontSize: 9),
              ),
              const SizedBox(height: 2),
              Text(
                "${total.toStringAsFixed(3)} OMR",
                style: const TextStyle(
                  color: omanGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _roundActionButton(
                    icon: Icons.edit_rounded,
                    color: omanGreen,
                    onTap: () => editDrugDetailsQuantity(item),
                  ),
                  const SizedBox(width: 5),
                  _roundActionButton(
                    icon: Icons.delete_outline,
                    color: omanRed,
                    onTap: () => deleteDrugDetailsItem(item),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DRUG DETAILS TOTAL
  // ============================================================

  double _calculateDrugDetailsTotal(List<Map<String, dynamic>> items) {
    double total = 0;

    for (final item in items) {
      final qty = _toInt(item["qty"]);

      final sale = _toDouble(item["sale"]);

      total += qty * sale;
    }

    return total;
  }

  Widget _buildDrugDetailsTotalCard(double total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: omanGreen.withOpacity(.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.calculate_rounded,
              color: omanGreen,
              size: 18,
            ),
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              "Drug Details Total",
              style: TextStyle(
                color: omanGreen,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            "${total.toStringAsFixed(3)} OMR",
            style: const TextStyle(
              color: omanGreen,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ROUND ACTION BUTTON
  // ============================================================

  Widget _roundActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 29,
        height: 29,
        decoration: BoxDecoration(
          color: color.withOpacity(.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 15),
      ),
    );
  }

  // ============================================================
  // SAFE NUMBER
  // ============================================================

  double _toDouble(dynamic value) {
    if (value == null) {
      return 0;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString().replaceAll(",", "").trim()) ?? 0;
  }

  int _toInt(dynamic value) {
    if (value == null) {
      return 0;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString().replaceAll(",", "").trim()) ?? 0;
  }

  // ============================================================
  // ADD EXCEL ROW
  // ============================================================

  void _appendExcelRow(Sheet sheet, List<String> values) {
    sheet.appendRow(values.map((value) => TextCellValue(value)).toList());
  }

  // ============================================================
  // GENERATE ORDER
  //
  // ============================================================
  //
  // SOURCE #1 = Missing Items Excel
  //
  // SOURCE #2 = Drug Details
  //
  // SOURCE #3 = Selected Items
  //             NEVER USED
  //
  // Warehouse inventory:
  //             MATCHING / PRICE / STOCK ONLY
  //
  // ============================================================
  //
  // OUTPUT:
  //
  // Missing only:
  //   Order
  //   Missing Items
  //
  // Drug Details only:
  //   Drug Details Order
  //
  // Both:
  //   Order
  //   Missing Items
  //   Drug Details Order
  //
  // ============================================================

  Future<void> generateOrder() async {
    if (isGenerating) {
      return;
    }

    // ==========================================================
    // SOURCE 1
    // MISSING ITEMS
    // ==========================================================

    final mergedMissingItems = buildMergedMissingItems();

    // ==========================================================
    // SOURCE 2
    // DRUG DETAILS
    //
    // This is already filtered by selected warehouse.
    // ==========================================================

    final drugDetailsForWarehouse = visibleDrugDetailsItems;

    final hasMissing = mergedMissingItems.isNotEmpty;

    final hasDrugDetails = drugDetailsForWarehouse.isNotEmpty;

    // ==========================================================
    // NOTHING TO GENERATE
    // ==========================================================

    if (!hasMissing && !hasDrugDetails) {
      if (mounted) {
        setState(() {
          statusText =
              "Please upload Missing Items Excel or add Drug Details items.";
        });
      }

      return;
    }

    // ==========================================================
    // WAREHOUSE
    //
    // A warehouse is still required because:
    //
    // - Missing Items must be matched against it.
    // - Drug Details are filtered by warehouse.
    //
    // BUT orderRows itself is NOT required when generating
    // Drug Details only.
    // ==========================================================

    if (selectedWarehouseId == null) {
      if (mounted) {
        setState(() {
          statusText = "Please select a Warehouse first.";
        });
      }

      return;
    }

    // ==========================================================
    // MISSING ITEMS NEED WAREHOUSE INVENTORY
    //
    // Drug Details do NOT need orderRows because they already
    // contain their matched item / prices.
    // ==========================================================

    if (hasMissing && orderRows.isEmpty) {
      if (mounted) {
        setState(() {
          statusText =
              "Warehouse inventory is empty. Please select a warehouse with inventory.";
        });
      }

      return;
    }

    if (!mounted) return;

    setState(() {
      isGenerating = true;
      statusText = "Preparing Order...";
      generatedFileBytes = null;
    });

    try {
      // ========================================================
      // CREATE WORKBOOK
      // ========================================================

      final excel = Excel.createExcel();

      // ========================================================
      // CREATE ONLY THE SHEETS WE NEED
      //
      // IMPORTANT:
      //
      // We reuse Sheet1 instead of creating the target sheet
      // first, to avoid duplicate/default-sheet conflicts.
      // ========================================================

      Sheet? orderSheet;
      Sheet? missingSheet;
      Sheet? drugDetailsSheet;

      if (hasMissing) {
        // Default Sheet1 -> Order
        excel.rename("Sheet1", "Order");

        orderSheet = excel["Order"];

        missingSheet = excel["Missing Items"];

        // Drug Details is created only if needed.
        if (hasDrugDetails) {
          drugDetailsSheet = excel["Drug Details Order"];
        }
      } else {
        // Drug Details only.
        //
        // Reuse Sheet1 so there is no unwanted Sheet1.
        excel.rename("Sheet1", "Drug Details Order");

        drugDetailsSheet = excel["Drug Details Order"];
      }

      // ========================================================
      // MISSING / ORDER
      // ========================================================

      double totalSale = 0;

      int matchedCount = 0;

      int missingCount = 0;

      int processedMissing = 0;

      final List<Map<String, dynamic>> notMatchedItems = [];

      if (hasMissing && orderSheet != null && missingSheet != null) {
        // ------------------------------------------------------
        // ORDER HEADERS
        //
        // IMPORTANT:
        // Matched Item + Match % are INCLUDED.
        // ------------------------------------------------------

        _appendExcelRow(orderSheet, [
          "Item",
          "Qty",
          "Matched Item",
          "Match %",
          "Purchase Price",
          "Sale Price",
          "Offers",
          "Total",
        ]);

        // ------------------------------------------------------
        // MISSING HEADERS
        // ------------------------------------------------------

        _appendExcelRow(missingSheet, [
          "Item",
          "Qty",
          "Similar Item",
          "Match %",
          "Purchase Price",
          "Sale Price",
          "Offers",
          "Total",
        ]);

        // ------------------------------------------------------
        // PROCESS MISSING ITEMS
        //
        // SOURCE = Excel only.
        // ------------------------------------------------------

        for (final data in mergedMissingItems.values) {
          final item = data["item"]?.toString().trim() ?? "";

          final qty = _toInt(data["qty"]);

          if (item.isEmpty || qty <= 0) {
            continue;
          }

          // ----------------------------------------------------
          // FIND BEST WAREHOUSE MATCH
          // ----------------------------------------------------

          double bestScore = 0;

          Map<String, dynamic>? bestWarehouse;

          for (final warehouse in orderRows) {
            final warehouseItem = warehouse["name"]?.toString().trim() ?? "";

            if (warehouseItem.isEmpty) {
              continue;
            }

            final score = calculateMatchScore(item, warehouseItem);

            if (score > bestScore) {
              bestScore = score;
              bestWarehouse = warehouse;
            }
          }

          // ====================================================
          // MATCH >= 60%
          // ====================================================

          if (bestWarehouse != null && bestScore >= matchThreshold) {
            final matchedItem = bestWarehouse["name"]?.toString().trim() ?? "";

            final purchase = _toDouble(bestWarehouse["purchase"]);

            final sale = _toDouble(bestWarehouse["sale"]);

            final offer = bestWarehouse["offer"]?.toString().trim() ?? "";

            final total = sale * qty;

            totalSale += total;

            matchedCount++;

            _appendExcelRow(orderSheet, [
              item,
              qty.toString(),
              matchedItem,
              "${bestScore.toStringAsFixed(0)}%",
              purchase.toStringAsFixed(3),
              sale.toStringAsFixed(3),
              offer,
              total.toStringAsFixed(3),
            ]);
          }
          // ====================================================
          // NO MATCH >= 60%
          //
          // Keep the best similar warehouse item anyway.
          // ====================================================
          else {
            missingCount++;

            notMatchedItems.add({
              "item": item,
              "qty": qty,
              "similarItem":
                  bestWarehouse?["name"]?.toString().trim() ?? "NOT MATCHED",
              "score": bestScore,
              "purchase": bestWarehouse?["purchase"] ?? 0,
              "sale": bestWarehouse?["sale"] ?? 0,
              "offer": bestWarehouse?["offer"]?.toString().trim() ?? "",
            });
          }

          processedMissing++;

          if (mounted) {
            setState(() {
              statusText =
                  "Processing Missing Items "
                  "$processedMissing / "
                  "${mergedMissingItems.length}...";
            });
          }
        }

        // ------------------------------------------------------
        // SORT NOT MATCHED BY MATCH %
        //
        // Highest score first.
        // ------------------------------------------------------

        notMatchedItems.sort((a, b) {
          final scoreA = _toDouble(a["score"]);

          final scoreB = _toDouble(b["score"]);

          return scoreB.compareTo(scoreA);
        });

        // ------------------------------------------------------
        // NOT MATCHED ITEMS
        // ------------------------------------------------------

        if (notMatchedItems.isNotEmpty) {
          _appendExcelRow(missingSheet, ["", "", "", "", "", "", "", ""]);

          _appendExcelRow(missingSheet, [
            "NOT MATCHED ITEMS",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
          ]);

          _appendExcelRow(missingSheet, [
            "Item",
            "Qty",
            "Similar Item",
            "Match %",
            "Purchase Price",
            "Sale Price",
            "Offers",
            "Total",
          ]);

          for (final data in notMatchedItems) {
            final item = data["item"]?.toString() ?? "";

            final qty = _toInt(data["qty"]);

            final similarItem =
                data["similarItem"]?.toString() ?? "NOT MATCHED";

            final score = _toDouble(data["score"]);

            final purchase = _toDouble(data["purchase"]);

            final sale = _toDouble(data["sale"]);

            final offer = data["offer"]?.toString() ?? "";

            final total = sale * qty;

            _appendExcelRow(missingSheet, [
              item,
              qty.toString(),
              similarItem,
              "${score.toStringAsFixed(0)}%",
              purchase.toStringAsFixed(3),
              sale.toStringAsFixed(3),
              offer,
              total.toStringAsFixed(3),
            ]);
          }
        }

        // ------------------------------------------------------
        // ORDER TOTAL
        // ------------------------------------------------------

        _appendExcelRow(orderSheet, [
          "",
          "",
          "",
          "",
          "",
          "",
          "TOTAL",
          totalSale.toStringAsFixed(3),
        ]);
      }

      // ========================================================
      // DRUG DETAILS ORDER
      //
      // SOURCE = DRUG DETAILS ONLY
      //
      // NEVER selectedItems.
      // NEVER Missing Items.
      // NEVER rematched against warehouse.
      // ========================================================

      double drugDetailsTotal = 0;

      int processedDrugDetails = 0;

      if (hasDrugDetails && drugDetailsSheet != null) {
        _appendExcelRow(drugDetailsSheet, [
          "Item",
          "Qty",
          "Matched Item",
          "Match %",
          "Purchase Price",
          "Sale Price",
          "Offers",
          "Total",
        ]);

        for (final item in drugDetailsForWarehouse) {
          final name = item["item"]?.toString().trim() ?? "";

          final qty = _toInt(item["qty"]);

          if (name.isEmpty || qty <= 0) {
            continue;
          }

          final matchedItem = item["matchedItem"]?.toString().trim() ?? "";

          final matchPercent = _toDouble(item["matchPercent"]);

          final purchase = _toDouble(item["purchase"]);

          final sale = _toDouble(item["sale"]);

          final offer = item["offer"]?.toString().trim() ?? "";

          final total = sale * qty;

          drugDetailsTotal += total;

          _appendExcelRow(drugDetailsSheet, [
            name,
            qty.toString(),
            matchedItem,
            matchPercent > 0 ? "${matchPercent.toStringAsFixed(0)}%" : "",
            purchase.toStringAsFixed(3),
            sale.toStringAsFixed(3),
            offer,
            total.toStringAsFixed(3),
          ]);

          processedDrugDetails++;

          if (mounted) {
            setState(() {
              statusText =
                  "Processing Drug Details "
                  "$processedDrugDetails / "
                  "${drugDetailsForWarehouse.length}...";
            });
          }
        }

        _appendExcelRow(drugDetailsSheet, [
          "",
          "",
          "",
          "",
          "",
          "",
          "TOTAL",
          drugDetailsTotal.toStringAsFixed(3),
        ]);
      }

      // ========================================================
      // ENCODE
      // ========================================================

      if (mounted) {
        setState(() {
          statusText = "Creating Excel file...";
        });
      }

      final encoded = excel.encode();

      if (encoded == null || encoded.isEmpty) {
        throw Exception("Excel encoder returned an empty file.");
      }

      final bytes = Uint8List.fromList(encoded);

      // ========================================================
      // GENERATED SHEETS
      // ========================================================

      final generatedSheets = <String>[];

      if (hasMissing) {
        generatedSheets.add("Order");
        generatedSheets.add("Missing Items");
      }

      if (hasDrugDetails) {
        generatedSheets.add("Drug Details Order");
      }

      // ========================================================
      // DONE
      // ========================================================

      if (!mounted) return;

      setState(() {
        generatedFileBytes = bytes;

        isGenerating = false;

        if (hasMissing && hasDrugDetails) {
          statusText =
              "Excel generated successfully ✔\n"
              "Order • Missing Items • Drug Details Order";
        } else if (hasMissing) {
          statusText =
              "Excel generated successfully ✔\n"
              "Order • Missing Items\n"
              "$matchedCount matched • "
              "$missingCount missing";
        } else {
          statusText =
              "Excel generated successfully ✔\n"
              "Drug Details Order";
        }
      });

      if (hasDrugDetails) {
        await clearDrugDetailsItems();
      }

      _showMessage(
        "Excel generated successfully: "
        "${generatedSheets.join(" • ")}",
      );
    } catch (e, stack) {
      debugPrint("GENERATE ORDER ERROR: $e");

      debugPrint(stack.toString());

      if (!mounted) return;

      setState(() {
        isGenerating = false;
        generatedFileBytes = null;

        statusText = "Error generating Excel:\n$e";
      });

      _showMessage("Could not generate Excel file.");
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

    // Count both independent sources.
    //
    // This does NOT use selectedItems.
    final missingCount = buildMergedMissingItems().length;

    final drugDetailsCount = visibleDrugDetailsItems.length;

    final order = {
      "fileName": fileName,
      "filePath": filePath,
      "date": DateFormat("yyyy-MM-dd").format(DateTime.now()),
      "items": missingCount + drugDetailsCount,
    };

    history.add(jsonEncode(order));

    await prefs.setStringList("orders", history);
  }

  Future<void> downloadFile(Uint8List bytes) async {
    if (bytes.isEmpty) {
      _showMessage("The generated Excel file is empty.");
      return;
    }

    if (isSavingFile) {
      return;
    }

    if (!mounted) return;

    setState(() {
      isSavingFile = true;
      statusText = "Saving Excel file...";
    });

    try {
      final location = await getSaveLocation(
        suggestedName: "Order.xlsx",
        acceptedTypeGroups: [
          XTypeGroup(label: "Excel", extensions: const ["xlsx"]),
        ],
      );

      if (location == null) {
        if (!mounted) return;

        setState(() {
          isSavingFile = false;
          statusText = "Save cancelled.";
        });

        return;
      }

      String path = location.path.trim();

      if (path.isEmpty) {
        throw Exception("Invalid save location.");
      }

      if (!path.toLowerCase().endsWith(".xlsx")) {
        path = "$path.xlsx";
      }

      debugPrint("SAVING EXCEL TO: $path");

      final fileName = path.split(RegExp(r'[\\/]')).last;

      final xFile = XFile.fromData(
        bytes,
        name: fileName,
        mimeType:
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      );

      await xFile.saveTo(path);

      final verifyFile = XFile(path);

      final savedBytes = await verifyFile.length();

      if (savedBytes <= 0) {
        throw Exception("Excel file was not saved correctly.");
      }

      debugPrint(
        "EXCEL SAVED SUCCESSFULLY: "
        "$path ($savedBytes bytes)",
      );

      // --------------------------------------------------------
      // SAVE HISTORY
      // --------------------------------------------------------

      try {
        await saveOrderLocally(fileName: fileName, filePath: path);

        debugPrint("ORDER HISTORY SAVED SUCCESSFULLY");
      } catch (historyError, historyStack) {
        debugPrint("WARNING: COULD NOT SAVE ORDER HISTORY");

        debugPrint("HISTORY ERROR: $historyError");

        debugPrint(historyStack.toString());
      }

      // --------------------------------------------------------
      // IMPORTANT:
      //
      // DO NOT CLEAR DRUG DETAILS.
      // --------------------------------------------------------

      if (!mounted) return;

      setState(() {
        isSavingFile = false;

        statusText = "Excel saved successfully ✔\n$path";
      });

      _showMessage("Excel file saved successfully.");

      resetScreen();
    } catch (e, stackTrace) {
      debugPrint("ERROR SAVING EXCEL: $e");

      debugPrint(stackTrace.toString());

      if (!mounted) return;

      setState(() {
        isSavingFile = false;

        statusText = "Error saving Excel file:\n$e";
      });

      _showMessage("Could not save Excel file.");
    }
  }

  // ============================================================
  // RESET
  //
  // IMPORTANT:
  //
  // DRUG DETAILS IS NOT CLEARED.
  // ============================================================

  void resetScreen() {
    if (!mounted) return;

    setState(() {
      inventoryRows.clear();

      orderRows.clear();

      warehouseSearchResults.clear();

      selectedItems.clear();

      generatedFileBytes = null;

      inventoryFileName = null;

      selectedWarehouseId = null;

      selectedWarehouse = null;

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
                      "Upload Missing Items and/or use Drug Details, then choose a warehouse and generate your order.",
                ),

                const SizedBox(height: 11),

                _buildInputCards(),

                const SizedBox(height: 22),

                if (selectedWarehouseId != null) ...[
                  _sectionTitle(
                    icon: Icons.medication_rounded,
                    title: "Drug Details",
                    subtitle:
                        "Review, edit or delete Drug Details items. They are generated in a separate sheet.",
                  ),
                  const SizedBox(height: 11),
                  buildDrugDetailsItemsCard(),
                  const SizedBox(height: 22),
                ],

                _sectionTitle(
                  icon: Icons.warehouse_rounded,
                  title: "Warehouse",
                  subtitle: "Choose the warehouse you want to match against.",
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
                        "Review matches from the uploaded Missing Items Excel list.",
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
    final itemCount = buildMergedMissingItems().length;

    final drugCount = selectedWarehouseId == null
        ? drugDetailsItems.length
        : visibleDrugDetailsItems.length;

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
                  "Upload missing items and/or use Drug Details, choose a warehouse and generate your order.",
                  style: TextStyle(
                    color: textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (itemCount > 0 || drugCount > 0)
            _countBadge("${itemCount + drugCount}", omanGreen),
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
        warehouseSearchResults.isNotEmpty || visibleDrugDetailsItems.isNotEmpty;

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
    final count = selectedWarehouseId == null
        ? drugDetailsItems.length
        : visibleDrugDetailsItems.length;

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
                  count == 0 ? "No items added" : "$count items saved",
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
    final String whatsappNumber =
        selectedWarehouse?["whatsapp"]?.toString().trim() ?? "";

    final String warehouseName =
        selectedWarehouse?["name"]?.toString().trim() ?? "";

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
                  color: omanGreen,
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

                      generatedFileBytes = null;

                      statusText = "Loading warehouse inventory...";
                    });

                    await loadWarehouseItems(value);
                  },
                ),
          if (selectedWarehouseId != null && whatsappNumber.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.phone,
                      color: Colors.green,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          warehouseName.isEmpty
                              ? "Warehouse WhatsApp"
                              : "$warehouseName WhatsApp",
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: textDark,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          whatsappNumber,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // WAREHOUSE INFO
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
      constraints: const BoxConstraints(maxWidth: 180),
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
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, color: textMuted),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SELECTED SUMMARY
  //
  // UI ONLY
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
    final hasMissing = buildMergedMissingItems().isNotEmpty;

    final hasDrugDetails = visibleDrugDetailsItems.isNotEmpty;

    final hasAnythingToGenerate = hasMissing || hasDrugDetails;

    // ----------------------------------------------------------
    // IMPORTANT:
    //
    // Missing Items requires warehouse inventory.
    //
    // Drug Details does NOT require orderRows because its
    // stored items already contain their matched/pricing data.
    // ----------------------------------------------------------

    final missingReady =
        !hasMissing || (selectedWarehouseId != null && orderRows.isNotEmpty);

    final canGenerate =
        hasAnythingToGenerate &&
        selectedWarehouseId != null &&
        missingReady &&
        !isGenerating;

    String description;

    if (hasMissing && hasDrugDetails) {
      description =
          "Generate 3 sheets: Order, Missing Items and Drug Details Order.";
    } else if (hasMissing) {
      description =
          "Generate Order and Missing Items from the uploaded Excel list.";
    } else if (hasDrugDetails) {
      description = "Generate Drug Details Order from Drug Details items.";
    } else {
      description = "Upload Missing Items or add Drug Details items.";
    }

    return _card(
      child: Column(
        children: [
          Row(
            children: [
              _iconBox(Icons.file_download_outlined, omanRed),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Order File",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(color: textMuted, fontSize: 10),
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
                onPressed: isGenerating
                    ? null
                    : () => downloadFile(generatedFileBytes!),
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

    final statusBackground = isSuccess
        ? Colors.green.shade50
        : isError
        ? Colors.red.shade50
        : const Color(0xfffff3f4);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: statusBackground,
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

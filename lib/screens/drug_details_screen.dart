import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/drug_model.dart';
import '../service/drug_service.dart';

// ============================================================
// OMAN COLORS
// ============================================================

const Color omanRed = Color(0xffD22730);
const Color omanGreen = Color(0xff009A44);
const Color omanDarkGreen = Color(0xff007A35);

const Color omanLightRed = Color(0xfffff0f1);
const Color omanLightGreen = Color(0xffedf9f2);

// ============================================================
// WAREHOUSE RESULT
// ============================================================

class WarehouseResult {
  final String storeCode;
  final String warehouseName;
  final String itemName;
  final double price;
  final double matchPercent;

  // اسم الدواء الذي تم البحث عنه
  final String searchedDrugName;

  WarehouseResult({
    required this.storeCode,
    required this.warehouseName,
    required this.itemName,
    required this.price,
    required this.matchPercent,
    required this.searchedDrugName,
  });
}

// ============================================================
// DRUG DETAILS SCREEN
// ============================================================

class DrugDetailsScreen extends StatefulWidget {
  final DrugModel drug;

  const DrugDetailsScreen({super.key, required this.drug});

  @override
  State<DrugDetailsScreen> createState() => _DrugDetailsScreenState();
}

class _DrugDetailsScreenState extends State<DrugDetailsScreen> {
  // ============================================================
  // SERVICES
  // ============================================================

  final DrugService service = DrugService();

  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // ============================================================
  // WAREHOUSE CODES
  // ============================================================

  final List<String> warehouseCodes = ['M001', 'M002', 'M003', 'M004'];

  // ============================================================
  // ALTERNATIVES
  // ============================================================

  List<DrugModel> alternatives = [];

  bool loadingAlternatives = true;

  // ============================================================
  // ORIGINAL WAREHOUSE SEARCH
  // ============================================================

  List<WarehouseResult> warehouseResults = [];

  bool searchingWarehouses = false;

  bool warehouseSearchDone = false;

  // اسم الدواء الذي يتم البحث عنه حاليًا
  String currentWarehouseSearchName = '';

  // ============================================================
  // QUANTITY
  // ============================================================

  final TextEditingController quantityController = TextEditingController(
    text: '1',
  );

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    loadAlternatives();
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    quantityController.dispose();

    super.dispose();
  }

  // ============================================================
  // LOAD ALTERNATIVES
  // ============================================================

  Future<void> loadAlternatives() async {
    try {
      final result = await service.getAlternatives(widget.drug);

      if (!mounted) return;

      setState(() {
        alternatives = result;
        loadingAlternatives = false;
      });
    } catch (e) {
      debugPrint('ERROR LOADING ALTERNATIVES: $e');

      if (!mounted) return;

      setState(() {
        alternatives = [];
        loadingAlternatives = false;
      });
    }
  }

  // ============================================================
  // NORMALIZE WAREHOUSE TEXT
  // ============================================================

  String normalizeForWarehouse(String value) {
    String text = value.toLowerCase().trim();

    text = text
        .replaceAll('&', ' and ')
        .replaceAll('/', ' ')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .replaceAll('.', ' ')
        .replaceAll(',', ' ')
        .replaceAll('(', ' ')
        .replaceAll(')', ' ')
        .replaceAll('[', ' ')
        .replaceAll(']', ' ');

    text = text.replaceAll(RegExp(r'\s+'), ' ');

    final replacements = <String, String>{
      'tablets': 'tab',
      'tablet': 'tab',
      'tabs': 'tab',
      'capsules': 'cap',
      'capsule': 'cap',
      'caps': 'cap',
      'syr': 'syrup',
      'syp': 'syrup',
      'syrup': 'syrup',
      'inj': 'injection',
      'injection': 'injection',
      'amp': 'ampoule',
      'ampoule': 'ampoule',
      'crm': 'cream',
      'cream': 'cream',
      'oint': 'ointment',
      'ointment': 'ointment',
    };

    final words = text.split(' ');

    final normalizedWords = words.map((word) {
      return replacements[word] ?? word;
    }).toList();

    return normalizedWords.join(' ').trim();
  }

  // ============================================================
  // WAREHOUSE WORDS
  // ============================================================

  List<String> warehouseWords(String value) {
    final ignoredWords = <String>{
      'tab',
      'cap',
      'syrup',
      'injection',
      'ampoule',
      'cream',
      'ointment',
      'tablet',
      'capsule',
      'ml',
      'mg',
      'gm',
      'g',
      'kg',
      'mcg',
      'iu',
      'pc',
      'pk',
      'pack',
      'box',
      'bt',
      's',
      'the',
      'and',
      'for',
    };

    return normalizeForWarehouse(value)
        .split(' ')
        .where(
          (word) =>
              word.isNotEmpty &&
              !ignoredWords.contains(word) &&
              !RegExp(r'^\d+$').hasMatch(word),
        )
        .toList();
  }

  // ============================================================
  // WAREHOUSE NUMBERS
  // ============================================================

  List<String> warehouseNumbers(String value) {
    return RegExp(r'\d+(?:\.\d+)?')
        .allMatches(normalizeForWarehouse(value))
        .map((match) => match.group(0)!)
        .toList();
  }

  // ============================================================
  // SIMPLE WORD SIMILARITY
  // ============================================================

  double simpleWordSimilarity(String a, String b) {
    if (a == b) return 100;

    if (a.isEmpty || b.isEmpty) {
      return 0;
    }

    final int maxLength = a.length > b.length ? a.length : b.length;

    int differences = 0;

    final int minLength = a.length < b.length ? a.length : b.length;

    for (int i = 0; i < minLength; i++) {
      if (a[i] != b[i]) {
        differences++;
      }
    }

    differences += maxLength - minLength;

    final double score = 100 - ((differences / maxLength) * 100);

    return score.clamp(0, 100);
  }

  // ============================================================
  // WAREHOUSE SIMILARITY
  // ============================================================

  double warehouseSimilarity(String original, String warehouseItem) {
    final originalWords = warehouseWords(original);

    final warehouseItemWords = warehouseWords(warehouseItem);

    if (originalWords.isEmpty || warehouseItemWords.isEmpty) {
      return 0;
    }

    // ----------------------------------------------------------
    // FIRST WORD
    // ----------------------------------------------------------

    final double firstWordScore = simpleWordSimilarity(
      originalWords.first,
      warehouseItemWords.first,
    );

    if (firstWordScore < 60) {
      return 0;
    }

    // ----------------------------------------------------------
    // MATCH WORDS
    // ----------------------------------------------------------

    int matchedWords = 0;

    double totalWordScore = 0;

    for (final originalWord in originalWords) {
      double bestScore = 0;

      for (final warehouseWord in warehouseItemWords) {
        final score = simpleWordSimilarity(originalWord, warehouseWord);

        if (score > bestScore) {
          bestScore = score;
        }
      }

      if (bestScore >= 80) {
        matchedWords++;

        totalWordScore += bestScore;
      }
    }

    final double averageWordScore = totalWordScore / originalWords.length;

    // ----------------------------------------------------------
    // NUMBERS
    // ----------------------------------------------------------

    final originalNumbers = warehouseNumbers(original);

    final warehouseNumbersList = warehouseNumbers(warehouseItem);

    double numberScore = 100;

    if (originalNumbers.isNotEmpty) {
      int matchedNumbers = 0;

      for (final number in originalNumbers) {
        if (warehouseNumbersList.contains(number)) {
          matchedNumbers++;
        }
      }

      numberScore = (matchedNumbers / originalNumbers.length) * 100;
    }

    // ----------------------------------------------------------
    // FINAL SCORE
    // ----------------------------------------------------------

    final double wordMatchRatio = matchedWords / originalWords.length;

    final double wordScore =
        (averageWordScore * 0.75) + (wordMatchRatio * 100 * 0.25);

    final double finalScore = (wordScore * 0.75) + (numberScore * 0.25);

    return finalScore.clamp(0, 100);
  }

  // ============================================================
  // SEARCH WAREHOUSES - ORIGINAL DRUG
  //
  // هذا البحث خاص بالدواء الأصلي فقط.
  // ============================================================

  Future<void> searchWarehouses({String? drugName}) async {
    if (searchingWarehouses) return;

    final String searchName = (drugName ?? widget.drug.tradeName).trim();

    if (searchName.isEmpty) {
      return;
    }

    setState(() {
      searchingWarehouses = true;
      warehouseSearchDone = false;
      warehouseResults = [];
      currentWarehouseSearchName = searchName;
    });

    final List<WarehouseResult> found = await searchWarehouseResults(
      searchName,
    );

    if (!mounted) return;

    setState(() {
      warehouseResults = found;
      searchingWarehouses = false;
      warehouseSearchDone = true;
    });

    // ----------------------------------------------------------
    // NOT FOUND
    // ----------------------------------------------------------

    if (found.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$searchName is not available in any warehouse '
            'with a match percentage of 60% or higher',
          ),
          backgroundColor: omanRed,
        ),
      );
    }
  }

  // ============================================================
  // SEARCH WAREHOUSE RESULTS
  //
  // هذه الدالة لا تغير أي State في الشاشة.
  //
  // تستخدم للدواء الأصلي والبدائل.
  // ============================================================

  Future<List<WarehouseResult>> searchWarehouseResults(
    String searchName,
  ) async {
    final List<WarehouseResult> found = [];

    for (final String storeCode in warehouseCodes) {
      try {
        // ------------------------------------------------------
        // STORE DATA
        // ------------------------------------------------------

        final DocumentSnapshot<Map<String, dynamic>> storeSnapshot =
            await firestore.collection('stores').doc(storeCode).get();

        final Map<String, dynamic>? storeData = storeSnapshot.data();

        final String warehouseName = getWarehouseName(storeData, storeCode);

        // ------------------------------------------------------
        // INVENTORY
        // ------------------------------------------------------

        final QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
            .collection('stores')
            .doc(storeCode)
            .collection('inventory')
            .get();

        WarehouseResult? bestResult;

        double bestScore = 0;

        // ------------------------------------------------------
        // SEARCH INVENTORY
        // ------------------------------------------------------

        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in snapshot.docs) {
          final Map<String, dynamic> data = doc.data();

          final String itemName = getItemName(data);

          if (itemName.isEmpty) {
            continue;
          }

          final double score = warehouseSimilarity(searchName, itemName);

          if (score >= 60 && score > bestScore) {
            bestScore = score;

            bestResult = WarehouseResult(
              storeCode: storeCode,
              warehouseName: warehouseName,
              itemName: itemName,
              price: getPrice(data),
              matchPercent: score,
              searchedDrugName: searchName,
            );
          }
        }

        if (bestResult != null) {
          found.add(bestResult);
        }
      } catch (e) {
        debugPrint('ERROR STORE $storeCode: $e');
      }
    }

    // ----------------------------------------------------------
    // SORT BY MATCH
    // ----------------------------------------------------------

    found.sort((a, b) => b.matchPercent.compareTo(a.matchPercent));

    return found;
  }

  // ============================================================
  // GET WAREHOUSE NAME
  // ============================================================

  String getWarehouseName(Map<String, dynamic>? data, String storeCode) {
    if (data == null) {
      return storeCode;
    }

    final possibleNames = [data['name'], data['username'], data['storeName']];

    for (final value in possibleNames) {
      final String name = value?.toString().trim() ?? '';

      if (name.isNotEmpty) {
        return name;
      }
    }

    return storeCode;
  }

  // ============================================================
  // GET ITEM NAME
  // ============================================================

  String getItemName(Map<String, dynamic> data) {
    final possibleNames = [
      data['itemName'],
      data['name'],
      data['item'],
      data['productName'],
      data['tradeName'],
    ];

    for (final value in possibleNames) {
      final String name = value?.toString().trim() ?? '';

      if (name.isNotEmpty) {
        return name;
      }
    }

    return '';
  }

  // ============================================================
  // GET PRICE
  // ============================================================

  double getPrice(Map<String, dynamic> data) {
    final possiblePrices = [
      data['price'],
      data['whPrice'],
      data['warehousePrice'],
      data['purchasePrice'],
      data['salePrice'],
    ];

    for (final value in possiblePrices) {
      if (value is num) {
        return value.toDouble();
      }

      if (value != null) {
        String priceText = value.toString().trim();

        priceText = priceText
            .replaceAll(',', '')
            .replaceAll('OMR', '')
            .replaceAll('ر.ع.', '')
            .trim();

        final double? parsed = double.tryParse(priceText);

        if (parsed != null) {
          return parsed;
        }
      }
    }

    return 0;
  }

  // ============================================================
  // GET QUANTITY
  // ============================================================

  int getQuantity() {
    final int? quantity = int.tryParse(quantityController.text.trim());

    if (quantity == null || quantity <= 0) {
      return 1;
    }

    return quantity;
  }

  // ============================================================
  // ADD DRUG TO ORDER
  // ============================================================

  Future<void> addDrugToOrder(WarehouseResult result) async {
    final int quantity = getQuantity();

    final prefs = await SharedPreferences.getInstance();

    const String key = 'drug_details_order_items';

    final String? saved = prefs.getString(key);

    List<dynamic> items = [];

    if (saved != null && saved.isNotEmpty) {
      try {
        items = jsonDecode(saved);
      } catch (_) {
        items = [];
      }
    }

    // ==========================================================
    // مهم:
    // نستخدم اسم الدواء الذي تم البحث عنه
    //
    // لو بحثت عن الأصلي:
    // item = original drug
    //
    // لو بحثت عن بديل:
    // item = alternative drug
    // ==========================================================

    final String itemName = result.searchedDrugName.trim();

    final String matchedItem = result.itemName.trim();

    bool merged = false;

    // ==========================================================
    // MERGE SAME ITEM
    // ==========================================================

    for (final item in items) {
      if (item is Map<String, dynamic>) {
        final String oldItem = item['item']?.toString() ?? '';

        final String oldWarehouse = item['warehouse']?.toString() ?? '';

        final String oldMatched = item['matchedItem']?.toString() ?? '';

        if (oldItem == itemName &&
            oldWarehouse == result.storeCode &&
            oldMatched == matchedItem) {
          final int oldQuantity =
              int.tryParse(item['qty']?.toString() ?? '') ?? 0;

          item['qty'] = oldQuantity + quantity;

          merged = true;

          break;
        }
      }
    }

    // ==========================================================
    // ADD NEW ITEM
    // ==========================================================

    if (!merged) {
      items.add({
        'item': itemName,
        'qty': quantity,
        'warehouse': result.storeCode,
        'warehouseName': result.warehouseName,
        'matchedItem': result.itemName,
        'matchPercent': result.matchPercent,
        'purchase': result.price,
        'sale': result.price,
        'registration': widget.drug.registration,
        'manufacturer': widget.drug.manufacturer,
        'addedAt': DateTime.now().toIso8601String(),
      });
    }

    await prefs.setString(key, jsonEncode(items));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$itemName added to order '
          'from ${result.warehouseName}',
        ),
        backgroundColor: omanGreen,
      ),
    );
  }

  // ============================================================
  // WAREHOUSE RESULTS
  // ============================================================

  Widget buildWarehouseResults() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14, bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ======================================================
          // HEADER
          // ======================================================

          Row(
            children: [
              const Icon(Icons.warehouse_rounded, color: omanRed),

              const SizedBox(width: 8),

              const Expanded(
                child: Text(
                  'Available in Warehouses',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: omanLightRed,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${warehouseResults.length}',
                  style: const TextStyle(
                    color: omanRed,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ======================================================
          // SEARCHED DRUG
          // ======================================================
          Text(
            'Search: $currentWarehouseSearchName',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),

          const SizedBox(height: 14),

          // ======================================================
          // RESULTS
          // ======================================================
          if (warehouseResults.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Item is not available in any warehouses',
                style: TextStyle(color: omanRed, fontWeight: FontWeight.bold),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final double width = constraints.maxWidth;

                final int columns = width >= 1000
                    ? 3
                    : width >= 650
                    ? 2
                    : 1;

                final double cardWidth = columns == 1
                    ? width
                    : (width - ((columns - 1) * 12)) / columns;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: warehouseResults.map((result) {
                    return SizedBox(
                      width: cardWidth,
                      child: buildWarehouseCard(result),
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  // ============================================================
  // WAREHOUSE CARD
  // ============================================================

  Widget buildWarehouseCard(WarehouseResult result) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: omanLightGreen,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: omanGreen.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ======================================================
          // WAREHOUSE HEADER
          // ======================================================

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warehouse_rounded, color: omanGreen),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.warehouseName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      result.storeCode,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: omanGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${result.matchPercent.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ======================================================
          // MATCHED ITEM
          // ======================================================
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Matched Item',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),

                const SizedBox(height: 3),

                Text(
                  result.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ======================================================
          // PRICE + ADD
          // ======================================================
          Row(
            children: [
              const Icon(Icons.payments_outlined, size: 19, color: omanGreen),

              const SizedBox(width: 6),

              Text(
                '${result.price.toStringAsFixed(3)} OMR',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: omanDarkGreen,
                ),
              ),

              const Spacer(),

              ElevatedButton.icon(
                onPressed: () => addDrugToOrder(result),
                icon: const Icon(Icons.add_shopping_cart, size: 17),
                label: const Text('Add'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: omanGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
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
  // DETAIL TILE
  // ============================================================

  Widget buildDetailTile(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: omanLightGreen,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: omanGreen, size: 19),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),

                const SizedBox(height: 3),

                Text(
                  value.isEmpty ? '-' : value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff8faf9),

      // ========================================================
      // APP BAR
      // ========================================================
      appBar: AppBar(
        title: const Text(
          'Drug Details',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),

      // ========================================================
      // BODY
      // ========================================================
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==================================================
              // DRUG HEADER
              // ==================================================

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: omanLightGreen,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.medication_rounded,
                        color: omanGreen,
                        size: 31,
                      ),
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.drug.tradeName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 5),

                          Text(
                            widget.drug.manufacturer,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 15),

              // ==================================================
              // DETAILS
              // ==================================================
              Row(
                children: [
                  Expanded(
                    child: buildDetailTile(
                      'Registration',
                      widget.drug.registration,
                      Icons.badge_outlined,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: buildDetailTile(
                      'Manufacturer',
                      widget.drug.manufacturer,
                      Icons.business_outlined,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // ==================================================
              // QUANTITY
              // ==================================================
              const Text(
                'Quantity',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  hintText: 'Enter quantity',
                  prefixIcon: const Icon(
                    Icons.production_quantity_limits,
                    color: omanGreen,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: omanGreen),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // ==================================================
              // ORIGINAL DRUG SEARCH BUTTON
              // ==================================================
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: searchingWarehouses
                      ? null
                      : () {
                          searchWarehouses(drugName: widget.drug.tradeName);
                        },
                  icon: searchingWarehouses
                      ? const SizedBox(
                          width: 21,
                          height: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.warehouse_rounded),
                  label: Text(
                    searchingWarehouses
                        ? 'Searching Warehouses...'
                        : 'Search in Warehouses',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: omanRed,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),

              // ==================================================
              // ORIGINAL WAREHOUSE RESULTS
              // ==================================================
              if (warehouseSearchDone) buildWarehouseResults(),

              const SizedBox(height: 10),

              // ==================================================
              // ALTERNATIVES HEADER
              // ==================================================
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: omanLightGreen,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.sync_alt_rounded, color: omanGreen),
                  ),

                  const SizedBox(width: 10),

                  const Expanded(
                    child: Text(
                      'Alternatives',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ==================================================
              // ALTERNATIVES LIST
              // ==================================================
              if (loadingAlternatives)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(25),
                    child: CircularProgressIndicator(color: omanGreen),
                  ),
                )
              else if (alternatives.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: const Text(
                    'No alternatives found.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                Column(
                  children: alternatives.map((alternative) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AlternativeWarehouseCard(
                        key: ValueKey(
                          alternative.registration.isNotEmpty
                              ? alternative.registration
                              : alternative.tradeName,
                        ),
                        alternative: alternative,
                        searchFunction: searchWarehouseResults,
                        onAdd: addDrugToOrder,
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ALTERNATIVE WAREHOUSE CARD
//
// كل Alternative لها State مستقل:
// - Loading مستقل
// - Results مستقلة
// - Search Done مستقلة
//
// وبالتالي البحث في بديل واحد لا يؤثر على باقي البدائل.
// ============================================================

class AlternativeWarehouseCard extends StatefulWidget {
  final DrugModel alternative;

  final Future<List<WarehouseResult>> Function(String searchName)
  searchFunction;

  final Future<void> Function(WarehouseResult result) onAdd;

  const AlternativeWarehouseCard({
    super.key,
    required this.alternative,
    required this.searchFunction,
    required this.onAdd,
  });

  @override
  State<AlternativeWarehouseCard> createState() =>
      _AlternativeWarehouseCardState();
}

class _AlternativeWarehouseCardState extends State<AlternativeWarehouseCard> {
  // ============================================================
  // LOCAL STATE
  // ============================================================

  bool isSearching = false;

  bool searchDone = false;

  List<WarehouseResult> results = [];

  // ============================================================
  // SEARCH
  // ============================================================

  Future<void> search() async {
    if (isSearching) return;

    final String searchName = widget.alternative.tradeName.trim();

    if (searchName.isEmpty) {
      return;
    }

    setState(() {
      isSearching = true;
      searchDone = false;
      results = [];
    });

    try {
      final List<WarehouseResult> found = await widget.searchFunction(
        searchName,
      );

      if (!mounted) return;

      setState(() {
        results = found;
        isSearching = false;
        searchDone = true;
      });
    } catch (e) {
      debugPrint('ERROR SEARCHING ALTERNATIVE $searchName: $e');

      if (!mounted) return;

      setState(() {
        results = [];
        isSearching = false;
        searchDone = true;
      });
    }
  }

  // ============================================================
  // WAREHOUSE CARD
  // ============================================================

  Widget buildWarehouseCard(WarehouseResult result) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: omanLightGreen,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: omanGreen.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ======================================================
          // WAREHOUSE HEADER
          // ======================================================

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warehouse_rounded, color: omanGreen),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.warehouseName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      result.storeCode,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: omanGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${result.matchPercent.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ======================================================
          // MATCHED ITEM
          // ======================================================
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Matched Item',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),

                const SizedBox(height: 3),

                Text(
                  result.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ======================================================
          // PRICE + ADD
          // ======================================================
          Row(
            children: [
              const Icon(Icons.payments_outlined, size: 19, color: omanGreen),

              const SizedBox(width: 6),

              Text(
                '${result.price.toStringAsFixed(3)} OMR',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: omanDarkGreen,
                ),
              ),

              const Spacer(),

              ElevatedButton.icon(
                onPressed: () => widget.onAdd(result),
                icon: const Icon(Icons.add_shopping_cart, size: 17),
                label: const Text('Add'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: omanGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
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
  // RESULTS
  //
  // تظهر مباشرة تحت الـ Alternative الذي تم البحث عنه.
  // ============================================================

  Widget buildResults() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ======================================================
          // RESULTS HEADER
          // ======================================================

          Row(
            children: [
              const Icon(Icons.warehouse_rounded, color: omanRed, size: 19),

              const SizedBox(width: 7),

              const Expanded(
                child: Text(
                  'Available in Warehouses',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: omanLightRed,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  '${results.length}',
                  style: const TextStyle(
                    color: omanRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          Text(
            'Search: ${widget.alternative.tradeName}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),

          const SizedBox(height: 10),

          // ======================================================
          // NO RESULTS
          // ======================================================
          if (results.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Item is not available in any warehouse',
                style: TextStyle(
                  color: omanRed,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            )
          // ======================================================
          // RESULTS
          // ======================================================
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final double width = constraints.maxWidth;

                final int columns = width >= 1000
                    ? 3
                    : width >= 650
                    ? 2
                    : 1;

                final double cardWidth = columns == 1
                    ? width
                    : (width - ((columns - 1) * 10)) / columns;

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: results.map((result) {
                    return SizedBox(
                      width: cardWidth,
                      child: buildWarehouseCard(result),
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ======================================================
          // ALTERNATIVE HEADER
          // ======================================================

          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: omanLightGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.medication_rounded, color: omanGreen),
              ),

              const SizedBox(width: 10),

              // ==================================================
              // ALTERNATIVE NAME
              // ==================================================
              Expanded(
                child: Text(
                  widget.alternative.tradeName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // ==================================================
              // CHECK BUTTON
              // ==================================================
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: isSearching ? null : search,
                  icon: isSearching
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.warehouse_rounded, size: 15),
                  label: const Text(
                    'Check',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: omanRed,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ======================================================
          // RESULTS UNDER THIS ALTERNATIVE
          // ======================================================
          if (searchDone) buildResults(),
        ],
      ),
    );
  }
}

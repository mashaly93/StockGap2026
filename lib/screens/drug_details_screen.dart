import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../models/drug_model.dart';
import '../service/drug_service.dart';

class DrugDetailsScreen extends StatefulWidget {
  final DrugModel drug;

  const DrugDetailsScreen({super.key, required this.drug});

  @override
  State<DrugDetailsScreen> createState() => _DrugDetailsScreenState();
}

// ============================================================
// WAREHOUSE RESULT
// ============================================================

class WarehouseResult {
  final String storeCode;
  final String warehouseName;
  final String itemName;
  final double price;
  final double matchPercent;

  WarehouseResult({
    required this.storeCode,
    required this.warehouseName,
    required this.itemName,
    required this.price,
    required this.matchPercent,
  });
}

// ============================================================
// STATE
// ============================================================

class _DrugDetailsScreenState extends State<DrugDetailsScreen> {
  final DrugService service = DrugService();

  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // ============================================================
  // WAREHOUSES
  // ============================================================

  final List<String> warehouseCodes = ['M001', 'M002', 'M003', 'M004'];

  // ============================================================
  // ALTERNATIVES
  // ============================================================

  List<DrugModel> alternatives = [];

  bool loadingAlternatives = true;

  // ============================================================
  // WAREHOUSE SEARCH
  // ============================================================

  List<WarehouseResult> warehouseResults = [];

  bool searchingWarehouses = false;

  bool warehouseSearchDone = false;

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
      final data = await service.getAlternatives(widget.drug);

      if (!mounted) return;

      setState(() {
        alternatives = data;
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
  // NORMALIZE
  // ============================================================

  String normalizeForWarehouse(String text) {
    String value = text.toLowerCase().trim();

    value = value.replaceAll(RegExp(r'[-_/\\.,()\[\]{}]+'), ' ');

    value = value.replaceAll(RegExp(r'\s+'), ' ');

    final Map<String, String> replacements = {
      'tablets': 'tab',
      'tablet': 'tab',
      'tabs': 'tab',

      'capsules': 'cap',
      'capsule': 'cap',
      'caps': 'cap',

      'syr': 'syrup',
      'syp': 'syrup',

      'inj': 'injection',
      'amp': 'ampoule',

      'crm': 'cream',
      'oint': 'ointment',
    };

    replacements.forEach((key, replacement) {
      value = value.replaceAll(RegExp(r'\b' + key + r'\b'), replacement);
    });

    return value.trim();
  }

  // ============================================================
  // WORDS
  // ============================================================

  List<String> warehouseWords(String text) {
    const Set<String> ignored = {
      'mg',
      'mcg',
      'g',
      'gm',
      'kg',
      'ml',
      'l',
      'new',
      'offer',
      'free',
      'pcs',
      'piece',
      'pieces',
      'pack',
      'box',
      'with',
      'the',
    };

    return normalizeForWarehouse(text)
        .split(' ')
        .where((word) => word.isNotEmpty && !ignored.contains(word))
        .toList();
  }

  // ============================================================
  // NUMBERS
  // ============================================================

  Set<String> warehouseNumbers(String text) {
    return RegExp(r'\d+(?:\.\d+)?')
        .allMatches(normalizeForWarehouse(text))
        .map((match) => match.group(0)!)
        .toSet();
  }

  // ============================================================
  // WORD SIMILARITY
  // ============================================================

  double simpleWordSimilarity(String a, String b) {
    if (a == b) {
      return 100;
    }

    if (a.isEmpty || b.isEmpty) {
      return 0;
    }

    final int maxLength = a.length > b.length ? a.length : b.length;

    int differences = 0;

    for (int i = 0; i < maxLength; i++) {
      if (i >= a.length || i >= b.length) {
        differences++;
      } else if (a[i] != b[i]) {
        differences++;
      }
    }

    return 100 - ((differences / maxLength) * 100);
  }

  // ============================================================
  // WAREHOUSE SIMILARITY
  // ============================================================

  double warehouseSimilarity(String drugName, String warehouseName) {
    final List<String> drugWords = warehouseWords(drugName);

    final List<String> storeWords = warehouseWords(warehouseName);

    if (drugWords.isEmpty || storeWords.isEmpty) {
      return 0;
    }

    final double firstWordScore = simpleWordSimilarity(
      drugWords.first,
      storeWords.first,
    );

    if (firstWordScore < 60) {
      return 0;
    }

    int matchedWords = 0;

    double fuzzyTotal = 0;

    final Set<int> usedStoreIndexes = {};

    for (final String drugWord in drugWords) {
      double bestWordScore = 0;

      int bestIndex = -1;

      for (int i = 0; i < storeWords.length; i++) {
        if (usedStoreIndexes.contains(i)) {
          continue;
        }

        final double score = simpleWordSimilarity(drugWord, storeWords[i]);

        if (score > bestWordScore) {
          bestWordScore = score;
          bestIndex = i;
        }
      }

      if (bestWordScore >= 80) {
        matchedWords++;

        fuzzyTotal += bestWordScore;

        if (bestIndex >= 0) {
          usedStoreIndexes.add(bestIndex);
        }
      }
    }

    if (matchedWords == 0) {
      return 0;
    }

    final double wordScore = fuzzyTotal / drugWords.length;

    final Set<String> drugNumbers = warehouseNumbers(drugName);

    final Set<String> storeNumbers = warehouseNumbers(warehouseName);

    double numberScore = 0;

    if (drugNumbers.isNotEmpty) {
      if (storeNumbers.isNotEmpty) {
        final int commonNumbers = drugNumbers.intersection(storeNumbers).length;

        if (commonNumbers == drugNumbers.length) {
          numberScore = 100;
        } else if (commonNumbers > 0) {
          numberScore = (commonNumbers / drugNumbers.length) * 100;
        }
      }
    } else {
      numberScore = 100;
    }

    double finalScore = (wordScore * 0.75) + (numberScore * 0.25);

    if (finalScore > 100) {
      finalScore = 100;
    }

    if (finalScore < 0) {
      finalScore = 0;
    }

    return finalScore;
  }

  // ============================================================
  // GET WAREHOUSE NAME
  // ============================================================

  String getWarehouseName(Map<String, dynamic>? data, String storeCode) {
    if (data != null) {
      final dynamic name = data['name'];

      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString().trim();
      }

      final dynamic username = data['username'];

      if (username != null && username.toString().trim().isNotEmpty) {
        return username.toString().trim();
      }

      final dynamic storeName = data['storeName'];

      if (storeName != null && storeName.toString().trim().isNotEmpty) {
        return storeName.toString().trim();
      }
    }

    // Fallback
    return storeCode;
  }

  // ============================================================
  // SEARCH ALL WAREHOUSES
  // ============================================================

  Future<void> searchWarehouses() async {
    if (searchingWarehouses) {
      return;
    }

    setState(() {
      searchingWarehouses = true;
      warehouseSearchDone = false;
      warehouseResults = [];
    });

    final String drugName = widget.drug.tradeName.trim();

    debugPrint('');
    debugPrint('================================================');
    debugPrint('SEARCHING ALL WAREHOUSES');
    debugPrint('DRUG = $drugName');
    debugPrint('MINIMUM MATCH = 60%');
    debugPrint('================================================');

    final List<WarehouseResult> found = [];

    // ========================================================
    // SEARCH EACH WAREHOUSE
    // ========================================================

    for (final String storeCode in warehouseCodes) {
      try {
        debugPrint('');
        debugPrint('-----------------------------------------------');
        debugPrint('STORE CODE = $storeCode');

        // ====================================================
        // GET WAREHOUSE DOCUMENT
        // ====================================================

        final DocumentSnapshot<Map<String, dynamic>> storeSnapshot =
            await firestore.collection('stores').doc(storeCode).get();

        final Map<String, dynamic>? storeData = storeSnapshot.data();

        final String warehouseName = getWarehouseName(storeData, storeCode);

        debugPrint('WAREHOUSE NAME = $warehouseName');

        // ====================================================
        // GET INVENTORY
        // ====================================================

        final QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
            .collection('stores')
            .doc(storeCode)
            .collection('inventory')
            .get();

        debugPrint('ITEMS = ${snapshot.docs.length}');

        WarehouseResult? bestResult;

        double bestScore = 0;

        // ====================================================
        // SEARCH ITEMS
        // ====================================================

        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in snapshot.docs) {
          final Map<String, dynamic> data = doc.data();

          final String itemName = getItemName(data);

          if (itemName.isEmpty) {
            continue;
          }

          final double score = warehouseSimilarity(drugName, itemName);

          debugPrint(
            '$storeCode | '
            '$itemName | '
            '${score.toStringAsFixed(1)}%',
          );

          if (score >= 60 && score > bestScore) {
            bestScore = score;

            bestResult = WarehouseResult(
              storeCode: storeCode,
              warehouseName: warehouseName,
              itemName: itemName,
              price: getPrice(data),
              matchPercent: score,
            );
          }
        }

        // ====================================================
        // ADD BEST RESULT
        // ====================================================

        if (bestResult != null) {
          found.add(bestResult);

          debugPrint('BEST MATCH $warehouseName:');

          debugPrint(bestResult.itemName);

          debugPrint('${bestResult.matchPercent}%');
        } else {
          debugPrint('NO MATCH >= 60% IN $warehouseName');
        }
      } catch (e) {
        debugPrint('ERROR STORE $storeCode: $e');
      }
    }

    // ========================================================
    // SORT
    // ========================================================

    found.sort((a, b) => b.matchPercent.compareTo(a.matchPercent));

    if (!mounted) {
      return;
    }

    setState(() {
      warehouseResults = found;
      searchingWarehouses = false;
      warehouseSearchDone = true;
    });

    debugPrint('');
    debugPrint('================================================');
    debugPrint('SEARCH FINISHED');
    debugPrint('RESULTS = ${found.length}');
    debugPrint('================================================');

    if (found.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الصنف غير موجود في المخازن بنسبة تطابق 60% أو أكثر'),
        ),
      );
    }
  }

  // ============================================================
  // GET ITEM NAME
  // ============================================================

  String getItemName(Map<String, dynamic> data) {
    const List<String> fields = [
      'itemName',
      'name',
      'item',
      'productName',
      'tradeName',
    ];

    for (final String field in fields) {
      final dynamic value = data[field];

      if (value == null) {
        continue;
      }

      final String text = value.toString().trim();

      if (text.isNotEmpty) {
        return text;
      }
    }

    return '';
  }

  // ============================================================
  // GET PRICE
  // ============================================================

  double getPrice(Map<String, dynamic> data) {
    const List<String> fields = [
      'price',
      'whPrice',
      'warehousePrice',
      'purchasePrice',
      'salePrice',
    ];

    for (final String field in fields) {
      final dynamic value = data[field];

      if (value == null) {
        continue;
      }

      if (value is num) {
        return value.toDouble();
      }

      String text = value.toString();

      text = text
          .replaceAll(',', '')
          .replaceAll('OMR', '')
          .replaceAll('ر.ع.', '')
          .trim();

      final double? parsed = double.tryParse(text);

      if (parsed != null) {
        return parsed;
      }
    }

    return 0;
  }

  // ============================================================
  // QUANTITY
  // ============================================================

  int getQuantity() {
    final String text = quantityController.text.trim();

    final int? quantity = int.tryParse(text);

    if (quantity == null || quantity <= 0) {
      return 0;
    }

    return quantity;
  }

  // ============================================================
  // ADD DRUG TO ORDER
  // ============================================================

  Future<void> addDrugToOrder(WarehouseResult result) async {
    final int quantity = getQuantity();

    if (quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid quantity.')),
      );

      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      final List<String> savedItems =
          prefs.getStringList('drug_details_order_items') ?? [];

      final Map<String, dynamic> newItem = {
        // Drug
        'item': widget.drug.tradeName,

        // Quantity
        'qty': quantity,

        // IMPORTANT:
        // Keep store code internally
        'warehouse': result.storeCode,

        // Warehouse display name
        'warehouseName': result.warehouseName,

        // Matched item
        'matchedItem': result.itemName,

        // Match
        'matchPercent': result.matchPercent,

        // Prices
        'purchase': result.price,
        'sale': result.price,

        // Drug information
        'registration': widget.drug.registration,
        'manufacturer': widget.drug.manufacturer,

        // Date
        'addedAt': DateTime.now().toIso8601String(),
      };

      // ========================================================
      // CHECK DUPLICATE
      // ========================================================

      bool foundExisting = false;

      for (int i = 0; i < savedItems.length; i++) {
        try {
          final Map<String, dynamic> oldItem = jsonDecode(savedItems[i]);

          if (oldItem['item']?.toString() == newItem['item']?.toString() &&
              oldItem['warehouse']?.toString() ==
                  newItem['warehouse']?.toString() &&
              oldItem['matchedItem']?.toString() ==
                  newItem['matchedItem']?.toString()) {
            final int oldQty =
                int.tryParse(oldItem['qty']?.toString() ?? '') ?? 0;

            oldItem['qty'] = oldQty + quantity;

            // Update warehouse name
            oldItem['warehouseName'] = result.warehouseName;

            savedItems[i] = jsonEncode(oldItem);

            foundExisting = true;

            break;
          }
        } catch (_) {}
      }

      if (!foundExisting) {
        savedItems.add(jsonEncode(newItem));
      }

      await prefs.setStringList('drug_details_order_items', savedItems);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.drug.tradeName} added to Drug Details Order ✔',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error adding item: $e')));
    }
  }

  // ============================================================
  // COPY
  // ============================================================

  void copyDrugName() {
    Clipboard.setData(ClipboardData(text: widget.drug.tradeName));

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final DrugModel drug = widget.drug;

    return Scaffold(
      appBar: AppBar(title: const Text('Drug Details'), centerTitle: true),

      body: ListView(
        padding: const EdgeInsets.all(16),

        children: [
          // ==================================================
          // DRUG NAME
          // ==================================================
          Row(
            children: [
              Expanded(
                child: Text(
                  drug.tradeName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              IconButton(icon: const Icon(Icons.copy), onPressed: copyDrugName),
            ],
          ),

          const SizedBox(height: 20),

          // ==================================================
          // DETAILS
          // ==================================================
          buildTile('Registration', drug.registration, Icons.badge),

          buildTile('Pack Size', drug.packSize, Icons.inventory_2),

          buildTile('Active Ingredient 1', drug.active1, Icons.science),

          if (drug.active2.isNotEmpty)
            buildTile(
              'Active Ingredient 2',
              drug.active2,
              Icons.science_outlined,
            ),

          buildTile('Manufacturer', drug.manufacturer, Icons.factory),

          buildTile('Agent', drug.agent, Icons.local_shipping),

          buildTile(
            'Price',
            '${drug.price.toStringAsFixed(3)} OMR',
            Icons.attach_money,
          ),

          const SizedBox(height: 20),

          // ==================================================
          // QUANTITY
          // ==================================================
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.production_quantity_limits,
                        color: Color(0xff0050c0),
                      ),

                      SizedBox(width: 8),

                      Text(
                        'Quantity',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  TextField(
                    controller: quantityController,

                    keyboardType: TextInputType.number,

                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],

                    decoration: InputDecoration(
                      hintText: 'Enter quantity',

                      labelText: 'Quantity',

                      prefixIcon: const Icon(Icons.numbers),

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ==================================================
          // SEARCH BUTTON
          // ==================================================
          SizedBox(
            width: double.infinity,

            child: ElevatedButton.icon(
              onPressed: searchingWarehouses ? null : searchWarehouses,

              icon: searchingWarehouses
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.warehouse),

              label: Text(
                searchingWarehouses ? 'Searching...' : 'Search in Warehouses',
              ),

              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff0050c0),

                foregroundColor: Colors.white,

                padding: const EdgeInsets.symmetric(vertical: 14),

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ==================================================
          // RESULTS
          // ==================================================
          if (warehouseSearchDone) buildWarehouseResults(),

          const SizedBox(height: 24),

          // ==================================================
          // ALTERNATIVES
          // ==================================================
          const Text(
            '🔄 Alternatives',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          if (loadingAlternatives)
            const Center(child: CircularProgressIndicator())
          else if (alternatives.isEmpty)
            const Text('No alternatives found')
          else
            ...alternatives.map((alt) {
              final bool cheapest = alternatives.first.price == alt.price;

              return Card(
                child: ListTile(
                  leading: Icon(cheapest ? Icons.star : Icons.medication),

                  title: Text(
                    alt.tradeName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),

                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(alt.manufacturer),
                      Text('${alt.price.toStringAsFixed(3)} OMR'),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // ==========================================================
  // WAREHOUSE RESULTS
  // ==========================================================

  Widget buildWarehouseResults() {
    return Card(
      elevation: 3,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

      child: Padding(
        padding: const EdgeInsets.all(14),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            // ==================================================
            // HEADER
            // ==================================================
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,

                  decoration: BoxDecoration(
                    color: const Color(0xff0050c0).withOpacity(0.10),

                    borderRadius: BorderRadius.circular(10),
                  ),

                  child: const Icon(Icons.warehouse, color: Color(0xff0050c0)),
                ),

                const SizedBox(width: 10),

                const Expanded(
                  child: Text(
                    'Available in Warehouses',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),

                if (warehouseResults.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),

                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),

                    child: Text(
                      '${warehouseResults.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 14),

            // ==================================================
            // NO RESULTS
            // ==================================================
            if (warehouseResults.isEmpty)
              Container(
                width: double.infinity,

                padding: const EdgeInsets.all(14),

                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),

                  borderRadius: BorderRadius.circular(10),
                ),

                child: const Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: Colors.red),

                    SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        'الصنف غير موجود في أي مخزن',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final double width = constraints.maxWidth;

                  int columns;

                  if (width >= 1100) {
                    columns = 4;
                  } else if (width >= 800) {
                    columns = 3;
                  } else if (width >= 520) {
                    columns = 2;
                  } else {
                    columns = 1;
                  }

                  const double spacing = 10;

                  final double cardWidth =
                      (width - ((columns - 1) * spacing)) / columns;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,

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
      ),
    );
  }

  // ==========================================================
  // WAREHOUSE CARD
  // ==========================================================

  Widget buildWarehouseCard(WarehouseResult result) {
    final int quantity = getQuantity();

    return Container(
      padding: const EdgeInsets.all(12),

      decoration: BoxDecoration(
        color: Colors.white,

        border: Border.all(color: Colors.grey.shade300),

        borderRadius: BorderRadius.circular(12),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),

            blurRadius: 5,

            offset: const Offset(0, 2),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // ==================================================
          // TOP
          // ==================================================
          Row(
            children: [
              Container(
                width: 42,
                height: 42,

                decoration: BoxDecoration(
                  color: const Color(0xff0050c0).withOpacity(0.10),

                  borderRadius: BorderRadius.circular(10),
                ),

                child: const Icon(
                  Icons.warehouse,
                  color: Color(0xff0050c0),
                  size: 21,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  result.warehouseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // ==================================================
              // MATCH %
              // ==================================================
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),

                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.10),

                  borderRadius: BorderRadius.circular(7),
                ),

                child: Text(
                  '${result.matchPercent.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ==================================================
          // ITEM
          // ==================================================
          Text(
            result.itemName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.3,
            ),
          ),

          const SizedBox(height: 8),

          // ==================================================
          // PRICE
          // ==================================================
          Row(
            children: [
              const Icon(
                Icons.payments_outlined,
                size: 17,
                color: Colors.green,
              ),

              const SizedBox(width: 5),

              Text(
                '${result.price.toStringAsFixed(3)} OMR',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ==================================================
          // ADD BUTTON
          // ==================================================
          SizedBox(
            width: double.infinity,

            height: 40,

            child: ElevatedButton.icon(
              onPressed: quantity > 0
                  ? () {
                      addDrugToOrder(result);
                    }
                  : null,

              icon: const Icon(Icons.add_shopping_cart, size: 17),

              label: Text(quantity > 0 ? 'Add $quantity' : 'Enter Quantity'),

              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,

                foregroundColor: Colors.white,

                disabledBackgroundColor: Colors.grey.shade400,

                disabledForegroundColor: Colors.white,

                elevation: 0,

                padding: const EdgeInsets.symmetric(horizontal: 8),

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // DETAIL TILE
  // ==========================================================

  Widget buildTile(String title, String value, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),

      child: ListTile(
        leading: Icon(icon),

        title: Text(title),

        subtitle: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

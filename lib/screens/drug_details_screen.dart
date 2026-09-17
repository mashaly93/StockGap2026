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

const Color pageBackground = Color(0xfff7faf8);

// ============================================================
// WAREHOUSE RESULT
// ============================================================

class WarehouseResult {
  final String storeCode;
  final String warehouseName;
  final String itemName;
  final double price;
  final double matchPercent;
  final String searchedDrugName;

  // NEW
  final String itemId;
  final String offerText;
  final int? stock;

  WarehouseResult({
    required this.storeCode,
    required this.warehouseName,
    required this.itemName,
    required this.price,
    required this.matchPercent,
    required this.searchedDrugName,
    this.itemId = '',
    this.offerText = '',
    this.stock,
  });

  bool get hasOffer => offerText.trim().isNotEmpty;

  bool get hasStock => stock != null;

  bool get isOutOfStock => stock != null && stock! <= 0;
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

// ============================================================
// STATE
// ============================================================

class _DrugDetailsScreenState extends State<DrugDetailsScreen> {
  // ============================================================
  // SERVICES
  // ============================================================

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
  // ORIGINAL SEARCH
  // ============================================================

  List<WarehouseResult> warehouseResults = [];

  bool searchingWarehouses = false;

  bool warehouseSearchDone = false;

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
  // NORMALIZE TEXT
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
        .replaceAll(']', ' ')
        .replaceAll('{', ' ')
        .replaceAll('}', ' ');

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

      'susp': 'suspension',
      'suspension': 'suspension',

      'drops': 'drop',
      'drop': 'drop',

      'sol': 'solution',
      'solution': 'solution',

      'oral': 'oral',
    };

    final words = text.split(' ');

    final normalizedWords = words.map((word) {
      return replacements[word] ?? word;
    }).toList();

    return normalizedWords.join(' ').trim();
  }

  // ============================================================
  // IGNORED WORDS
  // ============================================================

  Set<String> get warehouseIgnoredWords {
    return <String>{
      'tab',
      'cap',
      'syrup',
      'injection',
      'ampoule',
      'cream',
      'ointment',
      'suspension',
      'drop',
      'solution',
      'oral',
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
      'pcs',
      'pk',
      'pack',
      'box',
      'bt',
      'btl',
      'bottle',
      's',
      'the',
      'and',
      'for',
      'of',
    };
  }

  // ============================================================
  // WAREHOUSE WORDS
  // ============================================================

  List<String> warehouseWords(String value) {
    final normalized = normalizeForWarehouse(value);

    return normalized
        .split(' ')
        .where(
          (word) =>
              word.isNotEmpty &&
              !warehouseIgnoredWords.contains(word) &&
              !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(word),
        )
        .toList();
  }

  // ============================================================
  // NUMBERS
  // ============================================================

  List<String> warehouseNumbers(String value) {
    return RegExp(r'\d+(?:\.\d+)?')
        .allMatches(normalizeForWarehouse(value))
        .map((match) => match.group(0)!)
        .toList();
  }

  // ============================================================
  // TOKEN SET
  // ============================================================

  Set<String> warehouseTokenSet(String value) {
    return warehouseWords(value).toSet();
  }

  // ============================================================
  // SIMPLE WORD SIMILARITY
  // ============================================================

  double simpleWordSimilarity(String a, String b) {
    a = a.trim().toLowerCase();
    b = b.trim().toLowerCase();

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
  // PREFIX / CONTAINS SIMILARITY
  // ============================================================

  double prefixSimilarity(String a, String b) {
    a = a.toLowerCase().trim();
    b = b.toLowerCase().trim();

    if (a.isEmpty || b.isEmpty) {
      return 0;
    }

    if (a == b) {
      return 100;
    }

    if (a.startsWith(b) || b.startsWith(a)) {
      final int shorter = a.length < b.length ? a.length : b.length;

      final int longer = a.length > b.length ? a.length : b.length;

      return ((shorter / longer) * 100).clamp(0, 100);
    }

    if (a.contains(b) || b.contains(a)) {
      final int shorter = a.length < b.length ? a.length : b.length;

      final int longer = a.length > b.length ? a.length : b.length;

      return ((shorter / longer) * 90).clamp(0, 100);
    }

    return 0;
  }

  // ============================================================
  // BEST WORD MATCH
  // ============================================================

  double bestWordMatch(String originalWord, List<String> warehouseWordsList) {
    double best = 0;

    for (final warehouseWord in warehouseWordsList) {
      final direct = simpleWordSimilarity(originalWord, warehouseWord);

      final prefix = prefixSimilarity(originalWord, warehouseWord);

      final score = direct > prefix ? direct : prefix;

      if (score > best) {
        best = score;
      }
    }

    return best;
  }

  // ============================================================
  // IMPROVED WAREHOUSE SIMILARITY
  // ============================================================

  double warehouseSimilarity(String original, String warehouseItem) {
    final originalNormalized = normalizeForWarehouse(original);

    final warehouseNormalized = normalizeForWarehouse(warehouseItem);

    if (originalNormalized == warehouseNormalized) {
      return 100;
    }

    final originalWords = warehouseWords(original);

    final warehouseItemWords = warehouseWords(warehouseItem);

    if (originalWords.isEmpty || warehouseItemWords.isEmpty) {
      return 0;
    }

    // ==========================================================
    // FIRST IMPORTANT WORD
    // ==========================================================

    final double firstWordScore = bestWordMatch(
      originalWords.first,
      warehouseItemWords,
    );

    if (firstWordScore < 55) {
      return 0;
    }

    // ==========================================================
    // WORD MATCHING
    // ==========================================================

    int matchedWords = 0;

    double totalWordScore = 0;

    for (final originalWord in originalWords) {
      final double bestScore = bestWordMatch(originalWord, warehouseItemWords);

      if (bestScore >= 75) {
        matchedWords++;
        totalWordScore += bestScore;
      } else if (bestScore >= 55) {
        totalWordScore += bestScore * .5;
      }
    }

    final double averageWordScore = totalWordScore / originalWords.length;

    final double wordMatchRatio = matchedWords / originalWords.length;

    final double wordScore =
        (averageWordScore * .70) + (wordMatchRatio * 100 * .30);

    // ==========================================================
    // TOKEN OVERLAP
    // ==========================================================

    final Set<String> originalTokens = warehouseTokenSet(original);

    final Set<String> warehouseTokens = warehouseTokenSet(warehouseItem);

    final Set<String> commonTokens = originalTokens.intersection(
      warehouseTokens,
    );

    double tokenScore = 0;

    if (originalTokens.isNotEmpty) {
      tokenScore = (commonTokens.length / originalTokens.length) * 100;
    }

    // ==========================================================
    // NUMBERS / STRENGTH
    // ==========================================================

    final originalNumbers = warehouseNumbers(original);

    final warehouseNumberList = warehouseNumbers(warehouseItem);

    double numberScore = 100;

    if (originalNumbers.isNotEmpty) {
      int matchedNumbers = 0;

      for (final number in originalNumbers) {
        if (warehouseNumberList.contains(number)) {
          matchedNumbers++;
        }
      }

      numberScore = (matchedNumbers / originalNumbers.length) * 100;
    }

    // ==========================================================
    // ORDER BONUS
    // ==========================================================

    double orderBonus = 0;

    final int compareLength = originalWords.length < warehouseItemWords.length
        ? originalWords.length
        : warehouseItemWords.length;

    if (compareLength > 0) {
      int samePosition = 0;

      for (int i = 0; i < compareLength; i++) {
        final score = simpleWordSimilarity(
          originalWords[i],
          warehouseItemWords[i],
        );

        if (score >= 80) {
          samePosition++;
        }
      }

      orderBonus = (samePosition / compareLength) * 10;
    }

    // ==========================================================
    // FINAL SCORE
    // ==========================================================

    double finalScore =
        (wordScore * .55) +
        (tokenScore * .20) +
        (numberScore * .20) +
        orderBonus;

    // ==========================================================
    // PENALTY FOR MISSING STRENGTH
    // ==========================================================

    if (originalNumbers.isNotEmpty && numberScore == 0) {
      finalScore *= .65;
    }

    // ==========================================================
    // FULL CONTAINS BONUS
    // ==========================================================

    if (warehouseNormalized.contains(originalNormalized) ||
        originalNormalized.contains(warehouseNormalized)) {
      finalScore += 5;
    }

    return finalScore.clamp(0, 100);
  }

  // ============================================================
  // MATCH LABEL
  // ============================================================

  String getMatchLabel(double percent) {
    if (percent >= 95) {
      return 'Excellent Match';
    }

    if (percent >= 85) {
      return 'Very Good Match';
    }

    if (percent >= 75) {
      return 'Good Match';
    }

    if (percent >= 65) {
      return 'Possible Match';
    }

    return 'Weak Match';
  }

  // ============================================================
  // MATCH COLOR
  // ============================================================

  Color getMatchColor(double percent) {
    if (percent >= 85) {
      return omanGreen;
    }

    if (percent >= 75) {
      return const Color(0xff5f8f00);
    }

    if (percent >= 65) {
      return Colors.orange.shade700;
    }

    return omanRed;
  }

  // ============================================================
  // SEARCH WAREHOUSES
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

    if (found.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$searchName is not available in any warehouse'),
          backgroundColor: omanRed,
        ),
      );
    }
  }

  // ============================================================
  // SEARCH RESULTS
  // ============================================================

  Future<List<WarehouseResult>> searchWarehouseResults(
    String searchName,
  ) async {
    final List<WarehouseResult> found = [];

    for (final String storeCode in warehouseCodes) {
      try {
        final DocumentSnapshot<Map<String, dynamic>> storeSnapshot =
            await firestore.collection('stores').doc(storeCode).get();

        final Map<String, dynamic>? storeData = storeSnapshot.data();

        final String warehouseName = getWarehouseName(storeData, storeCode);

        final QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
            .collection('stores')
            .doc(storeCode)
            .collection('inventory')
            .get();

        WarehouseResult? bestResult;

        double bestScore = 0;

        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in snapshot.docs) {
          final Map<String, dynamic> data = doc.data();

          final String itemName = getItemName(data);

          if (itemName.isEmpty) {
            continue;
          }

          final double score = warehouseSimilarity(searchName, itemName);

          // ====================================================
          // MINIMUM MATCH
          // ====================================================

          if (score >= 65 && score > bestScore) {
            bestScore = score;

            bestResult = WarehouseResult(
              storeCode: storeCode,
              warehouseName: warehouseName,
              itemName: itemName,
              price: getPrice(data),
              matchPercent: score,
              searchedDrugName: searchName,

              itemId: doc.id,

              offerText: getOfferText(data),

              stock: getStock(data),
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

    final possibleNames = [
      data['name'],
      data['username'],
      data['storeName'],
      data['warehouseName'],
    ];

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
  // GET STOCK
  // ============================================================

  int? getStock(Map<String, dynamic> data) {
    final possibleStock = [
      data['stock'],
      data['quantity'],
      data['qty'],
      data['availableQuantity'],
      data['availableStock'],
      data['stockQuantity'],
      data['currentStock'],
      data['balance'],
    ];

    for (final value in possibleStock) {
      if (value is int) {
        return value;
      }

      if (value is num) {
        return value.toInt();
      }

      if (value != null) {
        final String text = value.toString().trim();

        final int? parsed = int.tryParse(text);

        if (parsed != null) {
          return parsed;
        }

        final double? decimal = double.tryParse(text);

        if (decimal != null) {
          return decimal.toInt();
        }
      }
    }

    return null;
  }

  // ============================================================
  // GET OFFER
  // ============================================================

  String getOfferText(Map<String, dynamic> data) {
    final possibleOffers = [
      data['offer'],
      data['offers'],
      data['offerText'],
      data['promotion'],
      data['promotions'],
      data['discountOffer'],
      data['specialOffer'],
      data['promo'],
    ];

    for (final value in possibleOffers) {
      if (value == null) {
        continue;
      }

      if (value is String) {
        final text = value.trim();

        if (text.isNotEmpty) {
          return text;
        }
      }

      if (value is num) {
        return '${value.toString()}% OFF';
      }

      if (value is Map) {
        final map = Map<String, dynamic>.from(value);

        final parts = <String>[];

        for (final key in [
          'title',
          'name',
          'text',
          'description',
          'discount',
          'value',
        ]) {
          final item = map[key]?.toString().trim() ?? '';

          if (item.isNotEmpty) {
            parts.add(item);
          }
        }

        if (parts.isNotEmpty) {
          return parts.join(' • ');
        }
      }

      if (value is List) {
        final parts = value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();

        if (parts.isNotEmpty) {
          return parts.join(' • ');
        }
      }
    }

    return '';
  }

  // ============================================================
  // GET CURRENT ORDER ITEMS
  // ============================================================

  Future<List<Map<String, dynamic>>> getCurrentOrderItems() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    const String key = 'drug_details_order_items';

    final List<Map<String, dynamic>> items = [];

    // ==========================================================
    // STRING LIST
    // ==========================================================

    try {
      final List<String>? savedList = prefs.getStringList(key);

      if (savedList != null) {
        for (final String savedItem in savedList) {
          try {
            final dynamic decoded = jsonDecode(savedItem);

            if (decoded is Map) {
              items.add(Map<String, dynamic>.from(decoded));
            }
          } catch (e) {
            debugPrint('ERROR DECODING ORDER ITEM: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('STRINGLIST READ ERROR: $e');
    }

    // ==========================================================
    // OLD STRING FORMAT
    // ==========================================================

    if (items.isEmpty) {
      try {
        final String? oldSaved = prefs.getString(key);

        if (oldSaved != null && oldSaved.trim().isNotEmpty) {
          final dynamic decoded = jsonDecode(oldSaved);

          if (decoded is List) {
            for (final dynamic item in decoded) {
              if (item is Map) {
                items.add(Map<String, dynamic>.from(item));
              }
            }
          }
        }
      } catch (e) {
        debugPrint('OLD ORDER FORMAT ERROR: $e');
      }
    }

    return items;
  }

  // ============================================================
  // EXISTING QUANTITY
  // ============================================================

  Future<int> getExistingQuantity(WarehouseResult result) async {
    final items = await getCurrentOrderItems();

    final String itemName = result.searchedDrugName.trim();

    final String matchedItem = result.itemName.trim();

    int quantity = 0;

    for (final item in items) {
      final String oldItem = item['item']?.toString().trim() ?? '';

      final String oldWarehouse = item['warehouse']?.toString().trim() ?? '';

      final String oldMatched = item['matchedItem']?.toString().trim() ?? '';

      if (oldItem == itemName &&
          oldWarehouse == result.storeCode &&
          oldMatched == matchedItem) {
        quantity += int.tryParse(item['qty']?.toString() ?? '') ?? 0;
      }
    }

    return quantity;
  }

  // ============================================================
  // ADD DRUG TO ORDER
  // ============================================================

  Future<void> addDrugToOrder(
    WarehouseResult result, {
    required int quantity,
  }) async {
    if (quantity <= 0) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid quantity.'),
          backgroundColor: omanRed,
        ),
      );

      return;
    }

    // ==========================================================
    // STOCK VALIDATION
    // ==========================================================

    if (result.stock != null && result.stock! <= 0) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This item is currently out of stock.'),
          backgroundColor: omanRed,
        ),
      );

      return;
    }

    final int existing = await getExistingQuantity(result);

    final int newTotal = existing + quantity;

    if (result.stock != null && newTotal > result.stock!) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Available stock: ${result.stock}. '
            'Already in order: $existing.',
          ),
          backgroundColor: omanRed,
        ),
      );

      return;
    }

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      const String key = 'drug_details_order_items';

      final List<Map<String, dynamic>> items = await getCurrentOrderItems();

      final String itemName = result.searchedDrugName.trim();

      final String matchedItem = result.itemName.trim();

      bool merged = false;

      // ==========================================================
      // MERGE
      // ==========================================================

      for (final Map<String, dynamic> item in items) {
        final String oldItem = item['item']?.toString().trim() ?? '';

        final String oldWarehouse = item['warehouse']?.toString().trim() ?? '';

        final String oldMatched = item['matchedItem']?.toString().trim() ?? '';

        if (oldItem == itemName &&
            oldWarehouse == result.storeCode &&
            oldMatched == matchedItem) {
          final int oldQuantity =
              int.tryParse(item['qty']?.toString() ?? '') ?? 0;

          item['qty'] = oldQuantity + quantity;

          // Update useful information
          item['purchase'] = result.price;

          item['sale'] = result.price;

          item['offer'] = result.offerText;

          item['stock'] = result.stock;

          item['itemId'] = result.itemId;

          item['matchPercent'] = result.matchPercent;

          merged = true;

          break;
        }
      }

      // ==========================================================
      // NEW ITEM
      // ==========================================================

      if (!merged) {
        items.add({
          'item': itemName,
          'qty': quantity,

          'warehouse': result.storeCode,
          'warehouseName': result.warehouseName,

          'matchedItem': matchedItem,
          'matchPercent': result.matchPercent,

          'purchase': result.price,
          'sale': result.price,

          'offer': result.offerText,

          'stock': result.stock,

          'itemId': result.itemId,

          'registration': widget.drug.registration,

          'manufacturer': widget.drug.manufacturer,

          'addedAt': DateTime.now().toIso8601String(),
        });
      }

      // ==========================================================
      // ENCODE
      // ==========================================================

      final List<String> encodedItems = items
          .map((item) => jsonEncode(item))
          .toList();

      await prefs.remove(key);

      final bool savedSuccessfully = await prefs.setStringList(
        key,
        encodedItems,
      );

      if (!savedSuccessfully) {
        throw Exception('SharedPreferences could not save order items.');
      }

      // ==========================================================
      // VERIFY
      // ==========================================================

      final List<String> verify = prefs.getStringList(key) ?? <String>[];

      debugPrint('=================================');

      debugPrint(
        'DRUG DETAILS ORDER SAVED = '
        '${verify.length}',
      );

      debugPrint('ADDED ITEM = $itemName');

      debugPrint('MATCHED ITEM = $matchedItem');

      debugPrint('WAREHOUSE = ${result.storeCode}');

      debugPrint(
        'WAREHOUSE NAME = '
        '${result.warehouseName}',
      );

      debugPrint('QUANTITY ADDED = $quantity');

      debugPrint('EXISTING QUANTITY = $existing');

      debugPrint('NEW TOTAL QUANTITY = $newTotal');

      debugPrint('PRICE = ${result.price}');

      debugPrint('OFFER = ${result.offerText}');

      debugPrint('STOCK = ${result.stock}');

      debugPrint('=================================');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$itemName added • '
            '$quantity pcs • '
            '${result.warehouseName}',
          ),
          backgroundColor: omanGreen,
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('ERROR ADDING DRUG TO ORDER: $e');

      debugPrint(stackTrace.toString());

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not add item to order: $e'),
          backgroundColor: omanRed,
        ),
      );
    }
  }

  // ============================================================
  // SHOW ORDER SHEET
  // ============================================================

  Future<void> showWarehouseOrderSheet(WarehouseResult result) async {
    if (result.stock != null && result.stock! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This item is out of stock.'),
          backgroundColor: omanRed,
        ),
      );

      return;
    }

    final int existing = await getExistingQuantity(result);

    if (!mounted) return;

    int quantity = 1;

    // ==========================================================
    // MAX NEW QUANTITY
    // ==========================================================

    int? maxAdditional;

    if (result.stock != null) {
      maxAdditional = result.stock! - existing;

      if (maxAdditional <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Stock limit reached. '
              'Already in order: $existing.',
            ),
            backgroundColor: omanRed,
          ),
        );

        return;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final double totalPrice = result.price * quantity;

            final int totalAfterAdding = existing + quantity;

            final bool stockLimitReached =
                maxAdditional != null && quantity >= maxAdditional!;

            return Container(
              constraints: const BoxConstraints(maxHeight: 720),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: const BoxDecoration(
                color: pageBackground,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ========================================
                      // HANDLE
                      // ========================================

                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ========================================
                      // HEADER
                      // ========================================
                      Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: omanLightGreen,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.medication_rounded,
                              color: omanGreen,
                              size: 26,
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  result.searchedDrugName.trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(height: 3),

                                Text(
                                  'Add to order',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          IconButton(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // ========================================
                      // MATCH STATUS
                      // ========================================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: getMatchColor(
                                  result.matchPercent,
                                ).withOpacity(.10),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.verified_rounded,
                                color: getMatchColor(result.matchPercent),
                              ),
                            ),

                            const SizedBox(width: 10),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    getMatchLabel(result.matchPercent),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: getMatchColor(result.matchPercent),
                                    ),
                                  ),

                                  const SizedBox(height: 2),

                                  Text(
                                    'Matched item: '
                                    '${result.itemName}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            Text(
                              '${result.matchPercent.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: getMatchColor(result.matchPercent),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

                      // ========================================
                      // WAREHOUSE
                      // ========================================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: omanLightGreen,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.warehouse_rounded,
                                color: omanGreen,
                              ),
                            ),

                            const SizedBox(width: 10),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'WAREHOUSE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade500,
                                      letterSpacing: .5,
                                    ),
                                  ),

                                  const SizedBox(height: 3),

                                  Text(
                                    result.warehouseName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),

                                  const SizedBox(height: 2),

                                  Text(
                                    result.storeCode,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

                      // ========================================
                      // OFFER
                      // ========================================
                      if (result.hasOffer)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: const Color(0xfffff7e8),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.orange.withOpacity(.25),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.local_offer_rounded,
                                  color: Colors.orange,
                                ),
                              ),

                              const SizedBox(width: 10),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'SPECIAL OFFER',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                        letterSpacing: .5,
                                      ),
                                    ),

                                    const SizedBox(height: 3),

                                    Text(
                                      result.offerText,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (result.hasOffer) const SizedBox(height: 10),

                      // ========================================
                      // PRICE
                      // ========================================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: omanLightGreen,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.payments_outlined,
                                color: omanGreen,
                                size: 21,
                              ),
                            ),

                            const SizedBox(width: 10),

                            const Expanded(
                              child: Text(
                                'UNIT PRICE',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                  letterSpacing: .4,
                                ),
                              ),
                            ),

                            Text(
                              '${result.price.toStringAsFixed(3)} OMR',
                              style: const TextStyle(
                                color: omanDarkGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

                      // ========================================
                      // STOCK
                      // ========================================
                      if (result.hasStock)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: result.isOutOfStock
                                ? omanLightRed
                                : omanLightGreen,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: result.isOutOfStock
                                  ? omanRed.withOpacity(.20)
                                  : omanGreen.withOpacity(.20),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                result.isOutOfStock
                                    ? Icons.error_outline_rounded
                                    : Icons.inventory_2_outlined,
                                color: result.isOutOfStock
                                    ? omanRed
                                    : omanGreen,
                              ),

                              const SizedBox(width: 9),

                              Expanded(
                                child: Text(
                                  result.isOutOfStock
                                      ? 'OUT OF STOCK'
                                      : 'AVAILABLE STOCK',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: result.isOutOfStock
                                        ? omanRed
                                        : omanDarkGreen,
                                  ),
                                ),
                              ),

                              Text(
                                '${result.stock}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: result.isOutOfStock
                                      ? omanRed
                                      : omanDarkGreen,
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (result.hasStock) const SizedBox(height: 10),

                      // ========================================
                      // EXISTING QUANTITY
                      // ========================================
                      if (existing > 0)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xffeef4ff),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(color: const Color(0xffd7e4ff)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.shopping_cart_rounded,
                                color: Color(0xff3867d6),
                                size: 21,
                              ),

                              const SizedBox(width: 9),

                              const Expanded(
                                child: Text(
                                  'ALREADY IN ORDER',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xff3867d6),
                                  ),
                                ),
                              ),

                              Text(
                                '$existing pcs',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xff3867d6),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (existing > 0) const SizedBox(height: 10),

                      // ========================================
                      // QUANTITY
                      // ========================================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'QUANTITY',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey,
                                      letterSpacing: .5,
                                    ),
                                  ),

                                  SizedBox(height: 3),

                                  Text(
                                    'Select required quantity',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            Container(
                              decoration: BoxDecoration(
                                color: pageBackground,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    onPressed: quantity > 1
                                        ? () {
                                            setSheetState(() {
                                              quantity--;
                                            });
                                          }
                                        : null,
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                    color: omanRed,
                                  ),

                                  Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 35,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '$quantity',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),

                                  IconButton(
                                    onPressed: stockLimitReached
                                        ? null
                                        : () {
                                            setSheetState(() {
                                              quantity++;
                                            });
                                          },
                                    icon: const Icon(Icons.add_circle_outline),
                                    color: stockLimitReached
                                        ? Colors.grey
                                        : omanGreen,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ========================================
                      // STOCK LIMIT MESSAGE
                      // ========================================
                      if (maxAdditional != null && stockLimitReached)
                        Padding(
                          padding: const EdgeInsets.only(top: 7, left: 4),
                          child: Text(
                            'Maximum available to add: '
                            '$maxAdditional pcs',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                      const SizedBox(height: 10),

                      // ========================================
                      // TOTAL
                      // ========================================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: omanLightGreen,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: omanGreen.withOpacity(.20)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'TOTAL',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: omanDarkGreen,
                                          letterSpacing: .6,
                                        ),
                                      ),

                                      SizedBox(height: 3),

                                      Text(
                                        'Quantity × Unit Price',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                Text(
                                  '${totalPrice.toStringAsFixed(3)} OMR',
                                  style: const TextStyle(
                                    color: omanDarkGreen,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                              ],
                            ),

                            if (existing > 0) ...[
                              const SizedBox(height: 8),
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'After adding',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '$totalAfterAdding pcs',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: omanDarkGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ========================================
                      // ADD BUTTON
                      // ========================================
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed:
                              result.isOutOfStock ||
                                  (maxAdditional != null && maxAdditional! <= 0)
                              ? null
                              : () async {
                                  await addDrugToOrder(
                                    result,
                                    quantity: quantity,
                                  );

                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext);
                                  }
                                },
                          icon: const Icon(
                            Icons.add_shopping_cart,
                            color: Colors.white,
                          ),
                          label: Text(
                            'ADD $quantity TO ORDER • '
                            '${totalPrice.toStringAsFixed(3)} OMR',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: omanRed,
                            disabledBackgroundColor: Colors.grey.shade400,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: omanLightRed,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warehouse_rounded, color: omanRed),
              ),

              const SizedBox(width: 9),

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

          Text(
            'Search: $currentWarehouseSearchName',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),

          const SizedBox(height: 14),

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
    final Color matchColor = getMatchColor(result.matchPercent);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: result.hasOffer
              ? Colors.orange.withOpacity(.25)
              : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ======================================================
          // HEADER
          // ======================================================

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: omanLightGreen,
                  borderRadius: BorderRadius.circular(11),
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
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: matchColor.withOpacity(.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Column(
                  children: [
                    Text(
                      '${result.matchPercent.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: matchColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'MATCH',
                      style: TextStyle(
                        color: matchColor,
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
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
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: pageBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),

                    const SizedBox(width: 5),

                    Text(
                      'MATCHED ITEM',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                Text(
                  result.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  getMatchLabel(result.matchPercent),
                  style: TextStyle(
                    color: matchColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ======================================================
          // PRICE + STOCK
          // ======================================================
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: omanLightGreen,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.payments_outlined,
                        size: 18,
                        color: omanGreen,
                      ),

                      const SizedBox(width: 5),

                      Expanded(
                        child: Text(
                          '${result.price.toStringAsFixed(3)} OMR',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: omanDarkGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (result.hasStock) const SizedBox(width: 7),

              if (result.hasStock)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: result.isOutOfStock ? omanLightRed : omanLightGreen,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 16,
                        color: result.isOutOfStock ? omanRed : omanGreen,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${result.stock}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: result.isOutOfStock ? omanRed : omanDarkGreen,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // ======================================================
          // OFFER
          // ======================================================
          if (result.hasOffer) ...[
            const SizedBox(height: 9),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xfffff7e8),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_offer_rounded,
                    size: 17,
                    color: Colors.orange,
                  ),

                  const SizedBox(width: 6),

                  Expanded(
                    child: Text(
                      result.offerText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // ======================================================
          // ADD
          // ======================================================
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: result.isOutOfStock
                  ? null
                  : () => showWarehouseOrderSheet(result),
              icon: const Icon(Icons.add_shopping_cart, size: 18),
              label: Text(
                result.isOutOfStock ? 'OUT OF STOCK' : 'ADD TO ORDER',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: omanGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
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
  // DRUG INFORMATION
  // ============================================================

  Widget buildDrugInformation() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Drug Information',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          LayoutBuilder(
            builder: (context, constraints) {
              final double width = constraints.maxWidth;

              final int columns = width >= 850
                  ? 3
                  : width >= 500
                  ? 2
                  : 1;

              const double gap = 10;

              final double tileWidth = columns == 1
                  ? width
                  : (width - ((columns - 1) * gap)) / columns;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: buildDetailTile(
                      'Regn. No.',
                      widget.drug.registration,
                      Icons.badge_outlined,
                    ),
                  ),

                  SizedBox(
                    width: tileWidth,
                    child: buildDetailTile(
                      'Trade Name',
                      widget.drug.tradeName,
                      Icons.medication_rounded,
                    ),
                  ),

                  SizedBox(
                    width: tileWidth,
                    child: buildDetailTile(
                      'Pack Size',
                      widget.drug.packSize,
                      Icons.inventory_2_outlined,
                    ),
                  ),

                  SizedBox(
                    width: tileWidth,
                    child: buildDetailTile(
                      'Active 1',
                      widget.drug.active1,
                      Icons.science_outlined,
                    ),
                  ),

                  SizedBox(
                    width: tileWidth,
                    child: buildDetailTile(
                      'Active 2',
                      widget.drug.active2,
                      Icons.science_outlined,
                    ),
                  ),

                  SizedBox(
                    width: tileWidth,
                    child: buildDetailTile(
                      'Local Agent',
                      widget.drug.agent,
                      Icons.local_shipping_outlined,
                    ),
                  ),

                  SizedBox(
                    width: tileWidth,
                    child: buildDetailTile(
                      'Mfr Name',
                      widget.drug.manufacturer,
                      Icons.business_outlined,
                    ),
                  ),

                  SizedBox(
                    width: tileWidth,
                    child: buildDetailTile(
                      'Price',
                      '${widget.drug.price.toStringAsFixed(3)} OMR',
                      Icons.payments_outlined,
                    ),
                  ),
                ],
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
    return Scaffold(
      backgroundColor: pageBackground,

      appBar: AppBar(
        title: const Text(
          'Drug Details',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),

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

              buildDrugInformation(),

              const SizedBox(height: 18),

              // ==================================================
              // DEFAULT QUANTITY
              // ==================================================
              const Text(
                'Default Quantity',
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
              // SEARCH
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

              if (warehouseSearchDone) buildWarehouseResults(),

              const SizedBox(height: 10),

              // ==================================================
              // ALTERNATIVES
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
                        onShowOrderSheet: showWarehouseOrderSheet,
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
// ============================================================

class AlternativeWarehouseCard extends StatefulWidget {
  final DrugModel alternative;

  final Future<List<WarehouseResult>> Function(String searchName)
  searchFunction;

  final Future<void> Function(WarehouseResult result, {required int quantity})
  onAdd;

  final Future<void> Function(WarehouseResult result) onShowOrderSheet;

  const AlternativeWarehouseCard({
    super.key,
    required this.alternative,
    required this.searchFunction,
    required this.onAdd,
    required this.onShowOrderSheet,
  });

  @override
  State<AlternativeWarehouseCard> createState() =>
      _AlternativeWarehouseCardState();
}

// ============================================================
// ALTERNATIVE STATE
// ============================================================

class _AlternativeWarehouseCardState extends State<AlternativeWarehouseCard> {
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
      debugPrint(
        'ERROR SEARCHING ALTERNATIVE '
        '$searchName: $e',
      );

      if (!mounted) return;

      setState(() {
        results = [];
        isSearching = false;
        searchDone = true;
      });
    }
  }

  // ============================================================
  // MATCH LABEL
  // ============================================================

  String getMatchLabel(double percent) {
    if (percent >= 95) {
      return 'Excellent';
    }

    if (percent >= 85) {
      return 'Very Good';
    }

    if (percent >= 75) {
      return 'Good';
    }

    return 'Possible';
  }

  // ============================================================
  // MATCH COLOR
  // ============================================================

  Color getMatchColor(double percent) {
    if (percent >= 85) {
      return omanGreen;
    }

    if (percent >= 75) {
      return const Color(0xff5f8f00);
    }

    if (percent >= 65) {
      return Colors.orange.shade700;
    }

    return omanRed;
  }

  // ============================================================
  // WAREHOUSE CARD
  // ============================================================

  Widget buildWarehouseCard(WarehouseResult result) {
    final Color matchColor = getMatchColor(result.matchPercent);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: result.hasOffer
              ? Colors.orange.withOpacity(.25)
              : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: omanLightGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warehouse_rounded, color: omanGreen),
              ),

              const SizedBox(width: 9),

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
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      result.storeCode,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: matchColor.withOpacity(.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${result.matchPercent.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: matchColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: pageBackground,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MATCHED ITEM',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  result.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 9),

          Row(
            children: [
              Expanded(
                child: Text(
                  '${result.price.toStringAsFixed(3)} OMR',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: omanDarkGreen,
                  ),
                ),
              ),

              if (result.hasStock)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: result.isOutOfStock ? omanLightRed : omanLightGreen,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    'Stock ${result.stock}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: result.isOutOfStock ? omanRed : omanDarkGreen,
                    ),
                  ),
                ),
            ],
          ),

          if (result.hasOffer) ...[
            const SizedBox(height: 7),
            Row(
              children: [
                const Icon(
                  Icons.local_offer_rounded,
                  size: 15,
                  color: Colors.orange,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    result.offerText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 9),

          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton.icon(
              onPressed: result.isOutOfStock
                  ? null
                  : () => widget.onShowOrderSheet(result),
              icon: const Icon(Icons.add_shopping_cart, size: 16),
              label: Text(
                result.isOutOfStock ? 'OUT OF STOCK' : 'ADD TO ORDER',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: omanGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                elevation: 0,
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

  // ============================================================
  // RESULTS
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.alternative.tradeName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),

                    const SizedBox(height: 7),

                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: omanLightGreen,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: omanGreen.withOpacity(.18),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.payments_outlined,
                                  size: 13,
                                  color: omanDarkGreen,
                                ),

                                const SizedBox(width: 4),

                                Flexible(
                                  child: Text(
                                    '${widget.alternative.price.toStringAsFixed(3)} OMR',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: omanDarkGreen,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: 7),

                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: omanLightGreen,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: omanGreen.withOpacity(.18),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.business_outlined,
                                  size: 13,
                                  color: omanDarkGreen,
                                ),

                                const SizedBox(width: 4),

                                Flexible(
                                  child: Text(
                                    widget.alternative.manufacturer,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: omanDarkGreen,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

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

          if (searchDone) buildResults(),
        ],
      ),
    );
  }
}

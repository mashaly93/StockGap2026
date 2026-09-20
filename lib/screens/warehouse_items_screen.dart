import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WarehouseItemsScreen extends StatefulWidget {
  final String pharmacyCode;

  const WarehouseItemsScreen({super.key, required this.pharmacyCode});

  @override
  State<WarehouseItemsScreen> createState() => _WarehouseItemsScreenState();
}

class _WarehouseItemsScreenState extends State<WarehouseItemsScreen> {
  // ================================================================
  // CONTROLLERS
  // ================================================================

  final TextEditingController controller = TextEditingController();

  Timer? searchTimer;

  // ================================================================
  // DATA
  // ================================================================

  List<Map<String, dynamic>> allItems = [];

  List<Map<String, dynamic>> results = [];

  List<String> searchHistory = [];

  // ================================================================
  // STATES
  // ================================================================

  bool loading = true;

  bool refreshing = false;

  bool historyLoading = true;

  // ================================================================
  // CACHE
  // ================================================================

  static const String cacheKey = "warehouse_items_cache_v2";

  static const String cacheDateKey = "warehouse_items_cache_date_v2";

  // ================================================================
  // SEARCH HISTORY
  // ================================================================

  static const String historyKey = "warehouse_items_search_history";

  static const int maxHistory = 10;

  // ================================================================
  // OMAN COLORS 🇴🇲
  // ================================================================

  static const Color omanRed = Color(0xffD81E05);

  static const Color omanGreen = Color(0xff00843D);

  static const Color omanDarkRed = Color(0xffA81708);

  static const Color backgroundColor = Color(0xffF6F8F6);

  static const Color searchFillColor = Color(0xffF1F5F2);

  // ================================================================
  // INIT
  // ================================================================

  @override
  void initState() {
    super.initState();

    controller.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    loadInitialData();
  }

  // ================================================================
  // DISPOSE
  // ================================================================

  @override
  void dispose() {
    searchTimer?.cancel();

    controller.dispose();

    super.dispose();
  }

  // ================================================================
  // INITIAL LOAD
  // ================================================================

  Future<void> loadInitialData() async {
    await loadCache();

    await loadSearchHistory();

    if (!mounted) return;

    setState(() {
      loading = false;
    });

    await refreshFromFirebase();
  }

  // ================================================================
  // CACHE
  // ================================================================

  Future<void> loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final cached = prefs.getString(cacheKey);

      if (cached == null || cached.trim().isEmpty) {
        return;
      }

      final decoded = jsonDecode(cached);

      if (decoded is! List) {
        return;
      }

      final loaded = <Map<String, dynamic>>[];

      for (final item in decoded) {
        if (item is Map) {
          loaded.add(Map<String, dynamic>.from(item));
        }
      }

      if (!mounted) return;

      setState(() {
        allItems = loaded;

        results = List<Map<String, dynamic>>.from(loaded);
      });

      debugPrint("WAREHOUSE CACHE LOADED = ${loaded.length}");
    } catch (e) {
      debugPrint("ERROR LOADING WAREHOUSE CACHE: $e");
    }
  }

  Future<void> saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(cacheKey, jsonEncode(allItems));

      await prefs.setString(cacheDateKey, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint("ERROR SAVING WAREHOUSE CACHE: $e");
    }
  }

  // ================================================================
  // FIREBASE REFRESH
  // ================================================================

  Future<void> refreshFromFirebase() async {
    if (refreshing) return;

    if (mounted) {
      setState(() {
        refreshing = true;
      });
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collectionGroup("inventory")
          .get();

      final List<Map<String, dynamic>> loaded = [];

      for (final doc in snapshot.docs) {
        try {
          final data = Map<String, dynamic>.from(doc.data());

          final storeReference = doc.reference.parent.parent;

          if (storeReference == null) {
            continue;
          }

          final storeId = storeReference.id.trim();

          if (storeId.isEmpty) {
            continue;
          }

          final name = data["name"]?.toString().trim() ?? "";

          if (name.isEmpty) {
            continue;
          }

          final price = parsePrice(data["price"]);

          final active =
              data["active"] == true ||
                  data["isActive"] == true ||
                  data["active"]?.toString().toLowerCase() == "true";

          loaded.add({
            "itemId": doc.id,
            "name": name,
            "price": price,
            "storeId": storeId,
            "path": doc.reference.path,
            "active": active,
            ...data,
          });
        } catch (e) {
          debugPrint("ERROR PARSING INVENTORY DOC: $e");
        }
      }

      if (!mounted) return;

      setState(() {
        allItems = loaded;

        results = filterItems(controller.text);
      });

      await saveCache();

      debugPrint("WAREHOUSE FIREBASE ITEMS = ${loaded.length}");
    } catch (e) {
      debugPrint("ERROR REFRESHING WAREHOUSE: $e");
    } finally {
      if (mounted) {
        setState(() {
          refreshing = false;
        });
      }
    }
  }

  // ================================================================
  // ACTIVE CHECK
  // ================================================================

  bool isItemActive(Map<String, dynamic> item) {
    if (item.containsKey("active")) {
      final value = item["active"];

      if (value is bool) {
        return value;
      }

      return value?.toString().toLowerCase() != "false";
    }

    if (item.containsKey("isActive")) {
      final value = item["isActive"];

      if (value is bool) {
        return value;
      }

      return value?.toString().toLowerCase() != "false";
    }

    return true;
  }

  // ================================================================
  // SEARCH NORMALIZATION
  // ================================================================

  String normalizeSearch(String value) {
    return value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  // ================================================================
  // FILTER
  // ================================================================

  List<Map<String, dynamic>> filterItems(String query) {
    final normalizedQuery = normalizeSearch(query);

    final activeItems = allItems.where(isItemActive).toList();

    if (normalizedQuery.isEmpty) {
      return List<Map<String, dynamic>>.from(activeItems);
    }

    return activeItems.where((item) {
      final name = normalizeSearch(item["name"]?.toString() ?? "");

      final itemId = normalizeSearch(item["itemId"]?.toString() ?? "");

      final storeId = normalizeSearch(item["storeId"]?.toString() ?? "");

      final registration = normalizeSearch(
        item["registration"]?.toString() ?? "",
      );

      return name.contains(normalizedQuery) ||
          itemId.contains(normalizedQuery) ||
          storeId.contains(normalizedQuery) ||
          registration.contains(normalizedQuery);
    }).toList();
  }

  // ================================================================
  // SEARCH
  // ================================================================

  void search(String value) {
    searchTimer?.cancel();

    final query = value.trim().toLowerCase();

    if (query.isEmpty) {
      if (!mounted) return;

      setState(() {
        results = [];
      });

      return;
    }

    searchTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;

      final data = filterItems(query);

      setState(() {
        results = data;
      });

      await saveSearchHistory(query);
    });
  }

  // ================================================================
  // SUBMIT SEARCH
  // ================================================================

  Future<void> submitSearch() async {
    final query = controller.text.trim();

    if (query.isEmpty) return;

    await saveSearchHistory(query);

    search(query);

    FocusScope.of(context).unfocus();
  }

  // ================================================================
  // SEARCH HISTORY LOAD
  // ================================================================

  Future<void> loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final saved = prefs.getStringList(historyKey) ?? <String>[];

      if (!mounted) return;

      setState(() {
        searchHistory = List<String>.from(saved);

        historyLoading = false;
      });
    } catch (e) {
      debugPrint("ERROR LOADING SEARCH HISTORY: $e");

      if (!mounted) return;

      setState(() {
        historyLoading = false;
      });
    }
  }

  // ================================================================
  // SEARCH HISTORY SAVE
  // ================================================================

  Future<void> saveSearchHistory(String query) async {
    final normalized = query.trim();

    if (normalized.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      final current = prefs.getStringList(historyKey) ?? <String>[];

      current.removeWhere(
            (item) => item.toLowerCase().trim() == normalized.toLowerCase().trim(),
      );

      current.insert(0, normalized);

      if (current.length > maxHistory) {
        current.removeRange(maxHistory, current.length);
      }

      await prefs.setStringList(historyKey, current);

      if (!mounted) return;

      setState(() {
        searchHistory = List<String>.from(current);
      });
    } catch (e) {
      debugPrint("ERROR SAVING SEARCH HISTORY: $e");
    }
  }

  // ================================================================
  // DELETE HISTORY
  // ================================================================

  Future<void> deleteSearchHistory(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final current = prefs.getStringList(historyKey) ?? <String>[];

      current.remove(query);

      await prefs.setStringList(historyKey, current);

      if (!mounted) return;

      setState(() {
        searchHistory = List<String>.from(current);
      });
    } catch (e) {
      debugPrint("ERROR DELETING SEARCH HISTORY: $e");
    }
  }

  // ================================================================
  // CLEAR HISTORY
  // ================================================================

  Future<void> clearSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove(historyKey);

      if (!mounted) return;

      setState(() {
        searchHistory.clear();
      });
    } catch (e) {
      debugPrint("ERROR CLEARING SEARCH HISTORY: $e");
    }
  }

  // ================================================================
  // PARSE PRICE
  // ================================================================

  double parsePrice(dynamic value) {
    if (value == null) {
      return 0.0;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString().replaceAll(",", ".").trim()) ?? 0.0;
  }

  // ================================================================
  // PARSE QUANTITY
  // ================================================================

  int parseQuantity(dynamic value) {
    if (value == null) {
      return 0;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? 0;
  }

  // ================================================================
  // GET WAREHOUSE NAME
  // ================================================================

  String getWarehouseName(Map<String, dynamic> item) {
    final possibleKeys = [
      "warehouseName",
      "storeName",
      "warehouse",
      "store",
      "branchName",
      "branch",
    ];

    for (final key in possibleKeys) {
      final value = item[key];

      if (value == null) {
        continue;
      }

      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }

      if (value is Map) {
        final map = Map<String, dynamic>.from(value);

        final name =
            map["name"]?.toString() ??
                map["title"]?.toString() ??
                map["storeName"]?.toString() ??
                map["warehouseName"]?.toString() ??
                "";

        if (name.trim().isNotEmpty) {
          return name.trim();
        }
      }
    }

    return item["storeId"]?.toString().trim() ?? "";
  }

  // ================================================================
  // GET OFFER
  // ================================================================

  String getOfferText(Map<String, dynamic> item) {
    final possibleKeys = [
      "offer",
      "offers",
      "offerText",
      "promotion",
      "promotions",
      "discountOffer",
      "specialOffer",
    ];

    for (final key in possibleKeys) {
      if (!item.containsKey(key)) {
        continue;
      }

      final value = item[key];

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
        return "${value.toString()}% Discount";
      }

      if (value is Map) {
        final map = Map<String, dynamic>.from(value);

        final text =
            map["text"]?.toString() ??
                map["title"]?.toString() ??
                map["description"]?.toString() ??
                map["name"]?.toString() ??
                "";

        if (text.trim().isNotEmpty) {
          return text.trim();
        }

        final discount = map["discount"] ?? map["percentage"] ?? map["percent"];

        if (discount != null) {
          return "${discount.toString()}% Discount";
        }
      }

      if (value is List && value.isNotEmpty) {
        final first = value.first;

        if (first is String) {
          final text = first.trim();

          if (text.isNotEmpty) {
            return text;
          }
        }

        if (first is Map) {
          final map = Map<String, dynamic>.from(first);

          final text =
              map["text"]?.toString() ??
                  map["title"]?.toString() ??
                  map["description"]?.toString() ??
                  map["name"]?.toString() ??
                  "";

          if (text.trim().isNotEmpty) {
            return text.trim();
          }
        }
      }
    }

    return "";
  }

  // ================================================================
  // GET CURRENT ORDER QUANTITY
  // ================================================================

  Future<int> getCurrentOrderQuantity({
    required String itemId,
    required String storeId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      const String drugDetailsKey = "drug_details_order_items";

      final savedList = prefs.getStringList(drugDetailsKey);

      if (savedList == null) {
        return 0;
      }

      for (final savedItem in savedList) {
        try {
          final decoded = jsonDecode(savedItem);

          if (decoded is! Map) {
            continue;
          }

          final oldItemId = decoded["itemId"]?.toString() ?? "";

          final oldWarehouse = decoded["warehouse"]?.toString() ?? "";

          if (oldItemId == itemId && oldWarehouse == storeId) {
            return parseQuantity(decoded["qty"]);
          }
        } catch (e) {
          debugPrint("ERROR READING ORDER QUANTITY: $e");
        }
      }
    } catch (e) {
      debugPrint("ERROR GETTING CURRENT ORDER QUANTITY: $e");
    }

    return 0;
  }

  // ================================================================
  // SET SELECTED QUANTITY TO ORDER
  // ================================================================

  Future<void> addSelectedQuantityToOrder({
    required Map<String, dynamic> item,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      _showMessage("Please select quantity", isError: true);

      return;
    }

    final itemId = item["itemId"]?.toString() ?? "";

    final storeId = item["storeId"]?.toString() ?? "";

    final name = item["name"]?.toString() ?? "";

    final price = parsePrice(item["price"]);

    final warehouseName = getWarehouseName(item);

    if (itemId.isEmpty || storeId.isEmpty || name.isEmpty) {
      _showMessage("Invalid warehouse item", isError: true);

      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      const String drugDetailsKey = "drug_details_order_items";

      final List<Map<String, dynamic>> orderItems = [];

      final savedList = prefs.getStringList(drugDetailsKey);

      if (savedList != null) {
        for (final savedItem in savedList) {
          try {
            final decoded = jsonDecode(savedItem);

            if (decoded is Map) {
              orderItems.add(Map<String, dynamic>.from(decoded));
            }
          } catch (e) {
            debugPrint("ERROR DECODING ORDER ITEM: $e");
          }
        }
      }

      // ==========================================================
      // FIND SAME ITEM + SAME WAREHOUSE
      // ==========================================================

      int existingIndex = -1;

      for (int i = 0; i < orderItems.length; i++) {
        final oldItemId = orderItems[i]["itemId"]?.toString() ?? "";

        final oldWarehouse =
            orderItems[i]["warehouse"]?.toString().trim().toLowerCase() ?? "";

        if (oldItemId == itemId &&
            oldWarehouse == storeId.trim().toLowerCase()) {
          existingIndex = i;
          break;
        }
      }

      final offer = getOfferText(item);

      // ==========================================================
      // UPDATE EXISTING ITEM
      // ==========================================================

      if (existingIndex >= 0) {
        orderItems[existingIndex]["qty"] = quantity;

        orderItems[existingIndex]["purchase"] = price;

        orderItems[existingIndex]["sale"] = price;

        orderItems[existingIndex]["warehouseName"] = warehouseName;

        if (offer.isNotEmpty) {
          orderItems[existingIndex]["offer"] = offer;
        }
      }
      // ==========================================================
      // ADD NEW ITEM
      // ==========================================================
      else {
        orderItems.add({
          "item": name,

          "qty": quantity,

          "warehouse": storeId,

          "warehouseName": warehouseName,

          "matchedItem": name,

          "matchPercent": 100.0,

          "purchase": price,

          "sale": price,

          "registration": item["registration"]?.toString() ?? "",

          "manufacturer": item["manufacturer"]?.toString() ?? "",

          "addedAt": DateTime.now().toIso8601String(),

          "itemId": itemId,

          "inventoryPath": item["path"]?.toString() ?? "",

          "pharmacyCode": widget.pharmacyCode,

          if (offer.isNotEmpty) "offer": offer,
        });
      }

      final encodedItems = orderItems.map((item) => jsonEncode(item)).toList();

      await prefs.setStringList(drugDetailsKey, encodedItems);

      if (!mounted) return;

      setState(() {});

      final total = price * quantity;

      _showMessage(
        "$name × $quantity = "
            "${total.toStringAsFixed(3)} OMR",
      );
    } catch (e, stackTrace) {
      debugPrint("ERROR ADDING WAREHOUSE ITEM TO ORDER: $e");

      debugPrint(stackTrace.toString());

      if (!mounted) return;

      _showMessage("Could not add item to order", isError: true);
    }
  }

  // ================================================================
  // SHOW ITEM ORDER SHEET
  // ================================================================

  Future<void> showItemOrderSheet(Map<String, dynamic> item) async {
    final name = item["name"]?.toString() ?? "";

    final storeId = item["storeId"]?.toString() ?? "";

    final warehouseName = getWarehouseName(item);

    final price = parsePrice(item["price"]);

    final offer = getOfferText(item);

    final itemId = item["itemId"]?.toString() ?? "";

    final currentQuantity = await getCurrentOrderQuantity(
      itemId: itemId,
      storeId: storeId,
    );

    if (!mounted) return;

    int quantity = currentQuantity > 0 ? currentQuantity : 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final totalPrice = price * quantity;

            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: const BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ==================================================
                      // HANDLE
                      // ==================================================

                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ==================================================
                      // HEADER
                      // ==================================================
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: omanRed.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.inventory_2_outlined,
                              color: omanRed,
                              size: 25,
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
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

                      const SizedBox(height: 18),

                      // ==================================================
                      // WAREHOUSE
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
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: omanGreen.withOpacity(0.09),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.storefront_outlined,
                                color: omanGreen,
                              ),
                            ),

                            const SizedBox(width: 10),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "WAREHOUSE",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade500,
                                      letterSpacing: .5,
                                    ),
                                  ),

                                  const SizedBox(height: 3),

                                  Text(
                                    warehouseName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ==================================================
                      // OFFER
                      // ==================================================
                      if (offer.isNotEmpty) ...[
                        const SizedBox(height: 12),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: omanGreen.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: omanGreen.withOpacity(0.25),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.local_offer_outlined,
                                  color: omanRed,
                                  size: 21,
                                ),
                              ),

                              const SizedBox(width: 10),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "OFFERS",
                                      style: TextStyle(
                                        color: omanRed,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      offer,
                                      style: TextStyle(
                                        color: Colors.grey.shade800,
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // ==================================================
                      // PRICE + TOTAL
                      // ==================================================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text(
                                  "Unit Price",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),

                                const Spacer(),

                                Text(
                                  "${price.toStringAsFixed(3)} OMR",
                                  style: const TextStyle(
                                    color: omanGreen,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            Divider(height: 1, color: Colors.grey.shade200),

                            const SizedBox(height: 10),

                            Row(
                              children: [
                                const Text(
                                  "TOTAL",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const Spacer(),

                                Text(
                                  "${totalPrice.toStringAsFixed(3)} OMR",
                                  style: const TextStyle(
                                    color: omanGreen,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 19,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ==================================================
                      // QUANTITY
                      // ==================================================
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
                                    "QUANTITY",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey,
                                      letterSpacing: .5,
                                    ),
                                  ),

                                  SizedBox(height: 3),

                                  Text(
                                    "Select required quantity",
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
                                color: backgroundColor,
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
                                      "$quantity",
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),

                                  IconButton(
                                    onPressed: () {
                                      setSheetState(() {
                                        quantity++;
                                      });
                                    },
                                    icon: const Icon(Icons.add_circle_outline),
                                    color: omanGreen,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ==================================================
                      // ADD TO ORDER
                      // ==================================================
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await addSelectedQuantityToOrder(
                              item: item,
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
                            "ADD $quantity TO ORDER • "
                                "${totalPrice.toStringAsFixed(3)} OMR",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: omanRed,
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

  // ================================================================
  // MESSAGE
  // ================================================================

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),

        backgroundColor: isError ? omanRed : omanGreen,

        behavior: SnackBarBehavior.floating,

        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

        margin: const EdgeInsets.all(12),
      ),
    );
  }

  // ================================================================
  // SELECT HISTORY
  // ================================================================

  void selectHistory(String value) {
    controller.text = value;

    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );

    search(value);

    FocusScope.of(context).unfocus();

    setState(() {});
  }

  // ================================================================
  // CLEAR SEARCH
  // ================================================================

  void clearSearch() {
    searchTimer?.cancel();

    controller.clear();

    FocusScope.of(context).unfocus();

    if (!mounted) return;

    setState(() {
      results = [];
    });
  }

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,

      // ==========================================================
      // APP BAR
      // ==========================================================
      appBar: AppBar(
        backgroundColor: Colors.white,

        foregroundColor: Colors.black87,

        elevation: 0,

        centerTitle: true,

        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 26,
              decoration: BoxDecoration(
                color: omanRed,
                borderRadius: BorderRadius.circular(5),
              ),
            ),

            const SizedBox(width: 7),

            const Text(
              "Warehouse",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),

            const SizedBox(width: 7),

            Container(
              width: 8,
              height: 26,
              decoration: BoxDecoration(
                color: omanGreen,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ],
        ),

        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),

        actions: [
          IconButton(
            tooltip: "Refresh",
            onPressed: refreshing ? null : refreshFromFirebase,
            icon: refreshing
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: omanGreen,
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.refresh_rounded, color: omanGreen),
          ),

          const SizedBox(width: 5),
        ],
      ),

      // ==========================================================
      // BODY
      // ==========================================================
      body: Column(
        children: [
          // ========================================================
          // SEARCH BAR
          // ========================================================

          Container(
            width: double.infinity,

            color: Colors.white,

            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),

            child: TextField(
              controller: controller,

              onChanged: (value) {
                setState(() {});

                search(value);
              },

              onSubmitted: (_) {
                submitSearch();
              },

              textInputAction: TextInputAction.search,

              decoration: InputDecoration(
                hintText: "Search warehouse item, ID or store...",

                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),

                prefixIcon: const Icon(Icons.search, color: omanRed),

                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: clearSearch,
                )
                    : null,

                filled: true,

                fillColor: searchFillColor,

                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),

                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: omanRed, width: 1.2),
                ),
              ),
            ),
          ),

          // ========================================================
          // LOADING
          // ========================================================
          if (loading || refreshing)
            const LinearProgressIndicator(
              minHeight: 2,
              color: omanRed,
              backgroundColor: Color(0xffE8EFEA),
            ),

          // ========================================================
          // CONTENT
          // ========================================================
          Expanded(
            child: controller.text.trim().isEmpty
                ? buildHistory()
                : buildResults(),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // HISTORY UI
  // ================================================================

  Widget buildHistory() {
    if (historyLoading) {
      return const Center(child: CircularProgressIndicator(color: omanRed));
    }

    if (searchHistory.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: omanRed.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.history_rounded,
                  size: 42,
                  color: omanRed,
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                "No Search History",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              Text(
                "Your recent warehouse searches\n"
                    "will appear here",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 23,
              decoration: BoxDecoration(
                color: omanRed,
                borderRadius: BorderRadius.circular(5),
              ),
            ),

            const SizedBox(width: 8),

            const Icon(Icons.history_rounded, color: omanGreen, size: 23),

            const SizedBox(width: 8),

            const Expanded(
              child: Text(
                "Recent Searches",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

            TextButton(
              onPressed: clearSearchHistory,
              child: const Text(
                "Clear All",
                style: TextStyle(color: omanRed, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        for (int index = 0; index < searchHistory.length; index++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.025),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 2,
              ),

              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: omanGreen.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.history_rounded,
                  color: omanGreen,
                  size: 21,
                ),
              ),

              title: Text(
                searchHistory[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),

              trailing: IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 19,
                  color: Colors.grey.shade500,
                ),
                onPressed: () {
                  deleteSearchHistory(searchHistory[index]);
                },
              ),

              onTap: () {
                selectHistory(searchHistory[index]);
              },
            ),
          ),
      ],
    );
  }

  // ================================================================
  // RESULTS UI
  // ================================================================

  Widget buildResults() {
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: omanGreen.withOpacity(0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 48,
                color: omanGreen,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              "No warehouse items found",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),

            const SizedBox(height: 5),

            Text(
              "Try another product name, ID or store",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 20),

      itemCount: results.length,

      itemBuilder: (context, index) {
        final item = results[index];

        return buildResultCard(item);
      },
    );
  }

  // ================================================================
  // RESULT CARD
  // ================================================================

  Widget buildResultCard(Map<String, dynamic> item) {
    final name = item["name"]?.toString() ?? "";

    final storeId = item["storeId"]?.toString() ?? "";

    final price = parsePrice(item["price"]);

    final offer = getOfferText(item);

    return FutureBuilder<int>(
      future: getCurrentOrderQuantity(
        itemId: item["itemId"]?.toString() ?? "",
        storeId: storeId,
      ),
      builder: (context, snapshot) {
        final quantity = snapshot.data ?? 0;

        final totalPrice = price * quantity;

        return Card(
          elevation: 0,

          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),

          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),

            // ======================================================
            // ICON
            // ======================================================
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: omanRed.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.inventory_2_outlined, color: omanRed),
            ),

            // ======================================================
            // CONTENT
            // ======================================================
            title: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),

            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (storeId.isNotEmpty)
                    Row(
                      children: [
                        const Icon(
                          Icons.storefront_outlined,
                          size: 14,
                          color: omanGreen,
                        ),

                        const SizedBox(width: 4),

                        Expanded(
                          child: Text(
                            "Store: ${getWarehouseName(item)}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 5),

                  Row(
                    children: [
                      Text(
                        quantity > 0
                            ? "${totalPrice.toStringAsFixed(3)} OMR"
                            : "${price.toStringAsFixed(3)} OMR",
                        style: const TextStyle(
                          color: omanGreen,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),

                      if (quantity > 0) ...[
                        const SizedBox(width: 7),

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: omanGreen.withOpacity(0.09),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            "Qty: $quantity",
                            style: const TextStyle(
                              color: omanGreen,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],

                      if (offer.isNotEmpty) ...[
                        const SizedBox(width: 8),

                        const Icon(
                          Icons.local_offer_outlined,
                          size: 14,
                          color: omanRed,
                        ),

                        const SizedBox(width: 3),

                        const Text(
                          "OFFER",
                          style: TextStyle(
                            color: omanRed,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // ======================================================
            // SHOPPING ICON
            // ======================================================
            trailing: Material(
              color: omanRed,

              borderRadius: BorderRadius.circular(11),

              child: InkWell(
                borderRadius: BorderRadius.circular(11),

                onTap: () {
                  showItemOrderSheet(item).then((_) {
                    if (mounted) {
                      setState(() {});
                    }
                  });
                },

                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.add_shopping_cart,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),

                    if (quantity > 0)
                      Positioned(
                        right: -5,
                        top: -5,
                        child: Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: omanGreen,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Text(
                            "$quantity",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/drug_model.dart';
import '../../service/drug_service.dart';
import 'drug_details_screen.dart';

class DrugSearchScreen extends StatefulWidget {
  static const routeName = "DrugSearchScreen";

  const DrugSearchScreen({super.key});

  @override
  State<DrugSearchScreen> createState() => _DrugSearchScreenState();
}

class _DrugSearchScreenState extends State<DrugSearchScreen> {
  final DrugService service = DrugService();

  final TextEditingController controller = TextEditingController();

  Timer? timer;

  List<DrugModel> allDrugs = [];
  List<DrugModel> results = [];
  List<String> searchHistory = [];

  bool loading = true;
  bool historyLoading = true;

  static const String historyKey = "drug_eye_search_history";

  static const int maxHistory = 10;

  // ================================================================
  // INIT
  // ================================================================

  @override
  void initState() {
    super.initState();

    loadData();
  }

  // ================================================================
  // LOAD DATA
  // ================================================================

  Future<void> loadData() async {
    await loadSearchHistory();
    await loadDrugs();
  }

  // ================================================================
  // LOAD SEARCH HISTORY
  // ================================================================

  Future<void> loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final history = prefs.getStringList(historyKey) ?? <String>[];

      if (!mounted) return;

      setState(() {
        searchHistory = List<String>.from(history);
        historyLoading = false;
      });

      debugPrint("SEARCH HISTORY LOADED: $searchHistory");
    } catch (e) {
      debugPrint("ERROR LOADING SEARCH HISTORY: $e");

      if (!mounted) return;

      setState(() {
        historyLoading = false;
      });
    }
  }

  // ================================================================
  // SAVE SEARCH HISTORY
  //
  // IMPORTANT:
  // This function is NOT called from onChanged.
  // It is only called when the user actually submits the search.
  // ================================================================

  Future<void> saveSearchHistory(String value) async {
    final query = value.trim();

    if (query.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      List<String> history = prefs.getStringList(historyKey) ?? <String>[];

      // Remove duplicate
      history.removeWhere(
        (item) => item.trim().toLowerCase() == query.toLowerCase(),
      );

      // Put newest search first
      history.insert(0, query);

      // Keep last 10
      if (history.length > maxHistory) {
        history = history.sublist(0, maxHistory);
      }

      await prefs.setStringList(historyKey, history);

      debugPrint("FINAL SEARCH SAVED: $query");

      if (!mounted) return;

      setState(() {
        searchHistory = List<String>.from(history);
      });
    } catch (e) {
      debugPrint("ERROR SAVING SEARCH HISTORY: $e");
    }
  }

  // ================================================================
  // DELETE ONE HISTORY ITEM
  // ================================================================

  Future<void> deleteHistoryItem(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final newHistory = List<String>.from(searchHistory);

      newHistory.remove(value);

      await prefs.setStringList(historyKey, newHistory);

      if (!mounted) return;

      setState(() {
        searchHistory = newHistory;
      });
    } catch (e) {
      debugPrint("ERROR DELETE HISTORY: $e");
    }
  }

  // ================================================================
  // CLEAR ALL HISTORY
  // ================================================================

  Future<void> clearAllHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove(historyKey);

      if (!mounted) return;

      setState(() {
        searchHistory.clear();
      });
    } catch (e) {
      debugPrint("ERROR CLEAR HISTORY: $e");
    }
  }

  // ================================================================
  // LOAD DRUGS
  // ================================================================

  Future<void> loadDrugs() async {
    try {
      final data = await service.loadAllDrugs();

      if (!mounted) return;

      setState(() {
        allDrugs = data;
        loading = false;
      });

      debugPrint("Loaded drugs: ${allDrugs.length}");
    } catch (e) {
      debugPrint("ERROR LOADING DRUGS: $e");

      if (!mounted) return;

      setState(() {
        loading = false;
      });
    }
  }

  // ================================================================
  // SEARCH
  //
  // This function ONLY searches.
  // It DOES NOT save history.
  // ================================================================

  void search(String value) {
    timer?.cancel();

    final query = value.trim().toLowerCase();

    if (query.isEmpty) {
      if (!mounted) return;

      setState(() {
        results = [];
      });

      return;
    }

    timer = Timer(const Duration(milliseconds: 300), () {
      if (allDrugs.isEmpty) {
        if (!mounted) return;

        setState(() {
          results = [];
        });

        return;
      }

      final data = allDrugs
          .where((drug) {
            final tradeName = drug.tradeName.toLowerCase();

            final active1 = drug.active1.toLowerCase();

            final active2 = drug.active2.toLowerCase();

            final manufacturer = drug.manufacturer.toLowerCase();

            final searchValues = drug.search
                .map((item) => item.toLowerCase())
                .toList();

            return tradeName.contains(query) ||
                active1.contains(query) ||
                active2.contains(query) ||
                manufacturer.contains(query) ||
                searchValues.any((item) => item.contains(query));
          })
          .take(20)
          .toList();

      if (!mounted) return;

      setState(() {
        results = data;
      });
    });
  }

  // ================================================================
  // SUBMIT SEARCH
  //
  // This is the ONLY normal place where the search
  // is added to History.
  // ================================================================

  Future<void> submitSearch() async {
    final query = controller.text.trim();

    if (query.isEmpty) return;

    // Save complete phrase only
    await saveSearchHistory(query);

    // Run search
    search(query);

    // Remove keyboard focus
    FocusScope.of(context).unfocus();
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
  }

  // ================================================================
  // CLEAR SEARCH
  // ================================================================

  void clearSearch() {
    timer?.cancel();

    controller.clear();

    FocusScope.of(context).unfocus();

    if (!mounted) return;

    setState(() {
      results = [];
    });
  }

  // ================================================================
  // OPEN DRUG
  // ================================================================

  Future<void> openDrug(DrugModel drug) async {
    final query = controller.text.trim();

    // If user searched something and did not press Enter,
    // save the complete phrase when opening a result.
    if (query.isNotEmpty) {
      await saveSearchHistory(query);
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DrugDetailsScreen(drug: drug)),
    );
  }

  // ================================================================
  // DISPOSE
  // ================================================================

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();

    super.dispose();
  }

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff6f8fc),

      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,

        centerTitle: true,

        title: const Text(
          "Drug Eye",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),

      body: Column(
        children: [
          // ==========================================================
          // SEARCH BAR
          // ==========================================================
          Container(
            width: double.infinity,
            color: Colors.white,

            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),

            child: TextField(
              controller: controller,

              // IMPORTANT:
              // Typing searches only.
              // It DOES NOT save history.
              onChanged: (value) {
                setState(() {});
                search(value);
              },

              // Enter / Search button
              onSubmitted: (_) {
                submitSearch();
              },

              textInputAction: TextInputAction.search,

              decoration: InputDecoration(
                hintText: "Search drug, active ingredient...",

                hintStyle: TextStyle(color: Colors.grey.shade500),

                prefixIcon: const Icon(Icons.search, color: Color(0xff0050c0)),

                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: clearSearch,
                      )
                    : null,

                filled: true,

                fillColor: const Color(0xfff3f6fa),

                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),

                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // ==========================================================
          // LOADING
          // ==========================================================
          if (loading) const LinearProgressIndicator(minHeight: 2),

          // ==========================================================
          // CONTENT
          // ==========================================================
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
      return const Center(child: CircularProgressIndicator());
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
                  color: const Color(0xff0050c0).withOpacity(0.08),

                  shape: BoxShape.circle,
                ),

                child: const Icon(
                  Icons.history_rounded,
                  size: 42,
                  color: Color(0xff0050c0),
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                "No Search History",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              Text(
                "Your recent drug searches\n"
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
        // ==========================================================
        // HEADER
        // ==========================================================
        Row(
          children: [
            const Icon(
              Icons.history_rounded,
              color: Color(0xff0050c0),
              size: 23,
            ),

            const SizedBox(width: 8),

            const Expanded(
              child: Text(
                "Recent Searches",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

            TextButton(
              onPressed: clearAllHistory,

              child: const Text(
                "Clear All",

                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // ==========================================================
        // HISTORY ITEMS
        // ==========================================================
        ...searchHistory.map((item) {
          return Container(
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
                  color: const Color(0xff0050c0).withOpacity(0.08),

                  borderRadius: BorderRadius.circular(10),
                ),

                child: const Icon(
                  Icons.history_rounded,
                  color: Color(0xff0050c0),
                  size: 21,
                ),
              ),

              title: Text(
                item,

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
                  deleteHistoryItem(item);
                },
              ),

              onTap: () {
                selectHistory(item);
              },
            ),
          );
        }),
      ],
    );
  }

  // ================================================================
  // RESULTS UI
  // ================================================================

  Widget buildResults() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Icon(
              Icons.medication_outlined,

              size: 60,

              color: Colors.grey.shade300,
            ),

            const SizedBox(height: 12),

            Text(
              "No drugs found",

              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),

            const SizedBox(height: 5),

            Text(
              "Try another drug name or ingredient",

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
        final drug = results[index];

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

            leading: Container(
              width: 44,
              height: 44,

              decoration: BoxDecoration(
                color: const Color(0xff0050c0).withOpacity(0.08),

                borderRadius: BorderRadius.circular(12),
              ),

              child: const Icon(
                Icons.medication_outlined,
                color: Color(0xff0050c0),
              ),
            ),

            title: Text(
              drug.tradeName,

              maxLines: 2,

              overflow: TextOverflow.ellipsis,

              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),

            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  if (drug.active1.isNotEmpty)
                    Text(
                      drug.active1,

                      maxLines: 1,

                      overflow: TextOverflow.ellipsis,
                    ),

                  if (drug.active2.isNotEmpty)
                    Text(
                      drug.active2,

                      maxLines: 1,

                      overflow: TextOverflow.ellipsis,
                    ),

                  const SizedBox(height: 4),

                  Row(
                    children: [
                      Text(
                        "Pack: ${drug.packSize}",

                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),

                      const SizedBox(width: 12),

                      Text(
                        "${drug.price.toStringAsFixed(3)} OMR",

                        style: const TextStyle(
                          color: Color(0xff16803c),

                          fontWeight: FontWeight.w600,

                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            trailing: const Icon(
              Icons.arrow_forward_ios_rounded,

              size: 16,

              color: Colors.grey,
            ),

            onTap: () {
              openDrug(drug);
            },
          ),
        );
      },
    );
  }
}

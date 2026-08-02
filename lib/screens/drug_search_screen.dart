import 'dart:async';

import 'package:flutter/material.dart';

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

  bool loading = true;

  @override
  void initState() {
    super.initState();

    loadDrugs();
  }

  Future<void> loadDrugs() async {
    final data = await service.loadAllDrugs();

    if (!mounted) return;

    setState(() {
      allDrugs = data;

      loading = false;
    });
  }

  void search(String value) {
    timer?.cancel();

    timer = Timer(const Duration(milliseconds: 300), () {
      final query = value.trim().toLowerCase();

      if (query.isEmpty) {
        setState(() {
          results = [];
        });

        return;
      }

      final data = allDrugs
          .where((drug) {
            return drug.search.any((item) => item.contains(query));
          })
          .take(20)
          .toList();

      setState(() {
        results = data;
      });
    });
  }

  void clearSearch() {
    controller.clear();

    setState(() {
      results = [];
    });
  }

  @override
  void dispose() {
    timer?.cancel();

    controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Drug Eye"),

        centerTitle: true,

        leading: IconButton(
          icon: const Icon(Icons.arrow_back),

          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),

            child: TextField(
              controller: controller,

              onChanged: search,

              decoration: InputDecoration(
                hintText: "Search drug, active ingredient...",

                prefixIcon: const Icon(Icons.search),

                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),

                        onPressed: clearSearch,
                      ),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),

          if (loading) const LinearProgressIndicator(),

          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text(
                      controller.text.isEmpty
                          ? "Start searching..."
                          : "No drugs found",

                      style: const TextStyle(fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    itemCount: results.length,

                    itemBuilder: (context, index) {
                      final drug = results[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,

                          vertical: 6,
                        ),

                        child: ListTile(
                          title: Text(
                            drug.tradeName,

                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),

                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [
                              if (drug.active1.isNotEmpty) Text(drug.active1),

                              if (drug.active2.isNotEmpty) Text(drug.active2),

                              Text("Pack: ${drug.packSize}"),

                              Text(
                                "Price: ${drug.price.toStringAsFixed(3)} OMR",
                              ),
                            ],
                          ),

                          trailing: const Icon(
                            Icons.arrow_forward_ios,

                            size: 16,
                          ),

                          onTap: () {
                            Navigator.push(
                              context,

                              MaterialPageRoute(
                                builder: (_) => DrugDetailsScreen(drug: drug),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

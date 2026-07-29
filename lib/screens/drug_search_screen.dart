import 'dart:async';
import 'package:flutter/material.dart';
import 'package:stockgap2026/service/drug_service.dart';

import '../../models/drug_model.dart';
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

  List<DrugModel> results = [];

  bool loading = false;

  void search(String value) {
    timer?.cancel();

    timer = Timer(const Duration(milliseconds: 500), () async {
      if (value.trim().isEmpty) {
        setState(() {
          results = [];
        });

        return;
      }

      setState(() {
        loading = true;
      });

      final data = await service.searchDrug(value);

      if (!mounted) return;

      setState(() {
        results = data;

        loading = false;
      });
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
      appBar: AppBar(leading: IconButton(
        color: Color(0xff0050c0),
        icon: const Icon(Icons.arrow_back),
        onPressed: () {

          Navigator.pop(context);

        },
      ),
          title: const Text("")),

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),

            child: TextField(
              controller: controller,

              onChanged: search,

              decoration: InputDecoration(
                hintText: "Search drug name or active ingredient",

                prefixIcon: const Icon(Icons.search),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          if (loading) const LinearProgressIndicator(),

          Expanded(
            child: results.isEmpty
                ? const Center(child: Text("No drugs found"))
                : ListView.builder(
                    itemCount: results.length,

                    itemBuilder: (context, index) {
                      final drug = results[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),

                        child: ListTile(
                          title: Text(
                            drug.tradeName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),

                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [
                              Text(drug.active1),

                              if (drug.active2.isNotEmpty) Text(drug.active2),

                              Text("Pack: ${drug.packSize}"),

                              Text("Price: ${drug.price}"),
                            ],
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

  void showDrugDetails(BuildContext context, DrugModel drug) {
    showModalBottomSheet(
      context: context,

      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(20),

          child: Column(
            mainAxisSize: MainAxisSize.min,

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Text(
                drug.tradeName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              Text("Registration: ${drug.registration}"),

              Text("Manufacturer: ${drug.manufacturer}"),

              Text("Agent: ${drug.agent}"),

              Text("Price: ${drug.price}"),
            ],
          ),
        );
      },
    );
  }
}

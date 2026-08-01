import 'package:flutter/material.dart';
import '../models/drug_model.dart';
import '../service/drug_service.dart';
import 'package:flutter/services.dart';
class DrugDetailsScreen extends StatefulWidget {
  final DrugModel drug;

  const DrugDetailsScreen({super.key, required this.drug});

  @override
  State<DrugDetailsScreen> createState() => _DrugDetailsScreenState();
}

class _DrugDetailsScreenState extends State<DrugDetailsScreen> {
  final DrugService service = DrugService();

  List<DrugModel> alternatives = [];

  bool loadingAlternatives = true;

  @override
  void initState() {
    super.initState();

    loadAlternatives();
  }

  Future<void> loadAlternatives() async {
    final data = await service.getAlternatives(widget.drug);

    if (!mounted) return;

    setState(() {
      alternatives = data;

      loadingAlternatives = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final drug = widget.drug;

    return Scaffold(
      appBar: AppBar(title: const Text("Drug Details"), centerTitle: true),

      body: ListView(
        padding: const EdgeInsets.all(16),

        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,

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

              IconButton(
                icon: const Icon(Icons.copy),

                onPressed: () {
                  Clipboard.setData(ClipboardData(text: drug.tradeName));

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text("Copied")));
                },
              ),
            ],
          ),

          const SizedBox(height: 20),

          buildTile("Registration", drug.registration, Icons.badge),

          buildTile("Pack Size", drug.packSize, Icons.inventory_2),

          buildTile("Active Ingredient 1", drug.active1, Icons.science),

          if (drug.active2.isNotEmpty)
            buildTile(
              "Active Ingredient 2",
              drug.active2,
              Icons.science_outlined,
            ),

          buildTile("Manufacturer", drug.manufacturer, Icons.factory),

          buildTile("Agent", drug.agent, Icons.local_shipping),

          buildTile(
            "Price",

            "${drug.price.toStringAsFixed(3)} OMR",

            Icons.attach_money,
          ),

          const SizedBox(height: 20),

          const Text(
            "🔄 Alternatives",

            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          if (loadingAlternatives)
            const Center(child: CircularProgressIndicator())
          else if (alternatives.isEmpty)
            const Text("No alternatives found")
          else
            ...alternatives.map((alt) {
              final cheapest = alternatives.first.price == alt.price;

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

                      Text("${alt.price.toStringAsFixed(3)} OMR"),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

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

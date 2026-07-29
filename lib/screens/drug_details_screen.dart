import 'package:flutter/material.dart';
import '../models/drug_model.dart';

class DrugDetailsScreen extends StatelessWidget {
  final DrugModel drug;

  const DrugDetailsScreen({super.key, required this.drug});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Drug Details"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            drug.tradeName,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 20),

          buildTile("Registration", drug.registration, Icons.badge),

          buildTile("Pack Size", drug.packSize, Icons.inventory_2),

          buildTile("Active Ingredient 1", drug.active1, Icons.science),

          if (drug.active2.trim().isNotEmpty)
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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'Homescreen.dart';
import 'OrderScreen.dart';
import 'drug_search_screen.dart';

class MainMenuScreen extends StatefulWidget {
  final String storeCode;
  final Timestamp? expireDate;
  final String role;

  const MainMenuScreen({
    super.key,
    required this.storeCode,
    required this.expireDate,
    required this.role,
  });

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('username');

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => Homescreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isStore = widget.role == "store";

    return Scaffold(
      backgroundColor: Colors.grey.shade100,

      appBar: AppBar(
        automaticallyImplyLeading: false,

        backgroundColor: Colors.grey.shade100,

        elevation: 0,

        title: const Text(
          "StockGap",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),

        centerTitle: true,

        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xff0050c0)),

            onPressed: logout,
          ),
        ],
      ),

      body: Center(
        child: Wrap(
          spacing: 30,

          runSpacing: 30,

          children: [
            // ==========================
            // Pharmacy
            // ==========================
            if (!isStore)
              MenuCard(
                title: "Generate Order",

                description: "Create pharmacy order Excel file",

                icon: Icons.inventory_2,

                color: const Color(0xff0050c0),

                onTap: () {
                  Navigator.push(
                    context,

                    MaterialPageRoute(
                      builder: (_) => OrderScreen(
                        storeCode: widget.storeCode,

                        expireDate: widget.expireDate,
                      ),
                    ),
                  );
                },
              ),

            if (!isStore)
              MenuCard(
                title: "Drug Eye",

                description: "Search drug information",

                icon: Icons.medication,

                color: Colors.green,

                onTap: () {
                  Navigator.push(
                    context,

                    MaterialPageRoute(builder: (_) => const DrugSearchScreen()),
                  );
                },
              ),

            // ==========================
            // Warehouse
            // ==========================
            if (isStore)
              MenuCard(
                title: "Inventory",

                description: "Manage warehouse stock",

                icon: Icons.warehouse,

                color: Colors.orange,

                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Inventory screen coming soon"),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class MenuCard extends StatelessWidget {
  final String title;

  final String description;

  final IconData icon;

  final Color color;

  final VoidCallback onTap;

  const MenuCard({
    super.key,

    required this.title,

    required this.description,

    required this.icon,

    required this.color,

    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,

      borderRadius: BorderRadius.circular(18),

      child: Card(
        elevation: 5,

        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),

        child: Container(
          width: 280,

          height: 160,

          padding: const EdgeInsets.all(12),

          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,

            children: [
              Container(
                width: 65,

                height: 65,

                decoration: BoxDecoration(
                  color: color.withOpacity(.12),

                  shape: BoxShape.circle,
                ),

                child: Icon(icon, size: 35, color: color),
              ),

              const SizedBox(height: 8),

              Text(
                title,

                textAlign: TextAlign.center,

                style: const TextStyle(
                  fontSize: 20,

                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                description,

                textAlign: TextAlign.center,

                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

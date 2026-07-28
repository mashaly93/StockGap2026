import 'package:flutter/material.dart';

import 'OrderScreen.dart';
import 'drug_search_screen.dart';

class MainMenuScreen extends StatelessWidget {
  final String storeCode;
  final dynamic expireDate;

  const MainMenuScreen({
    super.key,
    required this.storeCode,
    required this.expireDate,
  });

  @override
  Widget build(BuildContext context) {
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
      ),

      body: Center(
        child: Wrap(
          spacing: 30,

          runSpacing: 30,

          children: [
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
                      storeCode: storeCode,

                      expireDate: expireDate,
                    ),
                  ),
                );
              },
            ),

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
        shadowColor: Colors.black12,

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
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),

                child: Icon(icon, size: 35, color: color),
              ),

              const SizedBox(height: 8),

              Text(
                title,
                textAlign: TextAlign.center,

                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),

              const SizedBox(height: 3),

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

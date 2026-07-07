import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
class HistoryScreen extends StatefulWidget {
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}


class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();

    loadOrders();
  }
  DateTime selectedDay = DateTime.now();

  List<Map<String, dynamic>> allOrders = [];

  List<Map<String, dynamic>> dayOrders = [];

  Future<void> loadOrders() async {
    final prefs = await SharedPreferences.getInstance();

    final list = prefs.getStringList("orders") ?? [];

    allOrders = [];

    for (var e in list) {
      try {
        final data = jsonDecode(e);

        if (data is Map<String, dynamic>) {
          allOrders.add(data);
        }
      } catch (error) {
        print("Invalid order removed: $e");
      }
    }

    print("VALID ORDERS = $allOrders");

    filterOrders(selectedDay);
  }

  void filterOrders(DateTime day) {

    final date =
        "${day.year.toString().padLeft(4, '0')}-"
        "${day.month.toString().padLeft(2, '0')}-"
        "${day.day.toString().padLeft(2, '0')}";


    selectedDay = day;

    dayOrders = allOrders.where((order) {
      return order["date"] == date;
    }).toList();


    if(mounted){
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Orders History"),
        centerTitle: true,
      ),

      body: Column(
        children: [

          TableCalendar(
            firstDay: DateTime(2024),
            lastDay: DateTime(2035),
            focusedDay: selectedDay,

            selectedDayPredicate: (day) {
              return isSameDay(day, selectedDay);
            },

            onDaySelected: (selected, focused) {
              filterOrders(selected);
            },

            calendarStyle: const CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),

              selectedDecoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
            ),
          ),

          const Divider(),

          Expanded(
            child: dayOrders.isEmpty
                ? const Center(
              child: Text(
                "No Orders",
                style: TextStyle(fontSize: 18),
              ),
            )
                : ListView.builder(
              itemCount: dayOrders.length,
              itemBuilder: (context, index) {

                final order = dayOrders[index];

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),

                  child: ListTile(

                    leading: const Icon(
                      Icons.description,
                      color: Colors.green,
                    ),

                    title: Text(order["fileName"]),

                    subtitle: Text(
                      "${order["items"]} Items",
                    ),

                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [

                        IconButton(
                          icon: const Icon(Icons.folder_open),
                          onPressed: (){
                            openFile(order["filePath"]);
                          },
                        ),

                        IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.red,
                          ),
                          onPressed: (){
                            deleteOrder(index);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  Future<void> openFile(String path) async {

    final file = File(path);

    if(!await file.exists()){

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("File not found"),
        ),
      );

      return;
    }

    await Process.run(
      'cmd',
      ['/c','start','','"$path"'],
    );
  }
  Future<void> deleteOrder(int index) async {
    final prefs = await SharedPreferences.getInstance();

    final orderToDelete = dayOrders[index];

    allOrders.removeWhere((order) {
      return order["filePath"] == orderToDelete["filePath"];
    });

    final updatedList = allOrders
        .map((order) => jsonEncode(order))
        .toList();

    await prefs.setStringList("orders", updatedList);

    setState(() {
      dayOrders.removeAt(index);
    });

    print("Deleted: ${orderToDelete["fileName"]}");
  }
}


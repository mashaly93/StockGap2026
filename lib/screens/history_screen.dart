import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime selectedDay = DateTime.now();

  List<Map<String, dynamic>> allOrders = [];

  List<Map<String, dynamic>> dayOrders = [];

  bool loading = true;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    loadOrders();
  }

  // ============================================================
  // LOAD ORDERS
  // ============================================================

  Future<void> loadOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final list = prefs.getStringList("orders") ?? [];

      final loadedOrders = <Map<String, dynamic>>[];

      for (final e in list) {
        try {
          final data = jsonDecode(e);

          if (data is Map) {
            loadedOrders.add(Map<String, dynamic>.from(data));
          }
        } catch (error) {
          debugPrint("Invalid order: $e");
        }
      }

      if (!mounted) return;

      setState(() {
        allOrders = loadedOrders;
        loading = false;
      });

      filterOrders(selectedDay);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      _showMessage("Could not load order history: $e");
    }
  }

  // ============================================================
  // FILTER BY DAY
  // ============================================================

  void filterOrders(DateTime day) {
    final date =
        "${day.year.toString().padLeft(4, '0')}-"
        "${day.month.toString().padLeft(2, '0')}-"
        "${day.day.toString().padLeft(2, '0')}";

    final filtered = allOrders.where((order) {
      return order["date"]?.toString() == date;
    }).toList();

    if (!mounted) return;

    setState(() {
      selectedDay = day;
      dayOrders = filtered;
    });
  }

  // ============================================================
  // OPEN FILE
  // ============================================================

  Future<void> openFile(String path) async {
    if (path.trim().isEmpty) {
      _showMessage("File path is empty.");
      return;
    }

    final file = File(path);

    // ----------------------------------------------------------
    // CHECK FILE
    // ----------------------------------------------------------

    if (!await file.exists()) {
      _showMessage(
        "File not found.\n\n"
        "The order may have been moved or deleted.",
      );

      return;
    }

    try {
      debugPrint("OPENING ORDER FILE:");
      debugPrint(path);

      // --------------------------------------------------------
      // WINDOWS
      // --------------------------------------------------------

      if (Platform.isWindows) {
        final result = await Process.run('explorer.exe', [file.path]);

        debugPrint("Explorer exit code: ${result.exitCode}");
        debugPrint("Explorer stdout: ${result.stdout}");
        debugPrint("Explorer stderr: ${result.stderr}");

        if (result.exitCode != 0) {
          _showMessage("Could not open the order file.");
        }

        return;
      }

      // --------------------------------------------------------
      // FALLBACK
      // --------------------------------------------------------

      final result = await Process.run('cmd', ['/c', 'start', '', file.path]);

      debugPrint("Start result: ${result.exitCode}");

      if (result.exitCode != 0) {
        _showMessage("Could not open the order file.");
      }
    } catch (e) {
      debugPrint("OPEN FILE ERROR: $e");

      if (!mounted) return;

      _showMessage("Could not open file:\n$e");
    }
  }

  // ============================================================
  // OPEN FILE LOCATION
  // ============================================================

  Future<void> openFileLocation(String path) async {
    if (path.trim().isEmpty) {
      _showMessage("File path is empty.");
      return;
    }

    final file = File(path);

    if (!await file.exists()) {
      _showMessage("File not found.");
      return;
    }

    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', file.path]);
      }
    } catch (e) {
      _showMessage("Could not open file location:\n$e");
    }
  }

  // ============================================================
  // DELETE ORDER
  // ============================================================

  Future<void> deleteOrder(int index) async {
    if (index < 0 || index >= dayOrders.length) {
      return;
    }

    final orderToDelete = dayOrders[index];

    final filePath = orderToDelete["filePath"]?.toString() ?? "";

    final fileName = orderToDelete["fileName"]?.toString() ?? "Order";

    // ----------------------------------------------------------
    // CONFIRM
    // ----------------------------------------------------------

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete Order?"),
          content: Text("Do you want to remove \"$fileName\" from history?"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      // --------------------------------------------------------
      // REMOVE FROM ALL ORDERS
      // --------------------------------------------------------

      allOrders.removeWhere((order) {
        return order["filePath"]?.toString() == filePath;
      });

      // --------------------------------------------------------
      // SAVE UPDATED HISTORY
      // --------------------------------------------------------

      final updatedList = allOrders.map((order) => jsonEncode(order)).toList();

      await prefs.setStringList("orders", updatedList);

      // --------------------------------------------------------
      // REMOVE FROM CURRENT DAY
      // --------------------------------------------------------

      if (!mounted) return;

      setState(() {
        dayOrders.removeAt(index);
      });

      _showMessage("Order removed from history.");
    } catch (e) {
      _showMessage("Could not delete order:\n$e");
    }
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ============================================================
  // ORDER CARD
  // ============================================================

  Widget buildOrderCard(Map<String, dynamic> order, int index) {
    final fileName = order["fileName"]?.toString() ?? "Order.xlsx";

    final filePath = order["filePath"]?.toString() ?? "";

    final items = order["items"]?.toString() ?? "0";

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            // ==================================================
            // ICON
            // ==================================================
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.description,
                color: Colors.green,
                size: 26,
              ),
            ),

            const SizedBox(width: 12),

            // ==================================================
            // INFO
            // ==================================================
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 15,
                        color: Colors.grey,
                      ),

                      const SizedBox(width: 4),

                      Text(
                        "$items Items",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 3),

                  Text(
                    filePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // ==================================================
            // ACTIONS
            // ==================================================
            PopupMenuButton<String>(
              tooltip: "Options",
              onSelected: (value) {
                if (value == "open") {
                  openFile(filePath);
                } else if (value == "location") {
                  openFileLocation(filePath);
                } else if (value == "delete") {
                  deleteOrder(index);
                }
              },
              itemBuilder: (context) {
                return const [
                  PopupMenuItem(
                    value: "open",
                    child: Row(
                      children: [
                        Icon(Icons.folder_open, color: Colors.green),
                        SizedBox(width: 10),
                        Text("Open Order"),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: "location",
                    child: Row(
                      children: [
                        Icon(Icons.location_on_outlined, color: Colors.blue),
                        SizedBox(width: 10),
                        Text("Open File Location"),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: "delete",
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red),
                        SizedBox(width: 10),
                        Text("Delete"),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,

      appBar: AppBar(
        title: const Text(
          "Orders History",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,

        actions: [
          IconButton(
            tooltip: "Refresh",
            icon: const Icon(Icons.refresh),
            onPressed: loadOrders,
          ),
        ],
      ),

      body: Column(
        children: [
          // ======================================================
          // CALENDAR
          // ======================================================
          Card(
            margin: const EdgeInsets.all(12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: TableCalendar(
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
                    color: Color(0xff0050c0),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),

          // ======================================================
          // DATE TITLE
          // ======================================================
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  size: 18,
                  color: Color(0xff0050c0),
                ),

                const SizedBox(width: 8),

                Text(
                  "${selectedDay.day.toString().padLeft(2, '0')}/"
                  "${selectedDay.month.toString().padLeft(2, '0')}/"
                  "${selectedDay.year}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xff0050c0),
                  ),
                ),

                const Spacer(),

                Text(
                  "${dayOrders.length} Orders",
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),

          const SizedBox(height: 5),

          const Divider(),

          // ======================================================
          // ORDERS
          // ======================================================
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : dayOrders.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history,
                          size: 60,
                          color: Colors.grey.shade400,
                        ),

                        const SizedBox(height: 12),

                        const Text(
                          "No Orders",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          "No saved orders for this date.",
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: dayOrders.length,
                    itemBuilder: (context, index) {
                      final order = dayOrders[index];

                      return buildOrderCard(order, index);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

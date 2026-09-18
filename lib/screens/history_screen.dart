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
  // ============================================================
  // OMAN COLORS
  // ============================================================

  static const Color omanRed = Color(0xffC8102E);
  static const Color omanGreen = Color(0xff00843D);
  static const Color omanWhite = Color(0xffFFFFFF);

  static const Color pageBackground = Color(0xffF5F7F8);
  static const Color textDark = Color(0xff202124);
  static const Color textGrey = Color(0xff6B7280);

  // ============================================================
  // DATA
  // ============================================================

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

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),

          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: omanRed),

              SizedBox(width: 10),

              Text(
                "Delete Order?",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),

          content: Text("Do you want to remove \"$fileName\" from history?"),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },

              child: const Text("Cancel", style: TextStyle(color: textGrey)),
            ),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },

              style: ElevatedButton.styleFrom(
                backgroundColor: omanRed,
                foregroundColor: Colors.white,
                elevation: 0,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
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

      allOrders.removeWhere((order) {
        return order["filePath"]?.toString() == filePath;
      });

      final updatedList = allOrders.map((order) => jsonEncode(order)).toList();

      await prefs.setStringList("orders", updatedList);

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
      ..showSnackBar(
        SnackBar(
          content: Text(message),

          backgroundColor: omanGreen,

          behavior: SnackBarBehavior.floating,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),

          margin: const EdgeInsets.all(12),
        ),
      );
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

      elevation: 1.5,

      color: Colors.white,

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),

        side: BorderSide(color: Colors.grey.shade200),
      ),

      child: Padding(
        padding: const EdgeInsets.all(10),

        child: Row(
          children: [
            // ==================================================
            // ICON
            // ==================================================

            Container(
              width: 50,
              height: 50,

              decoration: BoxDecoration(
                color: omanGreen.withOpacity(0.10),

                borderRadius: BorderRadius.circular(12),

                border: Border.all(color: omanGreen.withOpacity(0.12)),
              ),

              child: const Icon(
                Icons.description_rounded,
                color: omanGreen,
                size: 27,
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
                      color: textDark,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 15,
                        color: omanGreen,
                      ),

                      const SizedBox(width: 4),

                      Text(
                        "$items Items",

                        style: const TextStyle(
                          color: textGrey,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

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

              icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade700),

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),

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
                        Icon(Icons.folder_open_rounded, color: omanGreen),

                        SizedBox(width: 10),

                        Text("Open Order"),
                      ],
                    ),
                  ),

                  PopupMenuItem(
                    value: "location",

                    child: Row(
                      children: [
                        Icon(Icons.location_on_outlined, color: omanRed),

                        SizedBox(width: 10),

                        Text("Open File Location"),
                      ],
                    ),
                  ),

                  PopupMenuDivider(),

                  PopupMenuItem(
                    value: "delete",

                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, color: omanRed),

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
      backgroundColor: pageBackground,

      // ========================================================
      // APP BAR
      // ========================================================
      appBar: AppBar(
        backgroundColor: omanRed,

        foregroundColor: Colors.white,

        elevation: 0,

        centerTitle: true,

        title: const Text(
          "Orders History",

          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),

        actions: [
          IconButton(
            tooltip: "Refresh",

            icon: const Icon(Icons.refresh_rounded, color: Colors.white),

            onPressed: loadOrders,
          ),
        ],
      ),

      // ========================================================
      // FULL PAGE SCROLL
      // ========================================================
      body: CustomScrollView(
        slivers: [
          // ======================================================
          // OMAN HEADER STRIPE
          // ======================================================



          // ======================================================
          // CALENDAR
          // ======================================================
          SliverToBoxAdapter(
            child: Card(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),

              elevation: 1.5,

              color: Colors.white,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),

                side: BorderSide(color: Colors.grey.shade200),
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

                  headerStyle: const HeaderStyle(
                    titleCentered: true,

                    titleTextStyle: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: textDark,
                    ),

                    leftChevronIcon: Icon(
                      Icons.chevron_left_rounded,
                      color: omanRed,
                    ),

                    rightChevronIcon: Icon(
                      Icons.chevron_right_rounded,
                      color: omanRed,
                    ),
                  ),

                  calendarStyle: CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: omanGreen,
                      shape: BoxShape.circle,
                    ),

                    selectedDecoration: const BoxDecoration(
                      color: omanRed,
                      shape: BoxShape.circle,
                    ),

                    todayTextStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),

                    selectedTextStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),

                    weekendTextStyle: const TextStyle(color: omanRed),

                    defaultTextStyle: const TextStyle(color: textDark),

                    outsideTextStyle: TextStyle(color: Colors.grey.shade400),
                  ),
                ),
              ),
            ),
          ),

          // ======================================================
          // DATE TITLE
          // ======================================================
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),

              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),

              decoration: BoxDecoration(
                color: Colors.white,

                borderRadius: BorderRadius.circular(12),

                border: Border.all(color: Colors.grey.shade200),
              ),

              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,

                    decoration: BoxDecoration(
                      color: omanRed.withOpacity(0.10),

                      borderRadius: BorderRadius.circular(9),
                    ),

                    child: const Icon(
                      Icons.calendar_today_rounded,
                      size: 17,
                      color: omanRed,
                    ),
                  ),

                  const SizedBox(width: 9),

                  Text(
                    "${selectedDay.day.toString().padLeft(2, '0')}/"
                    "${selectedDay.month.toString().padLeft(2, '0')}/"
                    "${selectedDay.year}",

                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: omanRed,
                      fontSize: 14,
                    ),
                  ),

                  const Spacer(),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),

                    decoration: BoxDecoration(
                      color: omanGreen.withOpacity(0.10),

                      borderRadius: BorderRadius.circular(20),
                    ),

                    child: Text(
                      "${dayOrders.length} Orders",

                      style: const TextStyle(
                        color: omanGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ======================================================
          // DIVIDER
          // ======================================================
          const SliverToBoxAdapter(
            child: Divider(height: 1, indent: 14, endIndent: 14),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 4)),

          // ======================================================
          // LOADING
          // ======================================================
          if (loading)
            const SliverFillRemaining(
              hasScrollBody: false,

              child: Center(child: CircularProgressIndicator(color: omanRed)),
            )
          // ======================================================
          // NO ORDERS
          // ======================================================
          else if (dayOrders.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,

              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,

                  children: [
                    Container(
                      width: 82,
                      height: 82,

                      decoration: BoxDecoration(
                        color: omanRed.withOpacity(0.08),

                        shape: BoxShape.circle,
                      ),

                      child: const Icon(
                        Icons.history_rounded,
                        size: 43,
                        color: omanRed,
                      ),
                    ),

                    const SizedBox(height: 14),

                    const Text(
                      "No Orders",

                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textDark,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      "No saved orders for this date.",

                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            )
          // ======================================================
          // ORDERS
          // ======================================================
          else
            SliverPadding(
              padding: const EdgeInsets.only(top: 8, bottom: 20),

              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final order = dayOrders[index];

                  return buildOrderCard(order, index);
                }, childCount: dayOrders.length),
              ),
            ),
        ],
      ),
    );
  }
}

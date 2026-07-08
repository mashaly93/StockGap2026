import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'Homescreen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'history_screen.dart';
import 'matcher.dart';

class OrderScreen extends StatefulWidget {
  static const routeName = "orderScreen";
  final String storeCode;
  final Timestamp? expireDate;

  const OrderScreen({
    super.key,
    required this.storeCode,
    this.expireDate,
  });

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  late final storeCode = widget.storeCode;
  List<List<String>> inventoryRows = [];
  List<List<String>> orderRows = [];
  List<String> orders = [];
  Uint8List? generatedFileBytes;

  String? inventoryFileName;
  String? orderFileName;

  String statusText = "";

  List<List<String>> excelToRows(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) return [];

    final table = excel.tables.values.first;

    return table.rows
        .map((row) => row.map((e) => e?.value.toString() ?? "").toList())
        .toList();
  }

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

  Future<List<List<String>>> processFile(File file) async {
    final path = file.path.toLowerCase();

    if (path.endsWith(".xlsx")) {
      final bytes = await file.readAsBytes();
      return excelToRows(bytes);
    }

    if (path.endsWith(".pdf")) {
      final csv = await convertPdfToCsv(file);
      return await csvToRows(csv);
    }

    throw Exception("Only Excel or PDF files are supported.");
  }

  Future<void> pickInventory() async {
    try {
      final type = XTypeGroup(label: "Files", extensions: ["xlsx", "pdf"]);

      final xfile = await openFile(acceptedTypeGroups: [type]);

      if (xfile == null) return;

      inventoryRows = await processFile(File(xfile.path));
      inventoryFileName = xfile.name;

      setState(() {
        statusText = "Missing Items Loaded Successfully";
      });
    } catch (e) {
      setState(() {
        statusText = e.toString();
      });
    }
  }

  Future<void> pickOrder() async {
    try {
      final type = XTypeGroup(label: "Files", extensions: ["xlsx", "pdf"]);

      final xfile = await openFile(acceptedTypeGroups: [type]);

      if (xfile == null) return;

      orderRows = await processFile(File(xfile.path));
      orderFileName = xfile.name;

      setState(() {
        statusText = "Store List  Loaded Successfully";
      });
    } catch (e) {
      setState(() {
        statusText = e.toString();
      });
    }
  }

  Future<void> generateOrder() async {
    if (inventoryRows.isEmpty || orderRows.isEmpty) {
      setState(() {
        statusText = "Please select both files.";
      });
      return;
    }

    setState(() {
      statusText = "Processing...";
    });


    final excel = Excel.createExcel();

    final resultSheet = excel['Sheet1'];
    final missingSheet = excel['Missing'];


    resultSheet.appendRow([
      TextCellValue("Item"),
      TextCellValue("Qty"),
      TextCellValue("Matched Item"),
      TextCellValue("Purchase Price"),
      TextCellValue("Sale Price"),
      TextCellValue("Sale Total"),
    ]);


    missingSheet.appendRow([
      TextCellValue("Item"),
      TextCellValue("Qty"),
    ]);


    double grandSaleTotal = 0;


    // استخراج الأسعار
    List<double> extractPrices(List<String> row) {

      final prices = <double>[];


      for (final cell in row) {

        final text = cell.trim();


        if (text.contains('%')) continue;


        final value = double.tryParse(
          text.replaceAll(',', ''),
        );


        if (value != null &&
            value > 0 &&
            value < 100 &&
            !(
                prices.isEmpty &&
                    value == value.roundToDouble()
            )
        ) {
          prices.add(value);
        }
      }


      return prices;
    }



    // نبدأ من Missing Items
    for (int i = 1; i < inventoryRows.length; i++) {


      final missingRow = inventoryRows[i];


      if (missingRow.isEmpty) continue;



      String item = "";

      int qty = 0;



      // استخراج الاسم والكمية
      for (final cell in missingRow) {

        if (RegExp(r'^\d+$').hasMatch(cell)) {

          qty = int.tryParse(cell) ?? 0;

          break;
        }


        item += "$cell ";
      }


      item = item.trim();


      if (item.isEmpty) continue;



      bool found = false;



      // البحث في Price List
      for (int j = 1; j < orderRows.length; j++) {


        final priceRow = orderRows[j];


        if (priceRow.isEmpty) continue;



        String priceItem = "";



        for (int x = 1; x < priceRow.length; x++) {


          final cell = priceRow[x].trim();


          if (RegExp(r'^\d').hasMatch(cell)) {
            break;
          }


          priceItem += "$cell ";
        }



        priceItem = priceItem.trim();



        final score = Matcher.findBestMatch(
          Matcher.normalize(item),
          [
            {
              "original": priceItem,
              "normalized": Matcher.normalize(priceItem),
            }
          ],
        );



        if (score.matchedItem != null &&
            score.score >= 60) {



          final prices = extractPrices(priceRow);



          if (prices.length >= 2) {


            final purchasePrice = prices[0];

            final salePrice = prices[1];


            final saleTotal =
                salePrice * qty;


            grandSaleTotal += saleTotal;



            resultSheet.appendRow([


              TextCellValue(item),


              TextCellValue(
                qty.toString(),
              ),


              TextCellValue(
                priceItem,
              ),


              TextCellValue(
                purchasePrice.toStringAsFixed(3),
              ),


              TextCellValue(
                salePrice.toStringAsFixed(3),
              ),


              TextCellValue(
                saleTotal.toStringAsFixed(3),
              ),

            ]);


            found = true;

          }


          break;

        }

      }



      if (!found) {


        missingSheet.appendRow([

          TextCellValue(item),

          TextCellValue(
            qty.toString(),
          ),

        ]);

      }

    }



    // المجموع في النهاية

    resultSheet.appendRow([]);


    resultSheet.appendRow([

      TextCellValue(""),

      TextCellValue(""),

      TextCellValue("TOTAL"),

      TextCellValue(""),

      TextCellValue(""),

      TextCellValue(
        grandSaleTotal.toStringAsFixed(3),
      ),

    ]);



    generatedFileBytes =
        Uint8List.fromList(
          excel.encode()!,
        );



    setState(() {

      statusText = "Done ✔";

    });

  }
  void resetScreen() {
    setState(() {
      inventoryRows.clear();
      orderRows.clear();
      generatedFileBytes = null;
      inventoryFileName = null;
      orderFileName = null;
      statusText = "Ready for a new order";
    });
  }
  Future<void> saveOrderLocally({
    required String fileName,
    required String filePath,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final List<String> history =
        prefs.getStringList("orders") ?? [];

    final order = {
      "fileName": fileName,
      "filePath": filePath,
      "date": DateFormat("yyyy-MM-dd").format(DateTime.now()),
      "items": inventoryRows.length,
    };

    history.add(jsonEncode(order));

    await prefs.setStringList("orders", history);


  }
  Future<void> showOrdersHistory() async {
    final prefs = await SharedPreferences.getInstance();

    List<String> orders = prefs.getStringList("orders") ?? [];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Orders History"),
        content: SizedBox(
          height: 300,
          width: 300,
          child: ListView(
            children: orders
                .map((e) => Text(e))
                .toList(),
          ),
        ),
      ),
    );
  }

  Future<void> downloadFile(Uint8List bytes) async {
    final customName = await askFileName();

    if(customName == null) return;

    final today =
    DateFormat("yyyy-MM-dd").format(DateTime.now());

    final fileName = customName.isEmpty
        ? "Order_$today.xlsx"
        : "$customName.xlsx";
    final location = await getSaveLocation(suggestedName: fileName);

    if (location == null) return;

    final filePath = location.path.endsWith('.xlsx')
        ? location.path
        : '${location.path}.xlsx';

    final file = File(filePath);
    await file.writeAsBytes(bytes);

    setState(() {
      statusText = "Saved Successfully ✔";

    });
    await saveOrderLocally(
      fileName: fileName,
      filePath: filePath,
    );


    await Process.run('cmd', ['/c', 'start', '', filePath]);
    resetScreen();
  }
  Future<List<String>> getOrders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList("orders") ?? [];
  }


  Future<File> convertPdfToCsv(File pdfFile) async {
    final outputPath = "${pdfFile.path}.csv";

    // مسار مجلد البرنامج
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    // Java الموجودة مع البرنامج
    final javaPath = "$exeDir\\jre\\bin\\java.exe";

    // tabula.jar الموجودة مع البرنامج
    final tabulaPath = "$exeDir\\tools\\tabula.jar";

    final result = await Process.run(
      javaPath,
      [
        "-jar",
        tabulaPath,
        "-p",
        "all",
        "-f",
        "CSV",
        "-o",
        outputPath,
        pdfFile.path,
      ],
    );

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }

    return File(outputPath);
  }

  Future<List<List<String>>> csvToRows(File file) async {
    final text = await file.readAsString();

    return text
        .split("\n")
        .where((e) => e.trim().isNotEmpty)
        .map(
          (line) =>
          line.split(",").map((e) => e.replaceAll('"', '').trim()).toList(),
    )
        .toList();
  }
  Future<String?> askFileName() async {
    final controller = TextEditingController();

    return await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Save Order"),

        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "File Name",
          ),
        ),

        actions: [

          TextButton(
            onPressed: (){
              Navigator.pop(context);
            },
            child: const Text("Cancel"),
          ),

          ElevatedButton(
            onPressed: (){
              Navigator.pop(
                context,
                controller.text.trim(),
              );
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.list),
          onPressed: (){

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>  HistoryScreen(),
              ),
            );

          },
        ),

        actions: [


          IconButton(
            icon: const Icon(
              Icons.logout,
              color: Color(0xff0050c0),
            ),
            onPressed: logout,
            tooltip: "Logout",
          ),
        ],
        backgroundColor: Colors.grey.shade100,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          "",
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      backgroundColor: Colors.grey.shade100,
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 800,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),

                  const Text(
                    "Stock Gap Generator",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 40),

                  Row(
                    children: [
                      Expanded(
                        child: _buildUploadCard(
                          title: "Missing Items",
                          fileName: inventoryFileName,
                          icon: Icons.inventory,
                          onPressed: pickInventory,
                          iconColor: Color(0xff0050c0),
                        ),
                      ),

                      const SizedBox(width: 20),

                      Expanded(
                        child: _buildUploadCard(
                          title: "Price List",
                          fileName: orderFileName,
                          icon: Icons.receipt_long,
                          onPressed: pickOrder,
                          iconColor: Color(0xff0050c0),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  SizedBox(
                    height: 55,
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                      (inventoryFileName != null && orderFileName != null)
                          ? generateOrder
                          : null,
                      icon: Icon(
                        Icons.play_arrow,
                        color:
                        (inventoryFileName != null && orderFileName != null)
                            ? Colors.white
                            : Colors.white,
                      ),
                      label: const Text(
                        "Generate Order",
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,

                        disabledBackgroundColor: Color(0xff0050c0),
                        foregroundColor: Color(0xff0050c0),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  if (generatedFileBytes != null)
                    SizedBox(
                      height: 55,
                      child: ElevatedButton.icon(
                        onPressed: () => downloadFile(generatedFileBytes!),
                        icon: const Icon(
                          Icons.download,
                          color: Color(0xff0050c0),
                        ),
                        label: Center(
                          child: const Text(
                            "Save Excel",
                            style: TextStyle(color: Color(0xff0050c0)),
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 30),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          statusText,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xff0050c0),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              storeCode,
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.expireDate != null
                  ? "Valid Until: ${widget.expireDate!.toDate().day}/${widget.expireDate!.toDate().month}/${widget.expireDate!.toDate().year}"
                  : "No Validity Date",
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildUploadCard({
  required String title,
  required String? fileName,
  required IconData icon,
  required Color iconColor,
  required VoidCallback onPressed,
}) {
  final uploaded = fileName != null;

  return Card(
    elevation: 4,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(
            uploaded ? Icons.check_circle : icon,
            size: 50,
            color: uploaded ? Colors.green : Color(0xff0050c0),
          ),
          const SizedBox(height: 15),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            fileName ?? "No file selected",
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: onPressed,
            child: Text(
              uploaded ? "Change File" : "Upload",
              style: TextStyle(color: Color(0xff0050c0)),
            ),
          ),
        ],
      ),
    ),
  );
}
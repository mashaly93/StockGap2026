
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../models/drug_model.dart';
import '../service/drug_service.dart';

class DrugDetailsScreen extends StatefulWidget {
final DrugModel drug;

const DrugDetailsScreen({super.key, required this.drug});

@override
State<DrugDetailsScreen> createState() => _DrugDetailsScreenState();
}

// ============================================================
// OMAN COLORS 🇴🇲
// ============================================================

const Color omanRed = Color(0xffD22730);
const Color omanGreen = Color(0xff009A44);
const Color omanDarkGreen = Color(0xff007A35);
const Color omanLightRed = Color(0xfffff0f1);
const Color omanLightGreen = Color(0xffedf9f2);

// ============================================================
// WAREHOUSE RESULT
// ============================================================

class WarehouseResult {
final String storeCode;
final String warehouseName;
final String itemName;
final double price;
final double matchPercent;

WarehouseResult({
required this.storeCode,
required this.warehouseName,
required this.itemName,
required this.price,
required this.matchPercent,
});
}

// ============================================================
// STATE
// ============================================================

class _DrugDetailsScreenState extends State<DrugDetailsScreen> {
final DrugService service = DrugService();

final FirebaseFirestore firestore = FirebaseFirestore.instance;

// ============================================================
// WAREHOUSES
// ============================================================

final List<String> warehouseCodes = [
'M001',
'M002',
'M003',
'M004',
];

// ============================================================
// ALTERNATIVES
// ============================================================

List<DrugModel> alternatives = [];

bool loadingAlternatives = true;

// ============================================================
// WAREHOUSE SEARCH
// ============================================================

List<WarehouseResult> warehouseResults = [];

bool searchingWarehouses = false;

bool warehouseSearchDone = false;

// ============================================================
// QUANTITY
// ============================================================

final TextEditingController quantityController =
TextEditingController(text: '1');

// ============================================================
// INIT
// ============================================================

@override
void initState() {
super.initState();

loadAlternatives();
}

// ============================================================
// DISPOSE
// ============================================================

@override
void dispose() {
quantityController.dispose();

super.dispose();
}

// ============================================================
// LOAD ALTERNATIVES
// ============================================================

Future<void> loadAlternatives() async {
try {
final data = await service.getAlternatives(widget.drug);

if (!mounted) return;

setState(() {
alternatives = data;
loadingAlternatives = false;
});
} catch (e) {
debugPrint('ERROR LOADING ALTERNATIVES: $e');

if (!mounted) return;

setState(() {
alternatives = [];
loadingAlternatives = false;
});
}
}

// ============================================================
// NORMALIZE
// ============================================================

String normalizeForWarehouse(String text) {
String value = text.toLowerCase().trim();

value = value.replaceAll(
RegExp(r'[-_/\\.,()\[\]{}]+'),
' ',
);

value = value.replaceAll(
RegExp(r'\s+'),
' ',
);

final Map<String, String> replacements = {
'tablets': 'tab',
'tablet': 'tab',
'tabs': 'tab',

'capsules': 'cap',
'capsule': 'cap',
'caps': 'cap',

'syr': 'syrup',
'syp': 'syrup',

'inj': 'injection',
'amp': 'ampoule',

'crm': 'cream',
'oint': 'ointment',
};

replacements.forEach((key, replacement) {
value = value.replaceAll(
RegExp(r'\b' + key + r'\b'),
replacement,
);
});

return value.trim();
}

// ============================================================
// WORDS
// ============================================================

List<String> warehouseWords(String text) {
const Set<String> ignored = {
'mg',
'mcg',
'g',
'gm',
'kg',
'ml',
'l',
'new',
'offer',
'free',
'pcs',
'piece',
'pieces',
'pack',
'box',
'with',
'the',
};

return normalizeForWarehouse(text)
    .split(' ')
    .where(
(word) =>
word.isNotEmpty && !ignored.contains(word),
)
    .toList();
}

// ============================================================
// NUMBERS
// ============================================================

Set<String> warehouseNumbers(String text) {
return RegExp(r'\d+(?:\.\d+)?')
    .allMatches(normalizeForWarehouse(text))
    .map((match) => match.group(0)!)
    .toSet();
}

// ============================================================
// WORD SIMILARITY
// ============================================================

double simpleWordSimilarity(String a, String b) {
if (a == b) {
return 100;
}

if (a.isEmpty || b.isEmpty) {
return 0;
}

final int maxLength =
a.length > b.length ? a.length : b.length;

int differences = 0;

for (int i = 0; i < maxLength; i++) {
if (i >= a.length || i >= b.length) {
differences++;
} else if (a[i] != b[i]) {
differences++;
}
}

return 100 -
((differences / maxLength) * 100);
}

// ============================================================
// WAREHOUSE SIMILARITY
// ============================================================

double warehouseSimilarity(
String drugName,
String warehouseName,
) {
final List<String> drugWords =
warehouseWords(drugName);

final List<String> storeWords =
warehouseWords(warehouseName);

if (drugWords.isEmpty || storeWords.isEmpty) {
return 0;
}

final double firstWordScore =
simpleWordSimilarity(
drugWords.first,
storeWords.first,
);

if (firstWordScore < 60) {
return 0;
}

int matchedWords = 0;

double fuzzyTotal = 0;

final Set<int> usedStoreIndexes = {};

for (final String drugWord in drugWords) {
double bestWordScore = 0;

int bestIndex = -1;

for (int i = 0;
i < storeWords.length;
i++) {
if (usedStoreIndexes.contains(i)) {
continue;
}

final double score =
simpleWordSimilarity(
drugWord,
storeWords[i],
);

if (score > bestWordScore) {
bestWordScore = score;
bestIndex = i;
}
}

if (bestWordScore >= 80) {
matchedWords++;

fuzzyTotal += bestWordScore;

if (bestIndex >= 0) {
usedStoreIndexes.add(bestIndex);
}
}
}

if (matchedWords == 0) {
return 0;
}

final double wordScore =
fuzzyTotal / drugWords.length;

final Set<String> drugNumbers =
warehouseNumbers(drugName);

final Set<String> storeNumbers =
warehouseNumbers(warehouseName);

double numberScore = 0;

if (drugNumbers.isNotEmpty) {
if (storeNumbers.isNotEmpty) {
final int commonNumbers =
drugNumbers
    .intersection(storeNumbers)
    .length;

if (commonNumbers == drugNumbers.length) {
numberScore = 100;
} else if (commonNumbers > 0) {
numberScore =
(commonNumbers /
drugNumbers.length) *
100;
}
}
} else {
numberScore = 100;
}

double finalScore =
(wordScore * 0.75) +
(numberScore * 0.25);

if (finalScore > 100) {
finalScore = 100;
}

if (finalScore < 0) {
finalScore = 0;
}

return finalScore;
}

// ============================================================
// GET WAREHOUSE NAME
// ============================================================

String getWarehouseName(
Map<String, dynamic>? data,
String storeCode,
) {
if (data != null) {
final dynamic name = data['name'];

if (name != null &&
name.toString().trim().isNotEmpty) {
return name.toString().trim();
}

final dynamic username = data['username'];

if (username != null &&
username.toString().trim().isNotEmpty) {
return username.toString().trim();
}

final dynamic storeName = data['storeName'];

if (storeName != null &&
storeName.toString().trim().isNotEmpty) {
return storeName.toString().trim();
}
}

return storeCode;
}

// ============================================================
// SEARCH ALL WAREHOUSES
// ============================================================

Future<void> searchWarehouses() async {
if (searchingWarehouses) {
return;
}

setState(() {
searchingWarehouses = true;
warehouseSearchDone = false;
warehouseResults = [];
});

final String drugName =
widget.drug.tradeName.trim();

debugPrint('');
debugPrint(
'================================================',
);
debugPrint(
'SEARCHING ALL WAREHOUSES',
);
debugPrint('DRUG = $drugName');
debugPrint('MINIMUM MATCH = 60%');
debugPrint(
'================================================',
);

final List<WarehouseResult> found = [];

for (final String storeCode
in warehouseCodes) {
try {
debugPrint('');
debugPrint(
'-----------------------------------------------',
);
debugPrint(
'STORE CODE = $storeCode',
);

final DocumentSnapshot<
Map<String, dynamic>>
storeSnapshot =
await firestore
    .collection('stores')
    .doc(storeCode)
    .get();

final Map<String, dynamic>? storeData =
storeSnapshot.data();

final String warehouseName =
getWarehouseName(
storeData,
storeCode,
);

debugPrint(
'WAREHOUSE NAME = $warehouseName',
);

final QuerySnapshot<
Map<String, dynamic>>
snapshot =
await firestore
    .collection('stores')
    .doc(storeCode)
    .collection('inventory')
    .get();

debugPrint(
'ITEMS = ${snapshot.docs.length}',
);

WarehouseResult? bestResult;

double bestScore = 0;

for (final QueryDocumentSnapshot<
Map<String, dynamic>>
doc in snapshot.docs) {
final Map<String, dynamic> data =
doc.data();

final String itemName =
getItemName(data);

if (itemName.isEmpty) {
continue;
}

final double score =
warehouseSimilarity(
drugName,
itemName,
);

debugPrint(
'$storeCode | '
'$itemName | '
'${score.toStringAsFixed(1)}%',
);

if (score >= 60 &&
score > bestScore) {
bestScore = score;

bestResult = WarehouseResult(
storeCode: storeCode,
warehouseName: warehouseName,
itemName: itemName,
price: getPrice(data),
matchPercent: score,
);
}
}

if (bestResult != null) {
found.add(bestResult);

debugPrint(
'BEST MATCH $warehouseName:',
);

debugPrint(bestResult.itemName);

debugPrint(
'${bestResult.matchPercent}%',
);
} else {
debugPrint(
'NO MATCH >= 60% IN $warehouseName',
);
}
} catch (e) {
debugPrint(
'ERROR STORE $storeCode: $e',
);
}
}

found.sort(
(a, b) =>
b.matchPercent.compareTo(
a.matchPercent,
),
);

if (!mounted) {
return;
}

setState(() {
warehouseResults = found;
searchingWarehouses = false;
warehouseSearchDone = true;
});

debugPrint('');
debugPrint(
'================================================',
);
debugPrint('SEARCH FINISHED');
debugPrint(
'RESULTS = ${found.length}',
);
debugPrint(
'================================================',
);

if (found.isEmpty) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text(
'الصنف غير موجود في المخازن بنسبة تطابق 60% أو أكثر',
),
backgroundColor: omanRed,
),
);
}
}

// ============================================================
// GET ITEM NAME
// ============================================================

String getItemName(
Map<String, dynamic> data,
) {
const List<String> fields = [
'itemName',
'name',
'item',
'productName',
'tradeName',
];

for (final String field in fields) {
final dynamic value = data[field];

if (value == null) {
continue;
}

final String text =
value.toString().trim();

if (text.isNotEmpty) {
return text;
}
}

return '';
}

// ============================================================
// GET PRICE
// ============================================================

double getPrice(
Map<String, dynamic> data,
) {
const List<String> fields = [
'price',
'whPrice',
'warehousePrice',
'purchasePrice',
'salePrice',
];

for (final String field in fields) {
final dynamic value = data[field];

if (value == null) {
continue;
}

if (value is num) {
return value.toDouble();
}

String text = value.toString();

text = text
    .replaceAll(',', '')
    .replaceAll('OMR', '')
    .replaceAll('ر.ع.', '')
    .trim();

final double? parsed =
double.tryParse(text);

if (parsed != null) {
return parsed;
}
}

return 0;
}

// ============================================================
// QUANTITY
// ============================================================

int getQuantity() {
final String text =
quantityController.text.trim();

final int? quantity =
int.tryParse(text);

if (quantity == null || quantity <= 0) {
return 0;
}

return quantity;
}

// ============================================================
// ADD DRUG TO ORDER
// ============================================================

Future<void> addDrugToOrder(
WarehouseResult result,
) async {
final int quantity = getQuantity();

if (quantity <= 0) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text(
'Please enter a valid quantity.',
),
backgroundColor: omanRed,
),
);

return;
}

try {
final prefs =
await SharedPreferences.getInstance();

final List<String> savedItems =
prefs.getStringList(
'drug_details_order_items',
) ??
[];

final Map<String, dynamic> newItem = {
'item': widget.drug.tradeName,
'qty': quantity,
'warehouse': result.storeCode,
'warehouseName': result.warehouseName,
'matchedItem': result.itemName,
'matchPercent': result.matchPercent,
'purchase': result.price,
'sale': result.price,
'registration': widget.drug.registration,
'manufacturer': widget.drug.manufacturer,
'addedAt':
DateTime.now().toIso8601String(),
};

bool foundExisting = false;

for (int i = 0;
i < savedItems.length;
i++) {
try {
final Map<String, dynamic> oldItem =
jsonDecode(savedItems[i]);

if (oldItem['item']?.toString() ==
newItem['item']?.toString() &&
oldItem['warehouse']?.toString() ==
newItem['warehouse']?.toString() &&
oldItem['matchedItem']?.toString() ==
newItem['matchedItem']?.toString()) {
final int oldQty =
int.tryParse(
oldItem['qty']
    ?.toString() ??
'',
) ??
0;

oldItem['qty'] =
oldQty + quantity;

oldItem['warehouseName'] =
result.warehouseName;

savedItems[i] =
jsonEncode(oldItem);

foundExisting = true;

break;
}
} catch (_) {}
}

if (!foundExisting) {
savedItems.add(
jsonEncode(newItem),
);
}

await prefs.setStringList(
'drug_details_order_items',
savedItems,
);

if (!mounted) return;

ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(
'${widget.drug.tradeName} added to Drug Details Order ✔',
),
backgroundColor: omanGreen,
),
);
} catch (e) {
if (!mounted) return;

ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(
'Error adding item: $e',
),
backgroundColor: omanRed,
),
);
}
}

// ============================================================
// COPY
// ============================================================

void copyDrugName() {
Clipboard.setData(
ClipboardData(
text: widget.drug.tradeName,
),
);

ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('Copied'),
backgroundColor: omanGreen,
),
);
}

// ============================================================
// BUILD
// ============================================================

@override
Widget build(BuildContext context) {
final DrugModel drug = widget.drug;

return Scaffold(
backgroundColor: const Color(0xfff7f9f8),

// ========================================================
// APP BAR
// ========================================================

appBar: AppBar(
backgroundColor: Colors.white,
foregroundColor: Colors.black87,
elevation: 0,
centerTitle: true,

leading: IconButton(
icon: const Icon(
Icons.arrow_back_ios_new_rounded,
size: 20,
),
onPressed: () {
Navigator.pop(context);
},
),

title: Row(
mainAxisSize: MainAxisSize.min,
children: [
Container(
width: 8,
height: 26,
decoration: BoxDecoration(
color: omanRed,
borderRadius:
BorderRadius.circular(10),
),
),

const SizedBox(width: 7),

const Text(
'Drug Details',
style: TextStyle(
fontWeight: FontWeight.bold,
fontSize: 19,
),
),

const SizedBox(width: 7),

Container(
width: 8,
height: 26,
decoration: BoxDecoration(
color: omanGreen,
borderRadius:
BorderRadius.circular(10),
),
),
],
),
),

// ========================================================
// BODY
// ========================================================

body: ListView(
padding: const EdgeInsets.all(16),

children: [
// ====================================================
// DRUG HEADER
// ====================================================

Container(
padding: const EdgeInsets.all(18),

decoration: BoxDecoration(
color: Colors.white,

borderRadius:
BorderRadius.circular(18),

border: Border.all(
color: Colors.grey.shade200,
),

boxShadow: [
BoxShadow(
color:
Colors.black.withOpacity(0.035),
blurRadius: 10,
offset: const Offset(0, 3),
),
],
),

child: Row(
crossAxisAlignment:
CrossAxisAlignment.start,

children: [
Container(
width: 58,
height: 58,

decoration: BoxDecoration(
gradient:
const LinearGradient(
colors: [
omanRed,
omanGreen,
],
begin: Alignment.topCenter,
end: Alignment.bottomCenter,
),

borderRadius:
BorderRadius.circular(15),
),

child: const Icon(
Icons.medication_rounded,
color: Colors.white,
size: 31,
),
),

const SizedBox(width: 13),

Expanded(
child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,

children: [
Text(
drug.tradeName,
style:
const TextStyle(
fontSize: 23,
fontWeight:
FontWeight.bold,
height: 1.15,
),
),

const SizedBox(height: 7),

Text(
drug.manufacturer,
maxLines: 2,
overflow:
TextOverflow.ellipsis,
style: TextStyle(
fontSize: 13,
color:
Colors.grey.shade600,
),
),
],
),
),

IconButton(
tooltip: 'Copy',
style:
IconButton.styleFrom(
backgroundColor:
omanLightGreen,
),
icon: const Icon(
Icons.copy_rounded,
color: omanGreen,
size: 20,
),
onPressed: copyDrugName,
),
],
),
),

const SizedBox(height: 16),

// ====================================================
// DETAILS
// ====================================================

buildTile(
'Registration',
drug.registration,
Icons.badge_outlined,
),

buildTile(
'Pack Size',
drug.packSize,
Icons.inventory_2_outlined,
),

buildTile(
'Active Ingredient 1',
drug.active1,
Icons.science_outlined,
),

if (drug.active2.isNotEmpty)
buildTile(
'Active Ingredient 2',
drug.active2,
Icons.science_outlined,
),

buildTile(
'Manufacturer',
drug.manufacturer,
Icons.factory_outlined,
),

buildTile(
'Agent',
drug.agent,
Icons.local_shipping_outlined,
),

buildTile(
'Price',
'${drug.price.toStringAsFixed(3)} OMR',
Icons.payments_outlined,
valueColor: omanGreen,
),

const SizedBox(height: 8),

// ====================================================
// QUANTITY
// ====================================================

Container(
padding: const EdgeInsets.all(16),

decoration: BoxDecoration(
color: Colors.white,

borderRadius:
BorderRadius.circular(16),

border: Border.all(
color: Colors.grey.shade200,
),

boxShadow: [
BoxShadow(
color:
Colors.black.withOpacity(0.025),
blurRadius: 7,
offset: const Offset(0, 2),
),
],
),

child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,

children: [
Row(
children: [
Container(
width: 40,
height: 40,

decoration: BoxDecoration(
color: omanLightRed,
borderRadius:
BorderRadius.circular(11),
),

child: const Icon(
Icons
    .production_quantity_limits,
color: omanRed,
size: 21,
),
),

const SizedBox(width: 10),

const Text(
'Quantity',
style: TextStyle(
fontSize: 17,
fontWeight:
FontWeight.bold,
),
),
],
),

const SizedBox(height: 12),

TextField(
controller:
quantityController,

keyboardType:
TextInputType.number,

inputFormatters: [
FilteringTextInputFormatter
    .digitsOnly,
],

decoration:
InputDecoration(
hintText:
'Enter quantity',

labelText:
'Quantity',

prefixIcon:
const Icon(
Icons.numbers,
color: omanGreen,
),

filled: true,

fillColor:
const Color(
0xfff8faf9,
),

border:
OutlineInputBorder(
borderRadius:
BorderRadius.circular(
11,
),
borderSide:
BorderSide(
color:
Colors.grey.shade300,
),
),

focusedBorder:
OutlineInputBorder(
borderRadius:
BorderRadius.circular(
11,
),
borderSide:
const BorderSide(
color: omanGreen,
width: 1.5,
),
),
),
),
],
),
),

const SizedBox(height: 16),

// ====================================================
// SEARCH BUTTON
// ====================================================

SizedBox(
width: double.infinity,
height: 52,

child: ElevatedButton.icon(
onPressed:
searchingWarehouses
? null
    : searchWarehouses,

icon: searchingWarehouses
? const SizedBox(
width: 21,
height: 21,
child:
CircularProgressIndicator(
strokeWidth: 2.2,
color: Colors.white,
),
)
    : const Icon(
Icons.warehouse_rounded,
),

label: Text(
searchingWarehouses
? 'Searching Warehouses...'
    : 'Search in Warehouses',
style: const TextStyle(
fontSize: 15,
fontWeight:
FontWeight.bold,
),
),

style:
ElevatedButton.styleFrom(
backgroundColor:
omanRed,

foregroundColor:
Colors.white,

disabledBackgroundColor:
Colors.grey.shade400,

elevation: 1,

shape:
RoundedRectangleBorder(
borderRadius:
BorderRadius.circular(13),
),
),
),
),

const SizedBox(height: 18),

// ====================================================
// WAREHOUSE RESULTS
// ====================================================

if (warehouseSearchDone)
buildWarehouseResults(),

const SizedBox(height: 22),

// ====================================================
// ALTERNATIVES HEADER
// ====================================================

Row(
children: [
Container(
width: 40,
height: 40,

decoration: BoxDecoration(
color: omanLightGreen,
borderRadius:
BorderRadius.circular(11),
),

child: const Icon(
Icons.sync_alt_rounded,
color: omanGreen,
),
),

const SizedBox(width: 10),

const Text(
'Alternatives',
style: TextStyle(
fontSize: 20,
fontWeight: FontWeight.bold,
),
),
],
),

const SizedBox(height: 10),

if (loadingAlternatives)
const Padding(
padding:
EdgeInsets.all(20),
child: Center(
child:
CircularProgressIndicator(
color: omanGreen,
),
),
)
else if (alternatives.isEmpty)
Container(
padding:
const EdgeInsets.all(16),

decoration: BoxDecoration(
color: Colors.white,
borderRadius:
BorderRadius.circular(14),
border: Border.all(
color:
Colors.grey.shade200,
),
),

child: const Text(
'No alternatives found',
style: TextStyle(
color: Colors.grey,
),
),
)
else
...alternatives.map((alt) {
final bool cheapest =
alternatives.first.price ==
alt.price;

return Container(
margin:
const EdgeInsets.only(
bottom: 9,
),

decoration:
BoxDecoration(
color: Colors.white,

borderRadius:
BorderRadius.circular(14),

border: Border.all(
color:
cheapest
? omanGreen
    .withOpacity(
0.35,
)
    : Colors
    .grey
    .shade200,
),
),

child: ListTile(
contentPadding:
const EdgeInsets
    .symmetric(
horizontal: 13,
vertical: 4,
),

leading: Container(
width: 43,
height: 43,

decoration:
BoxDecoration(
color: cheapest
? omanLightGreen
    : omanLightRed,

borderRadius:
BorderRadius
    .circular(11),
),

child: Icon(
cheapest
? Icons.star_rounded
    : Icons
    .medication_outlined,
color: cheapest
? omanGreen
    : omanRed,
),
),

title: Text(
alt.tradeName,
style:
const TextStyle(
fontWeight:
FontWeight.bold,
),
),

subtitle:
Column(
crossAxisAlignment:
CrossAxisAlignment
    .start,

children: [
const SizedBox(
height: 3,
),

Text(
alt.manufacturer,
maxLines: 1,
overflow:
TextOverflow
    .ellipsis,
),

const SizedBox(
height: 3,
),

Text(
'${alt.price.toStringAsFixed(3)} OMR',
style:
const TextStyle(
color: omanGreen,
fontWeight:
FontWeight.bold,
),
),
],
),

trailing: cheapest
? Container(
padding:
const EdgeInsets
    .symmetric(
horizontal: 8,
vertical: 5,
),
decoration:
BoxDecoration(
color:
omanGreen,
borderRadius:
BorderRadius
    .circular(
7,
),
),
child:
const Text(
'BEST',
style:
TextStyle(
color:
Colors.white,
fontSize: 10,
fontWeight:
FontWeight
    .bold,
),
),
)
    : null,
),
);
}),
],
),
);
}

// ==========================================================
// WAREHOUSE RESULTS
// ==========================================================

Widget buildWarehouseResults() {
return Container(
padding: const EdgeInsets.all(15),

decoration: BoxDecoration(
color: Colors.white,

borderRadius:
BorderRadius.circular(17),

border: Border.all(
color: Colors.grey.shade200,
),

boxShadow: [
BoxShadow(
color:
Colors.black.withOpacity(0.035),
blurRadius: 9,
offset: const Offset(0, 3),
),
],
),

child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,

children: [
// ==================================================
// HEADER
// ==================================================

Row(
children: [
Container(
width: 43,
height: 43,

decoration: BoxDecoration(
color: omanLightGreen,
borderRadius:
BorderRadius.circular(11),
),

child: const Icon(
Icons.warehouse_rounded,
color: omanGreen,
),
),

const SizedBox(width: 10),

const Expanded(
child: Text(
'Available in Warehouses',
style: TextStyle(
fontSize: 18,
fontWeight:
FontWeight.bold,
),
),
),

if (warehouseResults.isNotEmpty)
Container(
padding:
const EdgeInsets
    .symmetric(
horizontal: 10,
vertical: 6,
),

decoration:
BoxDecoration(
color: omanGreen,
borderRadius:
BorderRadius.circular(
20,
),
),

child: Text(
'${warehouseResults.length}',
style:
const TextStyle(
fontWeight:
FontWeight.bold,
color: Colors.white,
),
),
),
],
),

const SizedBox(height: 14),

// ==================================================
// NO RESULTS
// ==================================================

if (warehouseResults.isEmpty)
Container(
width: double.infinity,

padding:
const EdgeInsets.all(14),

decoration:
BoxDecoration(
color: omanLightRed,
borderRadius:
BorderRadius.circular(11),
border: Border.all(
color: omanRed
    .withOpacity(0.15),
),
),

child: const Row(
children: [
Icon(
Icons
    .inventory_2_outlined,
color: omanRed,
),

SizedBox(width: 10),

Expanded(
child: Text(
'الصنف غير موجود في أي مخزن',
style: TextStyle(
color: omanRed,
fontWeight:
FontWeight.bold,
),
),
),
],
),
)
else
LayoutBuilder(
builder:
(context, constraints) {
final double width =
constraints.maxWidth;

int columns;

if (width >= 1100) {
columns = 4;
} else if (width >= 800) {
columns = 3;
} else if (width >= 520) {
columns = 2;
} else {
columns = 1;
}

const double spacing =
10;

final double cardWidth =
(width -
((columns - 1) *
spacing)) /
columns;

return Wrap(
spacing: spacing,
runSpacing: spacing,

children:
warehouseResults
    .map(
(result) {
return SizedBox(
width: cardWidth,
child:
buildWarehouseCard(
result,
),
);
},
).toList(),
);
},
),
],
),
);
}

// ==========================================================
// WAREHOUSE CARD
// ==========================================================

Widget buildWarehouseCard(
WarehouseResult result,
) {
final int quantity =
getQuantity();

return Container(
padding: const EdgeInsets.all(13),

decoration: BoxDecoration(
color: Colors.white,

border: Border.all(
color: Colors.grey.shade200,
),

borderRadius:
BorderRadius.circular(14),

boxShadow: [
BoxShadow(
color:
Colors.black.withOpacity(0.025),
blurRadius: 6,
offset: const Offset(0, 2),
),
],
),

child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,

children: [
// ==================================================
// TOP
// ==================================================

Row(
children: [
Container(
width: 43,
height: 43,

decoration: BoxDecoration(
color: omanLightGreen,
borderRadius:
BorderRadius.circular(11),
),

child: const Icon(
Icons.warehouse_rounded,
color: omanGreen,
size: 21,
),
),

const SizedBox(width: 9),

Expanded(
child: Text(
result.warehouseName,
maxLines: 1,
overflow:
TextOverflow.ellipsis,
style:
const TextStyle(
fontSize: 15,
fontWeight:
FontWeight.bold,
),
),
),

// MATCH %

Container(
padding:
const EdgeInsets
    .symmetric(
horizontal: 8,
vertical: 5,
),

decoration:
BoxDecoration(
color: omanGreen,
borderRadius:
BorderRadius.circular(
8,
),
),

child: Text(
'${result.matchPercent.toStringAsFixed(0)}%',
style:
const TextStyle(
fontSize: 11,
fontWeight:
FontWeight.bold,
color: Colors.white,
),
),
),
],
),

const SizedBox(height: 11),

// ==================================================
// ITEM
// ==================================================

Container(
width: double.infinity,

padding:
const EdgeInsets.all(9),

decoration:
BoxDecoration(
color:
const Color(0xfff8faf9),
borderRadius:
BorderRadius.circular(9),
),

child: Text(
result.itemName,
maxLines: 2,
overflow:
TextOverflow.ellipsis,
style: TextStyle(
fontSize: 13,
color:
Colors.grey.shade700,
height: 1.3,
),
),
),

const SizedBox(height: 9),

// ==================================================
// PRICE
// ==================================================

Row(
children: [
Container(
width: 30,
height: 30,

decoration:
BoxDecoration(
color: omanLightGreen,
borderRadius:
BorderRadius.circular(
8,
),
),

child: const Icon(
Icons
    .payments_outlined,
size: 17,
color: omanGreen,
),
),

const SizedBox(width: 7),

Text(
'${result.price.toStringAsFixed(3)} OMR',
style:
const TextStyle(
fontSize: 14,
fontWeight:
FontWeight.bold,
color: omanGreen,
),
),
],
),

const SizedBox(height: 10),

// ==================================================
// ADD BUTTON
// ==================================================

SizedBox(
width: double.infinity,
height: 40,

child:
ElevatedButton.icon(
onPressed: quantity > 0
? () {
addDrugToOrder(
result,
);
}
    : null,

icon: const Icon(
Icons
    .add_shopping_cart_rounded,
size: 17,
),

label: Text(
quantity > 0
? 'Add $quantity'
    : 'Enter Quantity',
),

style:
ElevatedButton.styleFrom(
backgroundColor:
omanGreen,

foregroundColor:
Colors.white,

disabledBackgroundColor:
Colors.grey.shade400,

disabledForegroundColor:
Colors.white,

elevation: 0,

padding:
const EdgeInsets
    .symmetric(
horizontal: 8,
),

shape:
RoundedRectangleBorder(
borderRadius:
BorderRadius.circular(
9,
),
),
),
),
),
],
),
);
}

// ==========================================================
// DETAIL TILE
// ==========================================================

Widget buildTile(
String title,
String value,
IconData icon, {
Color? valueColor,
}) {
return Container(
margin:
const EdgeInsets.only(
bottom: 10,
),

decoration: BoxDecoration(
color: Colors.white,

borderRadius:
BorderRadius.circular(14),

border: Border.all(
color: Colors.grey.shade200,
),
),

child: ListTile(
contentPadding:
const EdgeInsets.symmetric(
horizontal: 13,
vertical: 3,
),

leading: Container(
width: 40,
height: 40,

decoration: BoxDecoration(
color: omanLightRed,
borderRadius:
BorderRadius.circular(10),
),

child: Icon(
icon,
color: omanRed,
size: 21,
),
),

title: Text(
title,
style: TextStyle(
fontSize: 12,
color: Colors.grey.shade600,
),
),

subtitle: Padding(
padding:
const EdgeInsets.only(
top: 2,
),

child: Text(
value.isEmpty
? '-'
    : value,
style: TextStyle(
fontWeight:
FontWeight.bold,
fontSize: 14,
color:
valueColor ??
Colors.black87,
),
),
),
),
);
}
}


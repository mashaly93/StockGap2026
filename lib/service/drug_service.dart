import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/drug_model.dart';

class DrugService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<List<DrugModel>> searchDrug(String query) async {
    query = query.trim().toLowerCase();

    if (query.isEmpty) {
      return [];
    }

    List<DrugModel> drugs = [];

    // 1- Search in search array
    final searchResult = await _db
        .collection("drugs")
        .where("search", arrayContains: query)
        .limit(20)
        .get();

    drugs.addAll(
      searchResult.docs.map((doc) => DrugModel.fromMap(doc.id, doc.data())),
    );

    // 2- Search trade name
    final nameResult = await _db
        .collection("drugs")
        .where("tradeNameLower", isGreaterThanOrEqualTo: query)
        .where("tradeNameLower", isLessThan: '$query\uf8ff')
        .limit(20)
        .get();

    for (var doc in nameResult.docs) {
      if (!drugs.any((d) => d.id == doc.id)) {
        drugs.add(DrugModel.fromMap(doc.id, doc.data()));
      }
    }

    // 3- Search active ingredient
    final activeResult = await _db
        .collection("drugs")
        .where("active1Lower", isGreaterThanOrEqualTo: query)
        .where("active1Lower", isLessThan: '$query\uf8ff')
        .limit(20)
        .get();

    for (var doc in activeResult.docs) {
      if (!drugs.any((d) => d.id == doc.id)) {
        drugs.add(DrugModel.fromMap(doc.id, doc.data()));
      }
    }

    return drugs.take(30).toList();
  }

  Future<DrugModel?> getDrugById(String id) async {
    final doc = await _db.collection("drugs").doc(id).get();

    if (!doc.exists) {
      return null;
    }

    return DrugModel.fromMap(doc.id, doc.data()!);
  }
}

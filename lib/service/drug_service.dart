import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/drug_model.dart';

class DrugService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<DrugModel> _allDrugs = [];

  bool _loaded = false;

  // ==========================
  // Load all drugs with Cache
  // ==========================
  Future<List<DrugModel>> loadAllDrugs() async {
    if (_loaded) {
      return _allDrugs;
    }

    final box = Hive.box("drugs");

    // ==========================
    // Load from local cache
    // ==========================
    if (box.isNotEmpty) {
      _allDrugs = box.values.map((e) {
        return DrugModel.fromLocal(Map<String, dynamic>.from(e));
      }).toList();

      _loaded = true;

      print("Loaded from Hive: ${_allDrugs.length}");

      return _allDrugs;
    }

    // ==========================
    // First time Firebase
    // ==========================
    final snapshot = await _db.collection("drugs").get();

    _allDrugs = snapshot.docs
        .map((e) => DrugModel.fromMap(e.id, e.data()))
        .toList();

    // ==========================
    // Save to Hive
    // ==========================
    await box.clear();

    for (final drug in _allDrugs) {
      await box.put(drug.id, drug.toMap());
    }

    _loaded = true;

    print("Loaded from Firebase: ${_allDrugs.length}");

    return _allDrugs;
  }

  // ==========================
  // Local Search
  // ==========================
  List<DrugModel> searchLocal(String query) {
    query = query.trim().toLowerCase();

    if (query.isEmpty) {
      return [];
    }

    final results = _allDrugs.where((drug) {
      return drug.search.any((item) => item.toLowerCase().contains(query));
    }).toList();

    results.sort((a, b) {
      int scoreA = _score(a, query);

      int scoreB = _score(b, query);

      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA);
      }

      return a.tradeName.compareTo(b.tradeName);
    });

    return results.take(50).toList();
  }

  int _score(DrugModel drug, String query) {
    final name = drug.tradeName.toLowerCase();

    final active1 = drug.active1.toLowerCase();

    final active2 = drug.active2.toLowerCase();

    final reg = drug.registration.toLowerCase();

    if (name.startsWith(query)) return 100;

    if (name.contains(query)) return 90;

    if (active1.startsWith(query)) return 80;

    if (active2.startsWith(query)) return 70;

    if (reg.startsWith(query)) return 60;

    return 10;
  }

  // ==========================
  // Alternatives
  // ==========================
  Future<List<DrugModel>> getAlternatives(DrugModel drug) async {
    await loadAllDrugs();

    final alternatives = _allDrugs.where((d) {
      if (d.id == drug.id) {
        return false;
      }

      final sameActive1 =
          d.active1.trim().toLowerCase() == drug.active1.trim().toLowerCase();

      final sameActive2 =
          d.active2.trim().isEmpty ||
          d.active2.trim().toLowerCase() == drug.active2.trim().toLowerCase();

      final sameStrength = d.strength == drug.strength;

      return sameActive1 && sameActive2 && sameStrength;
    }).toList();

    alternatives.sort((a, b) => a.price.compareTo(b.price));

    return alternatives;
  }

  // ==========================
  // Get by ID
  // ==========================
  Future<DrugModel?> getDrugById(String id) async {
    await loadAllDrugs();

    try {
      return _allDrugs.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  List<DrugModel> get allDrugs => _allDrugs;
}

class MatchResult {
  final String? matchedItem;
  final double score;

  MatchResult({
    required this.matchedItem,
    required this.score,
  });
}

class Matcher {

  static const Set<String> ignoredWords = {
    "new",
    "offer",
    "free",
    "pcs",
    "piece",
    "pieces",
    "pack",
    "box",
    "with",
    "the",

    // units
    "mg",
    "mcg",
    "g",
    "gm",
    "kg",
    "ml",
    "l",
  };


  static const Map<String, String> replacements = {

    // dosage forms
    "tablet": "tab",
    "tablets": "tab",

    "capsule": "cap",
    "capsules": "cap",

    "syp": "syrup",
    "syr": "syrup",

    "crm": "cream",
    "oint": "ointment",

    "inj": "injection",
    "amp": "ampoule",

    // common names
    "fort": "forte",
    "tabs": "tab",
    "caps": "cap",
  };


  static const Set<String> forms = {

    "tab",
    "cap",
    "syrup",
    "cream",
    "ointment",
    "gel",
    "drops",
    "spray",
    "lotion",
    "shampoo",
    "wipes",
    "soap",
    "wash",
    "foam",
    "powder",

  };


  // ---------------- NORMALIZE ----------------

  static String normalize(String text) {

    text = text.toLowerCase().trim();


    // إزالة الرموز
    text = text.replaceAll(
      RegExp(r'[-_/\\.,()\[\]`]+'),
      ' ',
    );


    text = text.replaceAll(
      RegExp(r'\s+'),
      ' ',
    );


    // replacements
    replacements.forEach((key, value) {

      text = text.replaceAll(
        RegExp(r'\b$key\b'),
        value,
      );

    });


    return text.trim();
  }



  // ---------------- WORDS ----------------

  static List<String> getWords(String text) {

    return normalize(text)
        .split(' ')
        .where(
          (w) =>
      w.isNotEmpty &&
          !ignoredWords.contains(w),
    )
        .toList();

  }



  // ---------------- NUMBERS ----------------

  static Set<String> getNumbers(String text) {

    return RegExp(r'\d+')
        .allMatches(normalize(text))
        .map((e) => e.group(0)!)
        .toSet();

  }



  // ---------------- FORM ----------------

  static String? getForm(List<String> words) {

    for (final w in words) {

      if (forms.contains(w)) {
        return w;
      }

    }

    return null;
  }



  // ---------------- WORD SIMILARITY ----------------

  static double wordSimilarity(
      String a,
      String b,
      ) {

    if (a == b) return 100;


    int distance = 0;


    final len =
    a.length > b.length ? a.length : b.length;


    for (int i = 0; i < len; i++) {

      if (i >= a.length ||
          i >= b.length) {

        distance++;

      }

      else if (a[i] != b[i]) {

        distance++;

      }

    }


    return 100 - ((distance / len) * 100);

  }




  // ---------------- CORE SIMILARITY ----------------

  static double similarity(
      String orderItem,
      String storeItem,
      ) {


    final orderWords = getWords(orderItem);

    final storeWords = getWords(storeItem);



    if (orderWords.isEmpty ||
        storeWords.isEmpty) {

      return 0;

    }



    // مقارنة أول كلمة
    if (orderWords.first != storeWords.first) {

      final firstScore =
      wordSimilarity(
        orderWords.first,
        storeWords.first,
      );


      if (firstScore < 70) {

        return 0;

      }

    }




    final orderSet =
    orderWords.toSet();


    final storeSet =
    storeWords.toSet();



    final common =
    orderSet.intersection(storeSet);



    if (common.isEmpty) {

      return 0;

    }



    double score =
        common.length * 20;



    // الأرقام

    final orderNums =
    getNumbers(orderItem);


    final storeNums =
    getNumbers(storeItem);



    if (orderNums.isNotEmpty &&
        storeNums.isNotEmpty) {


      if (orderNums
          .intersection(storeNums)
          .isNotEmpty) {


        score += 20;

      }

      else {

        score -= 10;

      }

    }



    // الشكل الدوائي

    final form1 =
    getForm(orderWords);


    final form2 =
    getForm(storeWords);



    if (form1 != null &&
        form2 != null) {


      if (form1 == form2) {

        score += 20;

      }

      else {

        score -= 15;

      }

    }



    if (score < 0) return 0;

    if (score > 100) return 100;


    return score;

  }




  // ---------------- BEST MATCH ----------------


  static MatchResult findBestMatch(
      String orderItem,
      List<Map<String, String>> storeItems,
      ) {


    String? bestItem;

    double bestScore = 0;



    for (final item in storeItems) {


      final score =
      similarity(
        orderItem,
        item["normalized"]!,
      );



      if (score > bestScore) {

        bestScore = score;

        bestItem =
        item["original"]!;

      }

    }



    return MatchResult(
      matchedItem: bestItem,
      score: bestScore,
    );

  }

}
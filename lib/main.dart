import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

import 'Homescreen.dart';
import 'OrderScreen.dart';
import 'drug_search_screen.dart';
import 'main_menu_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: "StockGap",

      // الشاشة التي تظهر عند فتح التطبيق
      home: const MainMenuScreen(storeCode: '', expireDate: '',),

      routes: {
        Homescreen.routeName: (context) => Homescreen(),

        OrderScreen.routeName: (context) => OrderScreen(storeCode: ''),

        DrugSearchScreen.routeName: (context) => const DrugSearchScreen(),
      },
    );
  }
}

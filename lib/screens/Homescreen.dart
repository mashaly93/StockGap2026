import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:stockgap2026/screens/store_inventory_screen.dart';

import 'OrderScreen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'main_menu_screen.dart';

class Homescreen extends StatefulWidget {
  const Homescreen({super.key});

  static const String routeName = 'Homescreen';

  @override
  State<Homescreen> createState() => _HomescreenState();
}

class _HomescreenState extends State<Homescreen> {
  final codeController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool isCheckingLogin = false;

  @override
  void dispose() {
    codeController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkLogin();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 8,
              shadowColor: Colors.black12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  children: [
                    // ==================================================
                    // LOGO
                    // ==================================================
                    Image.asset('assets/images/back.png', scale: 2.7),

                    const SizedBox(height: 12),

                    const Text(
                      "Stock Gap Generator",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xff0050c0),
                      ),
                    ),

                    const SizedBox(height: 25),

                    // ==================================================
                    // USERNAME
                    // ==================================================
                    TextFormField(
                      controller: codeController,
                      decoration: InputDecoration(
                        labelText: 'Pharmacy / Store Code',
                        prefixIcon: const Icon(Icons.store),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Color(0xff0050c0),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 15),

                    // ==================================================
                    // PASSWORD
                    // ==================================================
                    TextFormField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Color(0xff0050c0),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 25),

                    // ==================================================
                    // LOGIN BUTTON
                    // ==================================================
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isLoading
                            ? null
                            : () async {
                                await login();
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff0050c0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text("Login"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ================================================================
  // LOGIN
  // ================================================================

  Future<void> login() async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
    });

    try {
      final username = codeController.text.trim();
      final password = passwordController.text.trim();

      // ============================================================
      // VALIDATION
      // ============================================================

      if (username.isEmpty || password.isEmpty) {
        _stopLoading();

        _showMessage("Enter username and password");

        return;
      }

      final firestore = FirebaseFirestore.instance;

      QuerySnapshot<Map<String, dynamic>> result;

      // ============================================================
      // 1. SEARCH USERS
      //    Pharmacy accounts
      // ============================================================

      result = await firestore
          .collection("users")
          .where("username", isEqualTo: username)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      bool isStore = false;

      // ============================================================
      // 2. IF NOT FOUND -> SEARCH STORES
      // ============================================================

      if (result.docs.isEmpty) {
        result = await firestore
            .collection("stores")
            .where("username", isEqualTo: username)
            .limit(1)
            .get(const GetOptions(source: Source.server));

        isStore = true;
      }

      // ============================================================
      // USER NOT FOUND
      // ============================================================

      if (result.docs.isEmpty) {
        _stopLoading();

        _showMessage("User not found");

        return;
      }

      // ============================================================
      // DOCUMENT
      // ============================================================

      final doc = result.docs.first;

      final data = doc.data();

      final docRef = doc.reference;

      // ============================================================
      // IMPORTANT
      //
      // doc.id is the REAL Firestore document ID.
      //
      // Example:
      //
      // stores
      //   └── M001
      //        ├── username: Sahara
      //        └── inventory
      //
      // So we MUST use:
      //
      // doc.id = M001
      //
      // NOT:
      //
      // username = Sahara
      // ============================================================

      final firestoreDocumentId = doc.id;

      debugPrint("=================================");
      debugPrint("LOGIN SUCCESS");
      debugPrint("COLLECTION: ${doc.reference.parent.id}");
      debugPrint("DOCUMENT ID: $firestoreDocumentId");
      debugPrint("USERNAME: $username");
      debugPrint("DATA: $data");
      debugPrint("IS STORE: $isStore");
      debugPrint("=================================");

      // ============================================================
      // PASSWORD
      // ============================================================

      if (data["password"] != password) {
        _stopLoading();

        _showMessage("Wrong password");

        return;
      }

      // ============================================================
      // ACTIVE
      //
      // Stores are currently not checked here.
      // ============================================================

      if (!isStore && data["active"] != true) {
        _stopLoading();

        _showMessage("Account disabled");

        return;
      }

      // ============================================================
      // EXPIRE DATE
      // ============================================================

      final expireDate = data["expireDate"] is Timestamp
          ? data["expireDate"] as Timestamp
          : null;

      if (expireDate != null && DateTime.now().isAfter(expireDate.toDate())) {
        _stopLoading();

        _showMessage("Subscription expired");

        return;
      }

      // ============================================================
      // DEVICE SYSTEM
      // ============================================================

      final prefs = await SharedPreferences.getInstance();

      String deviceId = prefs.getString("deviceId") ?? "";

      if (deviceId.isEmpty) {
        deviceId = DateTime.now().microsecondsSinceEpoch.toString();

        await prefs.setString("deviceId", deviceId);
      }

      // ============================================================
      // READ DEVICES
      // ============================================================

      List devices = [];

      if (data["devices"] is List) {
        devices = List.from(data["devices"]);
      }

      // ============================================================
      // CLEAN DEVICES
      // ============================================================

      devices = devices
          .where((d) => d is Map)
          .map((d) => Map<String, dynamic>.from(d))
          .toList();

      // ============================================================
      // CHECK CURRENT DEVICE
      // ============================================================

      final exists = devices.any((d) => d["deviceId"] == deviceId);

      final maxDevices = (data["maxDevices"] ?? 1) as int;

      // ============================================================
      // REGISTER NEW DEVICE
      // ============================================================

      if (!exists) {
        if (devices.length >= maxDevices) {
          _stopLoading();

          _showMessage("Too many devices logged in");

          return;
        }

        devices.add({
          "deviceId": deviceId,
          "deviceName": "Flutter Windows",
          "loginTime": DateTime.now().toIso8601String(),
        });

        await docRef.update({"devices": devices});
      }

      // ============================================================
      // ROLE
      // ============================================================

      final role = data["role"] ?? (isStore ? "store" : "pharmacy");

      // ============================================================
      // SAVE LOGIN
      // ============================================================

      await prefs.setString("username", username);

      await prefs.setString("role", role);

      // مهم جداً:
      // نحفظ document ID
      //
      // مثال:
      // username = Sahara
      // storeCode = M001

      if (isStore || role == "store") {
        await prefs.setString("storeCode", firestoreDocumentId);
      } else {
        await prefs.setString("storeCode", username);
      }

      _stopLoading();

      // ============================================================
      // STORE
      // ============================================================

      if (isStore || role == "store") {
        debugPrint("OPENING STORE INVENTORY");

        debugPrint("STORE CODE = $firestoreDocumentId");

        debugPrint(
          "INVENTORY PATH = "
          "stores/$firestoreDocumentId/inventory",
        );

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => StoreInventoryScreen(
              storeCode: firestoreDocumentId,
              expireDate: expireDate,
            ),
          ),
        );

        return;
      }

      // ============================================================
      // PHARMACY
      // ============================================================

      debugPrint("OPENING PHARMACY MENU");

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainMenuScreen(
            storeCode: username,
            expireDate: expireDate,
            role: role,
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint("LOGIN ERROR: $e");

      debugPrint(stackTrace.toString());

      _stopLoading();

      _showMessage(e.toString());
    }
  }

  // ================================================================
  // STOP LOADING
  // ================================================================

  void _stopLoading() {
    if (!mounted) return;

    setState(() {
      isLoading = false;
    });
  }

  // ================================================================
  // SHOW MESSAGE
  // ================================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ================================================================
  // CHECK LOGIN
  // ================================================================

  Future<void> checkLogin() async {
    if (isCheckingLogin) return;

    isCheckingLogin = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      final savedUser = prefs.getString("username");

      debugPrint("Saved username: $savedUser");

      // لا ندخل تلقائياً حالياً.
      // المستخدم يعمل Login كل مرة.
    } finally {
      isCheckingLogin = false;
    }
  }

  // ================================================================
  // GET DEVICE ID
  // ================================================================

  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();

    String deviceId = prefs.getString("deviceId") ?? "";

    if (deviceId.isEmpty) {
      deviceId = DateTime.now().microsecondsSinceEpoch.toString();

      await prefs.setString("deviceId", deviceId);
    }

    return deviceId;
  }

  // ================================================================
  // REGISTER DEVICE
  // ================================================================

  Future<bool> registerDevice({
    required String deviceId,
    required String deviceName,
    required List devices,
    required int maxDevices,
    required DocumentReference docRef,
  }) async {
    final alreadyExists = devices.any(
      (d) => d is Map && d["deviceId"] == deviceId,
    );

    if (alreadyExists) {
      return true;
    }

    if (devices.length >= maxDevices) {
      return false;
    }

    devices.add({
      "deviceId": deviceId,
      "deviceName": deviceName,
      "loginTime": DateTime.now().toIso8601String(),
    });

    await docRef.update({"devices": devices});

    return true;
  }
}

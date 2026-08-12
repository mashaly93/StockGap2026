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

class _HomescreenState extends State<Homescreen>
    with SingleTickerProviderStateMixin {
  final codeController = TextEditingController();
  final passwordController = TextEditingController();

  final FocusNode codeFocusNode = FocusNode();
  final FocusNode passwordFocusNode = FocusNode();

  bool isLoading = false;
  bool isCheckingLogin = false;
  bool obscurePassword = true;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  static const Color primaryColor = Color(0xff0050c0);

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animationController.forward();
      checkLogin();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();

    codeController.dispose();
    passwordController.dispose();

    codeFocusNode.dispose();
    passwordFocusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f7fb),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 60,
                ),
                child: Center(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: _buildLoginCard(),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ================================================================
  // LOGIN CARD
  // ================================================================

  Widget _buildLoginCard() {
    return Container(
      width: 430,
      constraints: const BoxConstraints(maxWidth: 430),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 35,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLogo(),

          const SizedBox(height: 12),

          const Text(
            "Stock Gap Generator",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: Color(0xff172033),
            ),
          ),

          const SizedBox(height: 6),

          Text(
            "Sign in to continue",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 26),

          _buildUsernameField(),

          const SizedBox(height: 14),

          _buildPasswordField(),

          const SizedBox(height: 22),

          _buildLoginButton(),
        ],
      ),
    );
  }

  // ================================================================
  // LOGO
  // ================================================================

  Widget _buildLogo() {
    return Container(
      width: 110,
      height: 110,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xfff1f6ff),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Image.asset('assets/images/back.png', fit: BoxFit.contain),
    );
  }

  // ================================================================
  // USERNAME
  // ================================================================

  Widget _buildUsernameField() {
    return TextFormField(
      controller: codeController,
      focusNode: codeFocusNode,
      textInputAction: TextInputAction.next,
      onFieldSubmitted: (_) {
        passwordFocusNode.requestFocus();
      },
      decoration: _inputDecoration(
        label: 'Pharmacy / Store Code',
        hint: 'Enter your code',
        icon: Icons.store_outlined,
      ),
    );
  }

  // ================================================================
  // PASSWORD
  // ================================================================

  Widget _buildPasswordField() {
    return TextFormField(
      controller: passwordController,
      focusNode: passwordFocusNode,
      obscureText: obscurePassword,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) async {
        if (!isLoading) {
          await login();
        }
      },
      decoration: _inputDecoration(
        label: 'Password',
        hint: 'Enter your password',
        icon: Icons.lock_outline,
        suffixIcon: IconButton(
          tooltip: obscurePassword ? 'Show password' : 'Hide password',
          splashRadius: 22,
          icon: Icon(
            obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: Colors.grey.shade500,
            size: 21,
          ),
          onPressed: () {
            setState(() {
              obscurePassword = !obscurePassword;
            });
          },
        ),
      ),
    );
  }

  // ================================================================
  // INPUT DECORATION
  // ================================================================

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 21),
      suffixIcon: suffixIcon,

      floatingLabelBehavior: FloatingLabelBehavior.auto,

      filled: true,
      fillColor: const Color(0xfff8faff),

      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),

      labelStyle: TextStyle(
        color: Colors.grey.shade600,
        fontWeight: FontWeight.w500,
      ),

      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),

      prefixIconColor: Colors.grey.shade500,

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: primaryColor, width: 1.5),
      ),
    );
  }

  // ================================================================
  // LOGIN BUTTON
  // ================================================================

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          boxShadow: isLoading
              ? []
              : [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.22),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ],
        ),
        child: ElevatedButton(
          onPressed: isLoading
              ? null
              : () async {
                  await login();
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            disabledBackgroundColor: primaryColor.withOpacity(0.75),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: isLoading
                ? const SizedBox(
                    key: ValueKey("loading"),
                    width: 21,
                    height: 21,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.3,
                    ),
                  )
                : const Row(
                    key: ValueKey("login"),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Login",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 9),
                      Icon(Icons.arrow_forward_rounded, size: 19),
                    ],
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

    FocusScope.of(context).unfocus();

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

        _showMessage("Enter username and password", isError: true);

        return;
      }

      final firestore = FirebaseFirestore.instance;

      QuerySnapshot<Map<String, dynamic>> result;

      // ============================================================
      // 1. SEARCH USERS
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

        _showMessage("User not found", isError: true);

        return;
      }

      // ============================================================
      // DOCUMENT
      // ============================================================

      final doc = result.docs.first;

      final data = doc.data();

      final docRef = doc.reference;

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

        _showMessage("Wrong password", isError: true);

        return;
      }

      // ============================================================
      // ACTIVE
      // ============================================================

      if (!isStore && data["active"] != true) {
        _stopLoading();

        _showMessage("Account disabled", isError: true);

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

        _showMessage("Subscription expired", isError: true);

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

          _showMessage("Too many devices logged in", isError: true);

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
          _buildPageRoute(
            StoreInventoryScreen(
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
        _buildPageRoute(
          MainMenuScreen(
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

      _showMessage(e.toString(), isError: true);
    }
  }

  // ================================================================
  // MODERN PAGE TRANSITION
  // ================================================================

  PageRouteBuilder _buildPageRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) {
        return page;
      },
      transitionDuration: const Duration(milliseconds: 500),
      reverseTransitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);

        final slide =
            Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: slide, child: child),
        );
      },
    );
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
  // MODERN SNACKBAR
  // ================================================================

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        elevation: 0,
        backgroundColor: Colors.transparent,
        duration: const Duration(seconds: 3),
        padding: EdgeInsets.zero,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: isError ? const Color(0xff20242b) : const Color(0xff173d2b),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isError
                      ? Colors.red.withOpacity(0.15)
                      : Colors.green.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  color: isError ? Colors.red.shade300 : Colors.green.shade300,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'Homescreen.dart';
import 'OrderScreen.dart';
import 'drug_search_screen.dart';
import 'import_drug_screen.dart';

class MainMenuScreen extends StatefulWidget {
  final String storeCode;
  final Timestamp? expireDate;
  final String role;

  const MainMenuScreen({
    super.key,
    required this.storeCode,
    required this.expireDate,
    required this.role,
  });

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen>
    with SingleTickerProviderStateMixin {
  // ================================================================
  // OMAN COLORS
  // ================================================================

  static const Color omanRed = Color(0xffC8102E);
  static const Color omanGreen = Color(0xff009A44);
  static const Color omanWhite = Colors.white;

  static const Color backgroundColor = Color(0xfff5f7f8);
  static const Color textColor = Color(0xff172033);

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _animationController.forward();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // ================================================================
  // LOGOUT
  // ================================================================

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('username');

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      _buildPageRoute(const Homescreen()),
      (route) => false,
    );
  }

  // ================================================================
  // PAGE TRANSITION
  // ================================================================

  PageRouteBuilder _buildPageRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) {
        return page;
      },
      transitionDuration: const Duration(milliseconds: 450),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fadeAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );

        final slideAnimation =
            Tween<Offset>(
              begin: const Offset(0.035, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );

        return FadeTransition(
          opacity: fadeAnimation,
          child: SlideTransition(position: slideAnimation, child: child),
        );
      },
    );
  }

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(BuildContext context) {
    final isStore = widget.role == "store";

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildBody(isStore)),
          ],
        ),
      ),
    );
  }

  // ================================================================
  // TOP BAR
  // ================================================================

  Widget _buildTopBar() {
    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ==========================================================
          // OMAN FLAG STRIPE
          // ==========================================================



          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Row(
                children: [
                  // ==================================================
                  // LOGO
                  // ==================================================

                  Container(
                    width: 44,
                    height: 44,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xfffff3f4),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: omanRed.withOpacity(0.10)),
                    ),
                    child: Image.asset(
                      'assets/images/back.jpeg',
                      fit: BoxFit.contain,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // ==================================================
                  // BRAND
                  // ==================================================
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Full Stock",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                          letterSpacing: -0.4,
                        ),
                      ),

                      const SizedBox(height: 1),

                      Row(
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: omanRed,
                              shape: BoxShape.circle,
                            ),
                          ),

                          const SizedBox(width: 4),

                          const Text(
                            "OMAN",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: omanGreen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const Spacer(),

                  // ==================================================
                  // USER INFO
                  // ==================================================
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xfff8faf9),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: omanGreen.withOpacity(0.10)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: omanGreen.withOpacity(0.10),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.store_outlined,
                            color: omanGreen,
                            size: 17,
                          ),
                        ),

                        const SizedBox(width: 8),

                        Text(
                          widget.storeCode,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xff3c4658),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // ==================================================
                  // LOGOUT
                  // ==================================================
                  Tooltip(
                    message: "Logout",
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: logout,
                        child: Container(
                          width: 43,
                          height: 43,
                          decoration: BoxDecoration(
                            color: const Color(0xfffff3f4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: omanRed.withOpacity(0.08),
                            ),
                          ),
                          child: const Icon(
                            Icons.logout_rounded,
                            color: omanRed,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // BODY
  // ================================================================

  Widget _buildBody(bool isStore) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 35),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeSection(isStore),

              const SizedBox(height: 28),

              _buildMenuGrid(isStore),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // WELCOME
  // ================================================================

  Widget _buildWelcomeSection(bool isStore) {
    final title = isStore ? "Warehouse Dashboard" : "Pharmacy Dashboard";

    final subtitle = isStore
        ? "Manage your warehouse inventory and stock."
        : "Manage orders and search for drug information.";

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ========================================================
            // SMALL OMAN LINE
            // ========================================================

            Row(
              children: [
                Container(
                  width: 24,
                  height: 4,
                  decoration: BoxDecoration(
                    color: omanRed,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),

                const SizedBox(width: 4),

                Container(
                  width: 24,
                  height: 4,
                  decoration: BoxDecoration(
                    color: omanWhite,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                ),

                const SizedBox(width: 4),

                Container(
                  width: 24,
                  height: 4,
                  decoration: BoxDecoration(
                    color: omanGreen,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Text(
              title,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: textColor,
                letterSpacing: -0.7,
              ),
            ),

            const SizedBox(height: 7),

            Text(
              subtitle,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================================================================
  // MENU GRID
  // ================================================================

  Widget _buildMenuGrid(bool isStore) {
    final cards = <Widget>[];

    // ==============================================================
    // PHARMACY
    // ==============================================================

    if (!isStore) {
      // ------------------------------------------------------------
      // GENERATE ORDER
      // ------------------------------------------------------------

      cards.add(
        MenuCard(
          title: "Generate Order",
          description: "Create pharmacy order Excel file",
          icon: Icons.inventory_2_outlined,
          color: omanRed,
          index: 0,
          animation: _animationController,
          onTap: () {
            Navigator.push(
              context,
              _buildPageRoute(
                OrderScreen(
                  storeCode: widget.storeCode,
                  expireDate: widget.expireDate,
                ),
              ),
            );
          },
        ),
      );

      // ------------------------------------------------------------
      // DRUG EYE
      // ------------------------------------------------------------

      cards.add(
        MenuCard(
          title: "Drug Eye",
          description: "Search drug information",
          icon: Icons.medication_outlined,
          color: omanGreen,
          index: 1,
          animation: _animationController,
          onTap: () {
            Navigator.push(context, _buildPageRoute(const DrugSearchScreen()));
          },
        ),
      );

      // ------------------------------------------------------------
      // MINISTRY OF HEALTH LIST
      // ------------------------------------------------------------

      // cards.add(
      //   MenuCard(
      //     title: "Ministry List",
      //     description: "Upload Ministry of Health drug list",
      //     icon: Icons.upload_file_rounded,
      //     color: const Color(0xff7b61ff),
      //     index: 2,
      //     animation: _animationController,
      //     onTap: () {
      //       Navigator.push(
      //         context,
      //         _buildPageRoute(
      //           const ImportDrugScreen(),
      //         ),
      //       );
      //     },
      //   ),
      // );
    }

    // ==============================================================
    // STORE
    // ==============================================================

    if (isStore) {
      cards.add(
        MenuCard(
          title: "Inventory",
          description: "Manage warehouse stock",
          icon: Icons.warehouse_outlined,
          color: omanGreen,
          index: 0,
          animation: _animationController,
          onTap: () {
            _showModernMessage("Inventory screen coming soon");
          },
        ),
      );
    }

    return Wrap(spacing: 20, runSpacing: 20, children: cards);
  }

  // ================================================================
  // MODERN MESSAGE
  // ================================================================

  void _showModernMessage(String message) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        padding: EdgeInsets.zero,
        duration: const Duration(seconds: 3),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xff20242b),
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
                  color: omanGreen.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.white70,
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
}

// ====================================================================
// MENU CARD
// ====================================================================

class MenuCard extends StatefulWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final int index;
  final Animation<double> animation;

  const MenuCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.index,
    required this.animation,
  });

  @override
  State<MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<MenuCard> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    final start = 0.15 + (widget.index * 0.12);

    final safeStart = start.clamp(0.0, 0.75).toDouble();

    final cardAnimation = CurvedAnimation(
      parent: widget.animation,
      curve: Interval(safeStart, 1.0, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: cardAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(cardAnimation),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,

          onEnter: (_) {
            if (!mounted) return;

            setState(() {
              isHovered = true;
            });
          },

          onExit: (_) {
            if (!mounted) return;

            setState(() {
              isHovered = false;
            });
          },

          child: GestureDetector(
            onTap: widget.onTap,

            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,

              width: 300,
              height: 150,

              transform: Matrix4.translationValues(0, isHovered ? -4 : 0, 0),

              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),

                border: Border.all(
                  color: isHovered
                      ? widget.color.withOpacity(0.22)
                      : Colors.grey.shade200,
                ),

                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isHovered ? 0.10 : 0.045),
                    blurRadius: isHovered ? 22 : 12,
                    offset: Offset(0, isHovered ? 10 : 5),
                  ),
                ],
              ),

              padding: const EdgeInsets.all(20),

              child: Row(
                children: [
                  // ==================================================
                  // ICON
                  // ==================================================

                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),

                    width: 58,
                    height: 58,

                    decoration: BoxDecoration(
                      color: widget.color.withOpacity(isHovered ? 0.15 : 0.09),
                      borderRadius: BorderRadius.circular(17),
                    ),

                    child: Icon(widget.icon, size: 29, color: widget.color),
                  ),

                  const SizedBox(width: 16),

                  // ==================================================
                  // TEXT
                  // ==================================================
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,

                          ),
                        ),

                        const SizedBox(height: 6),

                        Text(
                          widget.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // ==================================================
                  // ARROW
                  // ==================================================
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),

                    width: 32,
                    height: 32,

                    decoration: BoxDecoration(
                      color: isHovered
                          ? widget.color.withOpacity(0.10)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),

                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 13,
                      color: isHovered ? widget.color : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

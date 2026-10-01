import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'Homescreen.dart';
import 'OrderScreen.dart';
import 'drug_search_screen.dart';
import 'import_drug_screen.dart';
import 'warehouse_items_screen.dart';

class MainMenuScreen extends StatefulWidget {
  final String storeCode;
  final Timestamp? expireDate;
  final String role;
  final String username;

  const MainMenuScreen({
    super.key,
    required this.storeCode,
    required this.expireDate,
    required this.role,
    required this.username,
  });

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen>
    with SingleTickerProviderStateMixin {
  static const Color omanRed = Color(0xffC8102E);
  static const Color omanGreen = Color(0xff009A44);
  static const Color omanWhite = Colors.white;
  static const Color textDark = Color(0xff202124);
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

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
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

  // ============================================================
  // EXPIRE DATE
  // ============================================================

  String _formatExpireDate() {
    final date = widget.expireDate?.toDate();

    if (date == null) {
      return "No expiry date";
    }

    return "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.year}";
  }

  int? _remainingDays() {
    final date = widget.expireDate?.toDate();

    if (date == null) {
      return null;
    }

    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final expiry = DateTime(
      date.year,
      date.month,
      date.day,
    );

    return expiry.difference(today).inDays;
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();

    // Clear login session
    await prefs.remove('isLoggedIn');
    await prefs.remove('username');
    await prefs.remove('role');
    await prefs.remove('storeCode');

    // IMPORTANT:
    // Do NOT remove deviceId.
    // It must remain fixed for the maxDevices system.

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      _buildPageRoute(const Homescreen()),
          (route) => false,
    );
  }

  // ============================================================
  // PAGE TRANSITION
  // ============================================================

  PageRouteBuilder _buildPageRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (
          context,
          animation,
          secondaryAnimation,
          ) =>
      page,
      transitionDuration: const Duration(milliseconds: 450),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (
          context,
          animation,
          secondaryAnimation,
          child,
          ) {
        final fadeAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );

        final slideAnimation = Tween<Offset>(
          begin: const Offset(0.035, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
        );

        return FadeTransition(
          opacity: fadeAnimation,
          child: SlideTransition(
            position: slideAnimation,
            child: child,
          ),
        );
      },
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isStore = widget.role == "store";

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),

            // ==================================================
            // EXPIRE DATE تحت الـ TOP BAR
            // ==================================================

            _buildExpireDateBar(),

            Expanded(
              child: _buildBody(isStore),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TOP BAR
  // ============================================================

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
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xfffff3f4),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: omanRed.withOpacity(0.10),
                      ),
                    ),
                    child: Image.asset(
                      'assets/images/back.jpeg',
                      fit: BoxFit.contain,
                    ),
                  ),

                  const SizedBox(width: 12),

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

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xfff8faf9),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: omanGreen.withOpacity(0.10),
                      ),
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
                          widget.username,
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

  // ============================================================
  // EXPIRE DATE BAR
  // ============================================================

  Widget _buildExpireDateBar() {
    final days = _remainingDays();

    final bool isExpired = days != null && days < 0;
    final bool isExpiringSoon = days != null && days >= 0 && days <= 7;

    Color borderColor;

    if (isExpired) {
      borderColor = omanRed.withOpacity(0.25);
    } else if (isExpiringSoon) {
      borderColor = Colors.orange.withOpacity(0.30);
    } else {
      borderColor = omanGreen.withOpacity(0.15);
    }

    Color iconBackground;

    if (isExpired) {
      iconBackground = omanRed.withOpacity(0.10);
    } else if (isExpiringSoon) {
      iconBackground = Colors.orange.withOpacity(0.10);
    } else {
      iconBackground = omanGreen.withOpacity(0.10);
    }

    Color iconColor;

    if (isExpired) {
      iconColor = omanRed;
    } else if (isExpiringSoon) {
      iconColor = Colors.orange.shade700;
    } else {
      iconColor = omanGreen;
    }

    String statusText;

    if (days == null) {
      statusText = "Expire Date: No expiry date";
    } else if (days < 0) {
      statusText = "Subscription expired • ${_formatExpireDate()}";
    } else if (days == 0) {
      statusText = "Expires today • ${_formatExpireDate()}";
    } else {
      statusText =
      "Expire Date: ${_formatExpireDate()} • $days days remaining";
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(30, 14, 30, 0),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.event_outlined,
              color: iconColor,
              size: 18,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isExpired
                    ? omanRed
                    : isExpiringSoon
                    ? Colors.orange.shade800
                    : const Color(0xff3c4658),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BODY
  // ============================================================

  Widget _buildBody(bool isStore) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: 30,
        vertical: 35,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1000,
          ),
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

  // ============================================================
  // WELCOME
  // ============================================================

  Widget _buildWelcomeSection(bool isStore) {
    final title = isStore
        ? "Warehouse Dashboard"
        : "Pharmacy Dashboard";

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
                    border: Border.all(
                      color: Colors.grey.shade300,
                    ),
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

  // ============================================================
  // MENU GRID
  // ============================================================

  Widget _buildMenuGrid(bool isStore) {
    if (isStore) {
      return Wrap(
        spacing: 18,
        runSpacing: 18,
        children: [
          MenuCard(
            icon: Icons.inventory_2_outlined,
            title: "Inventory",
            subtitle: "Manage warehouse inventory",
            color: omanGreen,
            onTap: () {
              _showModernMessage(
                "Inventory screen coming soon",
              );
            },
          ),
        ],
      );
    }

    return Wrap(
      spacing: 18,
      runSpacing: 18,
      children: [
        MenuCard(
          icon: Icons.receipt_long_outlined,
          title: "Generate Order",
          subtitle: "Create a new pharmacy order",
          color: omanGreen,
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

        MenuCard(
          icon: Icons.search_rounded,
          title: "Drug Eye",
          subtitle: "Search drug information",
          color: omanRed,
          onTap: () {
            Navigator.push(
              context,
              _buildPageRoute(
                const DrugSearchScreen(),
              ),
            );
          },
        ),

        MenuCard(
          icon: Icons.inventory_2_outlined,
          title: "Warehouse Items",
          subtitle: "View warehouse stock",
          color: const Color(0xff00897B),
          onTap: () {
            Navigator.push(
              context,
              _buildPageRoute(
                WarehouseItemsScreen(
                  pharmacyCode: widget.storeCode,
                ),
              ),
            );
          },
        ),

        if (false) ...[
          MenuCard(
            icon: Icons.price_change_outlined,
            title: "Update Prices",
            subtitle: "Update medicine prices",
            color: const Color(0xff8E44AD),
            onTap: () {
              Navigator.push(
                context,
                _buildPageRoute(
                  const ImportDrugScreen(),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showModernMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          backgroundColor: Colors.transparent,
          duration: const Duration(seconds: 2),
          padding: EdgeInsets.zero,
          margin: const EdgeInsets.fromLTRB(
            24,
            0,
            24,
            24,
          ),
          content: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 13,
            ),
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
                    color: omanGreen,
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

// ================================================================
// MENU CARD
// ================================================================

class MenuCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const MenuCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  State<MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<MenuCard> {
  bool isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() {
          isHovering = true;
        });
      },
      onExit: (_) {
        setState(() {
          isHovering = false;
        });
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 300,
          height: 150,
          transform: Matrix4.identity()
            ..translate(
              0.0,
              isHovering ? -4.0 : 0.0,
            ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.color.withOpacity(
                isHovering ? 0.22 : 0.10,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(
                  isHovering ? 0.12 : 0.055,
                ),
                blurRadius: isHovering ? 22 : 14,
                offset: Offset(
                  0,
                  isHovering ? 10 : 6,
                ),
              ),
            ],
          ),
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  widget.icon,
                  color: widget.color,
                  size: 25,
                ),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xff172033),
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      widget.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: widget.color.withOpacity(0.65),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';

class AppColors {
  // Primary - Maroon
  static const Color primary = Color(0xFF800020);
  static const Color primaryDark = Color(0xFF5C0015);
  static const Color primaryLight = Color(0xFFAD1A45);

  // Secondary - Gold
  static const Color gold = Color(0xFFD4AF37);
  static const Color goldLight = Color(0xFFFFD700);
  static const Color goldDark = Color(0xFFB8960C);

  // Neutral
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color background = Color(0xFFFFF8F0);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color scaffoldBg = Color(0xFFFAF3EA);

  // Dark Mode
  static const Color darkBackground = Color(0xFF1A0A0E);
  static const Color darkSurface = Color(0xFF2D1218);
  static const Color darkCard = Color(0xFF3D1A22);

  // Text
  static const Color textPrimary = Color(0xFF1A0A0E);
  static const Color textSecondary = Color(0xFF6B4A52);
  static const Color textHint = Color(0xFFAA8890);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnGold = Color(0xFF1A0A0E);

  // Status
  static const Color success = Color(0xFF2E7D32);
  static const Color error = Color(0xFFD32F2F);
  static const Color warning = Color(0xFFF57C00);
  static const Color info = Color(0xFF1565C0);

  // Report Alert Levels
  static const Color alertNormal = Color(0xFF2E7D32);
  static const Color alertWarning = Color(0xFFF57C00);
  static const Color alertHigh = Color(0xFFE65100);
  static const Color alertCritical = Color(0xFFD32F2F);

  // Subscription
  static const Color basicPlan = Color(0xFF546E7A);
  static const Color mediumPlan = Color(0xFF800020);
  static const Color premiumPlan = Color(0xFFD4AF37);

  // Divider & Border
  static const Color divider = Color(0xFFE8D5D8);
  static const Color border = Color(0xFFD4B8BC);
  static const Color borderFocus = Color(0xFF800020);

  // Shadow
  static const Color shadow = Color(0x1A800020);
  static const Color shadowGold = Color(0x33D4AF37);

  // Gradient
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF800020), Color(0xFF5C0015)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFD700), Color(0xFFD4AF37)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient premiumGradient = LinearGradient(
    colors: [Color(0xFF800020), Color(0xFFD4AF37)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient splashGradient = LinearGradient(
    colors: [Color(0xFF5C0015), Color(0xFF800020), Color(0xFFAD1A45)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

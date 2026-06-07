import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Colour tokens (mirrors Android theme exactly) ──────────────────────────
const Color ecoDark = Color(0xFF0A0F0A);
const Color ecoSurface = Color(0xFF111811);
const Color ecoCard = Color(0xFF161F16);
const Color ecoGreen = Color(0xFF10B981);
const Color ecoLeaf = Color(0xFF34D399);
const Color ecoMuted = Color(0xFF6B7280);
const Color ecoBorder = Color(0xFF1F2E1F);
const Color ecoError = Color(0xFFEF4444);
const Color ecoGreenLight = Color(0xFF6EE7B7);

// ── Gradients ───────────────────────────────────────────────────────────────
const LinearGradient ecoGreenGradient = LinearGradient(
  colors: [ecoGreen, ecoLeaf],
);

LinearGradient ecoHeaderGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [ecoGreen.withValues(alpha: 0.25), ecoDark],
);

// ── Theme ───────────────────────────────────────────────────────────────────
ThemeData buildEcoTheme() {
  final base = ThemeData.dark();
  return base.copyWith(
    scaffoldBackgroundColor: ecoDark,
    colorScheme: const ColorScheme.dark(
      primary: ecoGreen,
      secondary: ecoLeaf,
      surface: ecoSurface,
      error: ecoError,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: ecoDark,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ecoCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: ecoBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: ecoBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: ecoGreen, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: ecoError),
      ),
      labelStyle: const TextStyle(color: ecoMuted),
      hintStyle: const TextStyle(color: ecoMuted),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: ecoCard,
      labelStyle: const TextStyle(color: ecoMuted),
      side: const BorderSide(color: ecoBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: ecoGreen),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ecoSurface,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

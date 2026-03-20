import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {

  static const Color primary     = Color(0xFF1D4ED8);
  static const Color primaryDark = Color(0xFF1E40AF);

  static const Color cta         = Color(0xFFF97316);

  static const Color secondary   = Color(0xFFF97316);

  static const Color ctbRed      = Color(0xFFC62828);
  static const Color privateBlue = Color(0xFF1565C0);

  static const Color liveGreen    = Color(0xFF16A34A);
  static const Color delayedAmber = Color(0xFFD97706);
  static const Color accent       = Color(0xFF16A34A);
  static const Color error        = Color(0xFFEF4444);

  static const Color backgroundLight    = Color(0xFFF1F5F9);
  static const Color surfaceLight       = Color(0xFFFFFFFF);
  static const Color textPrimaryLight   = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF64748B);
  static const Color dividerLight       = Color(0xFFE2E8F0);

  static const Color backgroundDark    = Color(0xFF020617);
  static const Color surfaceDark       = Color(0xFF0F172A);
  static const Color surfaceVariantDark= Color(0xFF1E293B);
  static const Color textPrimaryDark   = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color dividerDark       = Color(0xFF334155);
}

class AppSpacing {
  static const double xs   = 4;
  static const double sm   = 8;
  static const double md   = 16;
  static const double lg   = 24;
  static const double xl   = 32;
  static const double xxl  = 48;
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.backgroundLight,
      cardColor: AppColors.surfaceLight,
      dividerColor: AppColors.dividerLight,

      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.secondary,
        onSecondary: Colors.white,
        surface: AppColors.surfaceLight,
        onSurface: AppColors.textPrimaryLight,
        onSurfaceVariant: AppColors.textSecondaryLight,
        surfaceContainerHighest: Color(0xFFE2E8F0),
        error: AppColors.error,
        outline: AppColors.dividerLight,
      ),

      textTheme: _buildTextTheme(
        displayColor: AppColors.textPrimaryLight,
        bodyColor: AppColors.textPrimaryLight,
        secondaryColor: AppColors.textSecondaryLight,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimaryLight,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimaryLight, size: 24),
      ),

      elevatedButtonTheme: _buildButtonTheme(AppColors.primary, Colors.white),
      outlinedButtonTheme: _buildOutlinedButtonTheme(AppColors.primary),
      inputDecorationTheme: _buildInputTheme(AppColors.textSecondaryLight, AppColors.primary),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      cardColor: AppColors.surfaceDark,
      dividerColor: AppColors.dividerDark,

      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF60A5FA),
        onPrimary: Color(0xFF020617),
        secondary: Color(0xFFFBBF24),
        onSecondary: Color(0xFF020617),
        surface: AppColors.surfaceDark,
        onSurface: AppColors.textPrimaryDark,
        onSurfaceVariant: AppColors.textSecondaryDark,
        surfaceContainerHighest: AppColors.surfaceVariantDark,
        error: AppColors.error,
        outline: AppColors.dividerDark,
      ),

      textTheme: _buildTextTheme(
        displayColor: AppColors.textPrimaryDark,
        bodyColor: AppColors.textPrimaryDark,
        secondaryColor: AppColors.textSecondaryDark,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.backgroundDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimaryDark,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimaryDark, size: 24),
      ),

      elevatedButtonTheme: _buildButtonTheme(const Color(0xFF60A5FA), const Color(0xFF020617)),
      outlinedButtonTheme: _buildOutlinedButtonTheme(const Color(0xFF60A5FA)),
      inputDecorationTheme: _buildInputTheme(AppColors.textSecondaryDark, const Color(0xFF60A5FA)),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }

  static TextTheme _buildTextTheme({
    required Color displayColor,
    required Color bodyColor,
    required Color secondaryColor,
  }) {
    return TextTheme(
      displayLarge: GoogleFonts.outfit(
        fontSize: 32, fontWeight: FontWeight.w900, color: displayColor, letterSpacing: -1,
      ),
      displayMedium: GoogleFonts.outfit(
        fontSize: 28, fontWeight: FontWeight.w800, color: displayColor, letterSpacing: -0.5,
      ),
      titleLarge: GoogleFonts.outfit(
        fontSize: 20, fontWeight: FontWeight.w700, color: displayColor,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16, fontWeight: FontWeight.w600, color: bodyColor,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w500, color: bodyColor,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w500, color: secondaryColor,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w700, color: displayColor, letterSpacing: 0.5,
      ),
    );
  }

  static ElevatedButtonThemeData _buildButtonTheme(Color bg, Color fg) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
        textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }

  static OutlinedButtonThemeData _buildOutlinedButtonTheme(Color color) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color, width: 1.5),
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }

  static InputDecorationTheme _buildInputTheme(Color hintColor, Color focusColor) {
    return InputDecorationTheme(
      filled: true,
      fillColor: Colors.transparent,
      hintStyle: GoogleFonts.inter(color: hintColor, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: hintColor.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: hintColor.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: focusColor, width: 2),
      ),
    );
  }
}
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Inter is used when it is bundled (see README); otherwise the platform font is used.
const _fontFamily = 'Inter';
const _fallback = ['Roboto', '.SF Pro Text', 'Segoe UI', 'Helvetica Neue', 'Arial'];

/// Text styles from the Figma file (Text/title/large, Text/body, Text/label, Text/overline...).
/// Body text is never below 16 px; 13–14 px is only used for secondary captions/labels.
abstract final class AppText {
  static const titleLarge = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fallback,
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
  static const title = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fallback,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
  static const titleSmall = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fallback,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const body = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fallback,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );
  static const bodyStrong = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fallback,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const bodySecondary = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fallback,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );
  static const label = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fallback,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const caption = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fallback,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );
  static const overline = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fallback,

    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: AppColors.textSecondary,
  );
  static const code = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fallback,
    fontSize: 48,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: 4,
    color: AppColors.brand,
  );
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    primary: AppColors.brand,
    onPrimary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    error: AppColors.danger,
    brightness: Brightness.light,
  );

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
    borderSide: const BorderSide(color: AppColors.border),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bgApp,
    fontFamily: _fontFamily,
    fontFamilyFallback: _fallback,
    textTheme: const TextTheme(
      headlineMedium: AppText.titleLarge,
      titleLarge: AppText.title,
      titleMedium: AppText.titleSmall,
      bodyLarge: AppText.body,
      bodyMedium: AppText.body,
      labelLarge: AppText.label,
      bodySmall: AppText.caption,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgApp,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppText.titleSmall,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: 14),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.brand, width: 2)),
      errorBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.danger, width: 2)),
      focusedErrorBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.danger, width: 2)),
      hintStyle: AppText.bodySecondary,
      helperStyle: AppText.caption,
      errorStyle: AppText.caption.copyWith(color: AppColors.danger),
      labelStyle: AppText.label,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1, thickness: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.brand : const Color(0xFFCBD5E1),
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: AppText.label.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    ),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
  );
}

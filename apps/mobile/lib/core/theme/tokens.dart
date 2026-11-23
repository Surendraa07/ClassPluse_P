import 'package:flutter/material.dart';

/// Design tokens from the ClassPulse Figma file (variables `--color-*`, `--space-*`, `--radius-*`).
abstract final class AppColors {
  static const brand = Color(0xFF5B4CF0);
  static const brandPressed = Color(0xFF4A3BD6);
  static const brandTint = Color(0xFFEEEBFF);
  static const bgApp = Color(0xFFF8F9FC);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE6E8F0);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);

  static const success = Color(0xFF15803D); // text/icons on light bg (AA)
  static const successFill = Color(0xFF22C55E);
  static const successTint = Color(0xFFDCFCE7);

  static const danger = Color(0xFFB91C1C); // AA on white and on dangerTint
  static const dangerTint = Color(0xFFFEE2E2);
  static const dangerBorder = Color(0xFFF87171);

  static const accentCyan = Color(0xFF06B6D4);
  static const warningFill = Color(0xFFF97316);

  /// Result bar colours cycle per option (violet, cyan, orange, green), as in the design.
  static const resultBars = [brand, accentCyan, warningFill, successFill];

  static const skeleton = Color(0xFFE9EBF2);
}

abstract final class AppSpace {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const s24 = 24.0;
  static const s32 = 32.0;
  static const s40 = 40.0;
}

abstract final class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const full = 999.0;
}

abstract final class AppSizes {
  /// Minimum touch target (44 pt, WCAG / Apple HIG).
  static const minTouch = 44.0;
  static const buttonHeight = 52.0;
  static const answerOptionHeight = 64.0;
  static const fieldHeight = 52.0;
}

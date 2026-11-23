import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

enum SecondaryButtonTone { neutral, danger }

/// Outlined 52 pt button on a white surface. `danger` is the soft red "End" style.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = SecondaryButtonTone.neutral,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final SecondaryButtonTone tone;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final danger = tone == SecondaryButtonTone.danger;
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: danger ? AppColors.dangerTint : AppColors.surface,
        foregroundColor: danger ? AppColors.danger : AppColors.textPrimary,
        disabledForegroundColor: AppColors.textSecondary,
        side: BorderSide(color: danger ? AppColors.dangerTint : AppColors.border),
        minimumSize: const Size(AppSizes.minTouch, AppSizes.buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        textStyle: AppText.bodyStrong,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: AppSpace.s8)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

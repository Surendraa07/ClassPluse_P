import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

/// Full-width 52 pt primary action. Shows a spinner + [loadingLabel] while [loading].
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.loadingLabel,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final String? loadingLabel;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final text = loading ? (loadingLabel ?? label) : label;
    final button = FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        // Disabled look from the design: brand at reduced opacity, white text.
        disabledBackgroundColor: AppColors.brand.withValues(alpha: 0.5),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size(AppSizes.minTouch, AppSizes.buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        textStyle: AppText.bodyStrong,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) ...[
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            ),
            const SizedBox(width: AppSpace.s12),
          ] else if (icon != null) ...[
            Icon(icon, size: 20),
            const SizedBox(width: AppSpace.s8),
          ],
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

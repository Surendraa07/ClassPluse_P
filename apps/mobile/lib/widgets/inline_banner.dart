import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

enum BannerKind { error, offline, info, success }

/// Inline (non-modal) banner with icon, title, message and an optional text action ("Retry").
/// Announced politely to screen readers via a live region.
class InlineBanner extends StatelessWidget {
  const InlineBanner({
    super.key,
    required this.title,
    this.message,
    this.kind = BannerKind.error,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final BannerKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg, icon) = switch (kind) {
      BannerKind.error => (AppColors.dangerTint, AppColors.dangerBorder, AppColors.danger, Icons.error_outline_rounded),
      BannerKind.offline => (AppColors.dangerTint, AppColors.dangerBorder, AppColors.danger, Icons.wifi_off_rounded),
      BannerKind.info => (AppColors.brandTint, AppColors.brand.withValues(alpha: 0.4), AppColors.brand, Icons.info_outline_rounded),
      BannerKind.success => (AppColors.successTint, AppColors.success.withValues(alpha: 0.4), AppColors.success, Icons.check_circle_outline_rounded),
    };

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.s16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(width: AppSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.bodyStrong),
                  if (message != null) ...[
                    const SizedBox(height: 2),
                    Text(message!, style: AppText.label.copyWith(fontWeight: FontWeight.w500)),
                  ],
                  if (actionLabel != null && onAction != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: onAction,
                        style: TextButton.styleFrom(
                          foregroundColor: fg,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(AppSizes.minTouch, AppSizes.minTouch),
                          tapTargetSize: MaterialTapTargetSize.padded,
                          textStyle: AppText.label,
                        ),
                        child: Text(actionLabel!),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

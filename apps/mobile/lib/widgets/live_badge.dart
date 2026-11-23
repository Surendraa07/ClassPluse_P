import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

/// Green "● Live" pill. Always includes the word "Live", so colour is not the only signal.
/// (The dot is static on purpose: no endless animation for reduced-motion users and tests.)
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, this.title, this.compact = false});

  /// Optional session title shown after "Live ·".
  final String? title;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = compact ? 'LIVE' : (title == null ? 'Live' : 'Live · $title');
    return Semantics(
      label: title == null ? 'Live session' : 'Live session: $title',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: 6),
        decoration: BoxDecoration(color: AppColors.successTint, borderRadius: BorderRadius.circular(AppRadius.full)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpace.s8),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(color: AppColors.success, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum StatusPillTone { success, brand, neutral }

/// Small rounded status pill, e.g. "● 12 students joined" or "18 answered".
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.tone = StatusPillTone.success, this.showDot = true});

  final String label;
  final StatusPillTone tone;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      StatusPillTone.success => (AppColors.successTint, AppColors.success),
      StatusPillTone.brand => (AppColors.brandTint, AppColors.brand),
      StatusPillTone.neutral => (AppColors.border, AppColors.textPrimary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(width: 8, height: 8, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: AppSpace.s8),
          ],
          Flexible(child: Text(label, style: AppText.label.copyWith(color: fg))),
        ],
      ),
    );
  }
}

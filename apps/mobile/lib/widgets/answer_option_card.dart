import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

/// Large (≥ 64 pt) single-choice option row. Selection is shown by a filled radio, a check icon,
/// a thicker border and tint, and is announced to screen readers — colour is never the only signal.
class AnswerOptionCard extends StatelessWidget {
  const AnswerOptionCard({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.index,
    this.total,
  });

  final String label;
  final bool selected;

  /// Null disables the card (e.g. after the question closed).
  final VoidCallback? onTap;
  final int? index;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final position = (index != null && total != null) ? 'Option ${index! + 1} of $total. ' : '';
    return Semantics(
      container: true,
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      enabled: enabled,
      label: '$position$label',
      onTap: onTap,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Material(
          color: selected ? AppColors.brandTint : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: selected ? AppColors.brand : AppColors.border, width: selected ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSizes.answerOptionHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s12),
                child: Row(
                  children: [
                    _RadioDot(selected: selected),
                    const SizedBox(width: AppSpace.s12),
                    Expanded(child: Text(label, style: selected ? AppText.bodyStrong : AppText.body)),
                    if (selected) const Icon(Icons.check_rounded, color: AppColors.brand, size: 22),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? AppColors.brand : AppColors.textSecondary, width: 2),
      ),
      child: selected
          ? const DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.brand))
          : null,
    );
  }
}

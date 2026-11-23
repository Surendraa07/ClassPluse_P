import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

/// One answer's share: bold label, percentage (and optional count) as text, and a bar.
/// The numbers are always printed so the bar colour is never the only signal.
/// Use [large] on the lecturer dashboard so it stays readable when mirrored to a projector.
class ResultBar extends StatelessWidget {
  const ResultBar({
    super.key,
    required this.label,
    required this.percent,
    this.count,
    this.color = AppColors.brand,
    this.isCorrect = false,
    this.isMine = false,
    this.large = false,
  });

  final String label;

  /// 0–100.
  final double percent;
  final int? count;
  final Color color;
  final bool isCorrect;
  final bool isMine;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final pct = percent.clamp(0, 100).toDouble();
    final pctText = '${pct.round()}%';
    final labelStyle = (large ? AppText.titleSmall : AppText.bodyStrong);
    final pctStyle = labelStyle.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    final semantic = StringBuffer('$label: $pctText');
    if (count != null) semantic.write(', $count ${count == 1 ? 'response' : 'responses'}');
    if (isCorrect) semantic.write(', correct answer');
    if (isMine) semantic.write(', your answer');

    return Semantics(
      label: semantic.toString(),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isCorrect) ...[
                const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                const SizedBox(width: AppSpace.s4),
              ],
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: label,
                    children: [
                      if (count != null) TextSpan(text: ' · $count', style: labelStyle.copyWith(fontWeight: FontWeight.w500)),
                      if (isCorrect)
                        TextSpan(text: '  Correct', style: AppText.label.copyWith(color: AppColors.success)),
                      if (isMine) TextSpan(text: '  Your answer', style: AppText.label.copyWith(color: AppColors.brand)),
                    ],
                  ),
                  style: labelStyle,
                ),
              ),
              const SizedBox(width: AppSpace.s8),
              Text(pctText, style: pctStyle),
            ],
          ),
          const SizedBox(height: AppSpace.s8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: SizedBox(
              height: large ? 20 : 16,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFFEDEBFB)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: pct / 100,
                    child: ColoredBox(color: color),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

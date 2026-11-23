import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

enum PulseKind { following, lost }

/// Large "I'm following" / "I'm lost" toggle. The selected one is filled and shows a "Selected"
/// tag; the icon (check / cross) and the label differ too, so state never relies on colour alone.
class PulseButton extends StatelessWidget {
  const PulseButton({super.key, required this.kind, required this.selected, required this.onTap});

  final PulseKind kind;
  final bool selected;
  final VoidCallback? onTap;

  String get label => kind == PulseKind.following ? "I'm following" : "I'm lost";

  @override
  Widget build(BuildContext context) {
    final following = kind == PulseKind.following;
    final solid = following ? AppColors.success : AppColors.danger;
    final tint = following ? AppColors.successTint : AppColors.dangerTint;
    final fg = selected ? Colors.white : solid;

    return Semantics(
      container: true,
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      enabled: onTap != null,
      label: label,
      hint: selected ? null : (following ? 'Tell your teacher you understand' : 'Tell your teacher you are lost'),
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? solid : tint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: selected ? solid : solid.withValues(alpha: 0.45), width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 122),
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.s16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(following ? Icons.check_rounded : Icons.close_rounded, size: 36, color: fg),
                        const SizedBox(height: AppSpace.s8),
                        Text(label, style: AppText.title.copyWith(color: fg)),
                      ],
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    top: AppSpace.s12,
                    right: AppSpace.s12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text('Selected', style: AppText.label.copyWith(color: solid)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

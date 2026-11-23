import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';
import 'primary_button.dart';

/// Card with a tinted icon, title, explanation and an optional primary action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Icon(icon, color: AppColors.brand, size: 28),
              ),
            ),
            const SizedBox(height: AppSpace.s16),
            Text(title, style: AppText.titleSmall, textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.s8),
            Text(message, style: AppText.bodySecondary, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpace.s20),
              PrimaryButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

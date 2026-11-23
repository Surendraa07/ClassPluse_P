import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

/// Brand mark: rounded violet square with a bar-chart glyph.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) {
    // Align keeps the logo at its own size inside full-width list layouts.
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: Semantics(
        label: 'ClassPluse',
        image: true,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7C6CF6), AppColors.brand, Color(0xFF8B3FE0)],
            ),
          ),
          child: Icon(Icons.bar_chart_rounded, color: Colors.white, size: size * 0.6),
        ),
      ),
    );
  }
}

/// Uppercase overline section label, e.g. "SESSION CODE".
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: AppText.overline)),
          ?trailing,
        ],
      ),
    );
  }
}

/// White rounded card with border (the design's default surface).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpace.s16), this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Tappable list row: tinted icon tile, title, meta line, chevron. ≥ 64 pt tall.
class ListRowCard extends StatelessWidget {
  const ListRowCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.iconColor = AppColors.brand,
    this.iconBg = AppColors.brandTint,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color iconColor;
  final Color iconBg;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Icon(icon, color: iconColor, size: 22),
              ),
            ),
            const SizedBox(width: AppSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (subtitle != null) Text(subtitle!, style: AppText.caption),
                ],
              ),
            ),
            trailing ??
                (onTap != null
                    ? const ExcludeSemantics(child: Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary))
                    : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

/// Stat card: tinted icon, big number, caption ("24 Participants").
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor = AppColors.brand,
    this.iconBg = AppColors.brandTint,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color iconColor;
  final Color iconBg;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$value $label',
      excludeSemantics: true,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: AppSpace.s12),
            Text(value, style: AppText.titleLarge),
            Text(label, style: AppText.bodySecondary),
          ],
        ),
      ),
    );
  }
}

/// Screen header with a circular back/close button, title and subtitle (design "Top Bar").
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon = Icons.chevron_left_rounded,
    this.leadingLabel = 'Back',
    this.onLeading,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData leadingIcon;
  final String leadingLabel;
  final VoidCallback? onLeading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s8, AppSpace.s16, AppSpace.s8),
      child: Row(
        children: [
          if (onLeading != null) ...[
            Semantics(
              button: true,
              label: leadingLabel,
              excludeSemantics: true,
              child: Material(
                color: AppColors.surface,
                shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onLeading,
                  child: SizedBox.square(dimension: 44, child: Icon(leadingIcon, color: AppColors.textPrimary)),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.s12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: AppText.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

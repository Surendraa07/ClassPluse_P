import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// Grey placeholder block shown while content loads.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 16, this.radius = AppRadius.sm});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.skeleton, borderRadius: BorderRadius.circular(radius)),
    );
  }
}

/// A list of skeleton rows (icon square + two lines), announced once as "Loading".
class SkeletonLoader extends StatelessWidget {
  const SkeletonLoader({super.key, this.rows = 3, this.label = 'Loading', this.header = false});

  final int rows;
  final String label;

  /// Adds two stat-card blocks above the rows (dashboard / summary layout).
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header) ...[
            const Row(
              children: [
                Expanded(child: SkeletonBox(height: 110, radius: AppRadius.lg)),
                SizedBox(width: AppSpace.s12),
                Expanded(child: SkeletonBox(height: 110, radius: AppRadius.lg)),
              ],
            ),
            const SizedBox(height: AppSpace.s20),
          ],
          for (var i = 0; i < rows; i++) ...[
            Container(
              padding: const EdgeInsets.all(AppSpace.s12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                children: [
                  SkeletonBox(width: 40, height: 40, radius: AppRadius.md),
                  SizedBox(width: AppSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 160, height: 14),
                        SizedBox(height: AppSpace.s8),
                        SkeletonBox(width: 100, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.s12),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/primary_button.dart';

class SessionEndedScreen extends StatelessWidget {
  const SessionEndedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExcludeSemantics(
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: const BoxDecoration(color: AppColors.brandTint, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded, color: AppColors.brand, size: 48),
                        ),
                      ),
                      const SizedBox(height: AppSpace.s20),
                      Semantics(
                        header: true,
                        child: const Text('Thanks for joining', key: ValueKey('thanks'), style: AppText.titleLarge),
                      ),
                      const SizedBox(height: AppSpace.s8),
                      const Text(
                        'Your teacher ended the session. Your answers were anonymous and no account was created.',
                        textAlign: TextAlign.center,
                        style: AppText.bodySecondary,
                      ),
                    ],
                  ),
                ),
              ),
              PrimaryButton(
                key: const ValueKey('join-another'),
                label: 'Join another session',
                onPressed: () => context.go('/join'),
              ),
              TextButton(onPressed: () => context.go('/'), child: const Text('Back to start')),
            ],
          ),
        ),
      ),
    );
  }
}

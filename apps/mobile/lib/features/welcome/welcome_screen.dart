import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';

/// First screen: students join a session (no account); teachers go to login.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final returning = ref.watch(localStoreProvider).hasJoinedBefore;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6B5CF5), AppColors.brand, Color(0xFF4433C9)],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.s24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpace.s12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppRadius.xl),
                          ),
                          child: const AppLogo(size: 64),
                        ),
                        const SizedBox(height: AppSpace.s20),
                        Semantics(
                          header: true,
                          child: Text('ClassPluse', style: AppText.titleLarge.copyWith(color: Colors.white)),
                        ),
                        const SizedBox(height: AppSpace.s8),
                        Text(
                          'Answer live questions and tell your teacher how the lesson is going. No account needed.',
                          textAlign: TextAlign.center,
                          style: AppText.body.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s24, AppSpace.s16, AppSpace.s16),
              child: Column(
                children: [
                  PrimaryButton(
                    key: const ValueKey('welcome-join'),
                    label: returning ? 'Join another session' : 'Join a session',
                    icon: Icons.qr_code_2_rounded,
                    onPressed: () => context.push('/join'),
                  ),
                  const SizedBox(height: AppSpace.s12),
                  SecondaryButton(
                    key: const ValueKey('welcome-teacher'),
                    label: "I'm a teacher",
                    icon: Icons.school_outlined,
                    onPressed: () => context.push('/login'),
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

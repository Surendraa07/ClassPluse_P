import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/inline_banner.dart';
import '../../widgets/labeled_field.dart';
import '../../widgets/primary_button.dart';
import 'auth_controller.dart';
import 'validators.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _submitted = false;
  ApiException? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? get _emailError => _submitted ? validateEmail(_email.text) : null;
  String? get _passwordError => _submitted && _password.text.isEmpty ? 'Enter your password' : null;

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (_emailError != null || _passwordError != null) return;
    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).login(email: _email.text, password: _password.text);
      if (mounted) context.go('/lecturer');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expired = ref.watch(authControllerProvider).sessionExpired;
    final error = _error;
    return Scaffold(
      body: SafeArea(
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.all(AppSpace.s16),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
              ),
              const AppLogo(size: 40),
              const SizedBox(height: AppSpace.s16),
              Semantics(header: true, child: const Text('Welcome back', style: AppText.titleLarge)),
              const SizedBox(height: AppSpace.s4),
              const Text('Log in to build and run live sessions.', style: AppText.bodySecondary),
              const SizedBox(height: AppSpace.s20),
              if (error != null) ...[
                InlineBanner(
                  kind: error.isNetwork ? BannerKind.offline : BannerKind.error,
                  title: error.code == 'INVALID_CREDENTIALS' ? 'Incorrect email or password' : "Couldn't log in",
                  message: error.code == 'INVALID_CREDENTIALS' ? 'Check your details and try again.' : error.message,
                  actionLabel: 'Retry',
                  onAction: _loading ? null : _submit,
                ),
                const SizedBox(height: AppSpace.s16),
              ] else if (expired) ...[
                const InlineBanner(
                  kind: BannerKind.info,
                  title: 'You were logged out',
                  message: 'Your session expired. Please log in again.',
                ),
                const SizedBox(height: AppSpace.s16),
              ],
              LabeledField(
                fieldKey: const ValueKey('login-email'),
                label: 'Email',
                controller: _email,
                hint: 'name@university.edu',
                helper: 'Use your school or personal email',
                errorText: _emailError,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                enabled: !_loading,
                onChanged: (_) => _submitted ? setState(() {}) : null,
              ),
              const SizedBox(height: AppSpace.s16),
              PasswordField(
                fieldKey: const ValueKey('login-password'),
                controller: _password,
                helper: 'At least 8 characters',
                errorText: _passwordError,
                enabled: !_loading,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpace.s24),
              PrimaryButton(
                key: const ValueKey('login-submit'),
                label: 'Log in',
                loading: _loading,
                loadingLabel: 'Signing in…',
                onPressed: _submit,
              ),
              const SizedBox(height: AppSpace.s12),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : () => context.pushReplacement('/signup'),
                  child: const Text('New here? Create an account'),
                ),
              ),
              const SizedBox(height: AppSpace.s24),
              _StudentShortcut(onTap: () => context.go('/join')),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudentShortcut extends StatelessWidget {
  const _StudentShortcut({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandTint,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s16),
          child: Row(
            children: [
              const Icon(Icons.groups_outlined, color: AppColors.brand),
              const SizedBox(width: AppSpace.s12),
              Expanded(
                child: Text(
                  'Student? Join with a code, no account needed',
                  style: AppText.bodyStrong.copyWith(color: AppColors.brand),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.brand),
            ],
          ),
        ),
      ),
    );
  }
}

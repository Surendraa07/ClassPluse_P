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

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _submitted = false;
  ApiException? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _fieldError(String field, String? local) {
    if (!_submitted) return null;
    return local ?? _error?.fieldErrors[field];
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (validateName(_name.text) != null || validateEmail(_email.text) != null || validateNewPassword(_password.text) != null) {
      return;
    }
    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .register(name: _name.text, email: _email.text, password: _password.text);
      if (mounted) context.go('/lecturer');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final showBanner = error != null && error.fieldErrors.isEmpty;
    void revalidate(String _) => _submitted ? setState(() {}) : null;

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
              Semantics(header: true, child: const Text('Create your account', style: AppText.titleLarge)),
              const SizedBox(height: AppSpace.s4),
              const Text('Teachers only. Students never need an account.', style: AppText.bodySecondary),
              const SizedBox(height: AppSpace.s20),
              if (showBanner) ...[
                InlineBanner(
                  kind: error.isNetwork ? BannerKind.offline : BannerKind.error,
                  title: error.code == 'CONFLICT' ? 'This email is already registered' : "Couldn't create your account",
                  message: error.code == 'CONFLICT' ? 'Log in instead, or use another email.' : error.message,
                  actionLabel: error.code == 'CONFLICT' ? 'Log in' : 'Retry',
                  onAction: error.code == 'CONFLICT' ? () => context.pushReplacement('/login') : _submit,
                ),
                const SizedBox(height: AppSpace.s16),
              ],
              LabeledField(
                fieldKey: const ValueKey('signup-name'),
                label: 'Full name',
                controller: _name,
                hint: 'Suren Thapa',
                helper: 'Shown to you only',
                errorText: _fieldError('name', validateName(_name.text)),
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                enabled: !_loading,
                onChanged: revalidate,
              ),
              const SizedBox(height: AppSpace.s16),
              LabeledField(
                fieldKey: const ValueKey('signup-email'),
                label: 'Email',
                controller: _email,
                hint: 'name@university.edu',
                helper: 'Use your school or personal email',
                errorText: _fieldError('email', validateEmail(_email.text)),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                enabled: !_loading,
                onChanged: revalidate,
              ),
              const SizedBox(height: AppSpace.s16),
              PasswordField(
                fieldKey: const ValueKey('signup-password'),
                controller: _password,
                newPassword: true,
                helper: 'At least 8 characters',
                errorText: _fieldError('password', validateNewPassword(_password.text)),
                enabled: !_loading,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpace.s24),
              PrimaryButton(
                key: const ValueKey('signup-submit'),
                label: 'Create account',
                loading: _loading,
                loadingLabel: 'Creating account…',
                onPressed: _submit,
              ),
              const SizedBox(height: AppSpace.s12),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : () => context.pushReplacement('/login'),
                  child: const Text('Already have an account? Log in'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

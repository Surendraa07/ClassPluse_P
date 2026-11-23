import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/code_input.dart';
import '../../widgets/common.dart';
import '../../widgets/inline_banner.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import 'student_repository.dart';

/// Six digit boxes + on-screen keypad, or scan a QR code. No account.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, this.initialCode});

  /// From a deep link / QR scan: filled in and joined automatically.
  final String? initialCode;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  late final CodeInputController _code = CodeInputController(text: widget.initialCode ?? '');
  bool _joining = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(_onCodeChanged);
    if (_code.isComplete) WidgetsBinding.instance.addPostFrameCallback((_) => _join());
  }

  @override
  void dispose() {
    _code.removeListener(_onCodeChanged);
    _code.dispose();
    super.dispose();
  }

  void _onCodeChanged() => setState(() {}); // keeps the error banner until the user retries

  Future<void> _join() async {
    if (!_code.isComplete || _joining) return;
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      await ref.read(studentRepositoryProvider).join(_code.value);
      if (mounted) context.go('/student/session');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e); // digits are kept so one can be corrected
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _scan() async {
    final code = await context.push<String>('/join/scan');
    if (code == null || !mounted) return;
    _code.setCode(code);
    await _join();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final invalid = error != null && (error.code == 'SESSION_NOT_FOUND' || error.code == 'VALIDATION_ERROR');

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s8, AppSpace.s16, AppSpace.s16),
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      const Spacer(),
                    ],
                  ),
                  if (error == null) ...[const AppLogo(size: 44), const SizedBox(height: AppSpace.s16)],
                  Semantics(header: true, child: const Text('Join a live session', style: AppText.titleLarge)),
                  const SizedBox(height: AppSpace.s4),
                  const Text('Enter the 6-digit code from your teacher. No account needed.', style: AppText.bodySecondary),
                  const SizedBox(height: AppSpace.s16),
                  if (error != null) ...[
                    InlineBanner(
                      key: const ValueKey('join-error'),
                      kind: error.isNetwork ? BannerKind.offline : BannerKind.error,
                      title: invalid
                          ? "We couldn't find that session"
                          : error.code == 'RATE_LIMITED'
                              ? 'Too many attempts'
                              : "Couldn't join",
                      message: invalid ? 'Check the code with your teacher and try again.' : error.message,
                      actionLabel: 'Retry',
                      onAction: _code.isComplete && !_joining ? _join : null,
                    ),
                    const SizedBox(height: AppSpace.s16),
                  ],
                  const SectionLabel('Session code'),
                  const SizedBox(height: AppSpace.s12),
                  CodeInput(
                    key: const ValueKey('join-code'),
                    controller: _code,
                    hasError: invalid,
                    enabled: !_joining,
                    autofocus: true,
                  ),
                  const SizedBox(height: AppSpace.s16),
                  PrimaryButton(
                    key: const ValueKey('join-submit'),
                    label: 'Join session',
                    loading: _joining,
                    loadingLabel: 'Joining…',
                    onPressed: _code.isComplete ? _join : null,
                  ),
                  const SizedBox(height: AppSpace.s12),
                  SecondaryButton(
                    key: const ValueKey('join-scan'),
                    label: 'Scan QR code',
                    icon: Icons.qr_code_scanner_rounded,
                    onPressed: _joining ? null : _scan,
                  ),
                ],
              ),
            ),
            NumberKeypad(controller: _code, enabled: !_joining),
          ],
        ),
      ),
    );
  }
}

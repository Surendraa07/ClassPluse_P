import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

/// Holds the digits typed into a [CodeInput]. Shared with [NumberKeypad].
class CodeInputController extends ValueNotifier<String> {
  CodeInputController({String text = '', this.length = 6}) : super(_clean(text, length));

  final int length;

  static String _clean(String s, int length) {
    final digits = s.replaceAll(RegExp(r'\D'), '');
    return digits.length > length ? digits.substring(0, length) : digits;
  }

  bool get isComplete => value.length == length;

  void append(String digit) {
    if (isComplete || !RegExp(r'^\d$').hasMatch(digit)) return;
    value = value + digit;
  }

  void backspace() {
    if (value.isNotEmpty) value = value.substring(0, value.length - 1);
  }

  void clear() => value = '';

  /// Sets the whole code (paste / QR scan); non-digits are ignored.
  void setCode(String code) => value = _clean(code, length);
}

/// Six separate digit boxes (no system keyboard; pair with [NumberKeypad]). Physical keyboards
/// and paste (Ctrl/Cmd+V) also work when the field has focus.
class CodeInput extends StatefulWidget {
  const CodeInput({
    super.key,
    required this.controller,
    this.hasError = false,
    this.enabled = true,
    this.onCompleted,
    this.autofocus = false,
  });

  final CodeInputController controller;

  /// Red borders; digits are kept so a single digit can be corrected.
  final bool hasError;
  final bool enabled;
  final ValueChanged<String>? onCompleted;
  final bool autofocus;

  @override
  State<CodeInput> createState() => _CodeInputState();
}

class _CodeInputState extends State<CodeInput> {
  final _focus = FocusNode(debugLabel: 'CodeInput');
  String _last = '';

  @override
  void initState() {
    super.initState();
    _last = widget.controller.value;
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(CodeInput old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    final v = widget.controller.value;
    if (v.length == widget.controller.length && _last.length != v.length) {
      widget.onCompleted?.call(v);
    }
    _last = v;
    setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled || event is KeyUpEvent) return KeyEventResult.ignored;
    final c = widget.controller;
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      c.backspace();
      return KeyEventResult.handled;
    }
    final isPaste = event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed);
    if (isPaste) {
      Clipboard.getData(Clipboard.kTextPlain).then((d) {
        if (d?.text != null) c.setCode(d!.text!);
      });
      return KeyEventResult.handled;
    }
    final ch = event.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      c.append(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final code = c.value;
    final spoken = code.isEmpty ? 'empty' : code.split('').join(' ');
    return Semantics(
      label: 'Session code, ${code.length} of ${c.length} digits entered: $spoken',
      hint: widget.hasError ? 'Code not found. Check the digits and try again.' : null,
      textField: true,
      excludeSemantics: true,
      child: Focus(
        focusNode: _focus,
        autofocus: widget.autofocus,
        onKeyEvent: _onKey,
        child: GestureDetector(
          onTap: () => _focus.requestFocus(),
          child: Row(
            children: [
              for (var i = 0; i < c.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpace.s8),
                Expanded(child: _DigitBox(
                  key: ValueKey('code-digit-$i'),
                  digit: i < code.length ? code[i] : null,
                  active: widget.enabled && i == code.length,
                  hasError: widget.hasError,
                  dimmed: !widget.enabled,
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DigitBox extends StatelessWidget {
  const _DigitBox({super.key, required this.digit, required this.active, required this.hasError, required this.dimmed});

  final String? digit;
  final bool active;
  final bool hasError;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? AppColors.danger
        : active
            ? AppColors.brand
            : AppColors.border;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: borderColor, width: (hasError || active) ? 2 : 1),
      ),
      child: Text(
        digit ?? '',
        style: AppText.titleLarge.copyWith(color: dimmed ? AppColors.textSecondary : AppColors.textPrimary),
      ),
    );
  }
}

/// On-screen numeric keypad (1–9, 0, delete) from the design; avoids the system keyboard
/// covering the screen. Every key is ≥ 52 pt tall.
class NumberKeypad extends StatelessWidget {
  const NumberKeypad({super.key, required this.controller, this.enabled = true});

  final CodeInputController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget key(String d) => _Key(
          key: ValueKey('keypad-$d'),
          label: d,
          semanticLabel: d,
          onTap: enabled ? () => controller.append(d) : null,
          child: Text(d, style: AppText.titleLarge.copyWith(fontWeight: FontWeight.w500, fontSize: 24)),
        );
    final del = _Key(
      key: const ValueKey('keypad-delete'),
      label: 'delete',
      semanticLabel: 'Delete last digit',
      onTap: enabled ? controller.backspace : null,
      child: const Icon(Icons.backspace_outlined, color: AppColors.textPrimary),
    );

    return Container(
      color: const Color(0xFFEEF0F5),
      padding: const EdgeInsets.all(AppSpace.s8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.s8),
              child: Row(children: [for (final d in row) Expanded(child: key(d))]),
            ),
          Row(children: [const Expanded(child: SizedBox(height: 52)), Expanded(child: key('0')), Expanded(child: del)]),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({super.key, required this.label, required this.semanticLabel, required this.onTap, required this.child});

  final String label;
  final String semanticLabel;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        button: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  },
            child: SizedBox(height: 52, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}

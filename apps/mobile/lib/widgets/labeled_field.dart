import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

/// Text field with its label above it (design: label → 52 pt field → helper/error).
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.errorText,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
    this.maxLength,
    this.maxLines = 1,
    this.suffix,
    this.fieldKey,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final String? errorText;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final int? maxLength;
  final int? maxLines;
  final Widget? suffix;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Text(label, style: AppText.label)),
        const SizedBox(height: AppSpace.s8),
        // The visual label above is excluded; screen readers get it from here instead.
        Semantics(
          label: label,
          child: TextField(
            key: fieldKey,
            controller: controller,
            obscureText: obscure,
            enabled: enabled,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            autofillHints: autofillHints,
            onSubmitted: onSubmitted,
            onChanged: onChanged,
            maxLength: maxLength,
            maxLines: obscure ? 1 : maxLines,
            style: AppText.body,
            decoration: InputDecoration(
              hintText: hint,
              helperText: errorText == null ? helper : null,
              errorText: errorText,
              counterText: maxLength == null ? null : '',
              suffixIcon: suffix,
            ),
          ),
        ),
      ],
    );
  }
}

/// Password field with a show/hide toggle (44 pt target).
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.helper,
    this.errorText,
    this.textInputAction,
    this.onSubmitted,
    this.enabled = true,
    this.newPassword = false,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final String? errorText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool newPassword;
  final Key? fieldKey;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      fieldKey: widget.fieldKey,
      label: widget.label,
      controller: widget.controller,
      obscure: _hidden,
      helper: widget.helper,
      errorText: widget.errorText,
      enabled: widget.enabled,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      autofillHints: [widget.newPassword ? AutofillHints.newPassword : AutofillHints.password],
      suffix: IconButton(
        tooltip: _hidden ? 'Show password' : 'Hide password',
        icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.textSecondary),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    );
  }
}

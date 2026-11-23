import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showInfo(BuildContext context, String message) => showError(context, message);

/// Single text field dialog (create / rename). Returns the trimmed text or null.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
  String initial = '',
  String confirmLabel = 'Save',
  int maxLength = 150,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) {
      String? error;
      return StatefulBuilder(builder: (context, setState) {
        void submit() {
          final v = controller.text.trim();
          if (v.isEmpty) {
            setState(() => error = '$label is required');
            return;
          }
          Navigator.of(context).pop(v);
        }

        return AlertDialog(
          title: Text(title, style: AppText.title),
          content: TextField(
            key: const ValueKey('text-input-dialog-field'),
            controller: controller,
            autofocus: true,
            maxLength: maxLength,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => submit(),
            decoration: InputDecoration(labelText: label, hintText: hint, errorText: error, counterText: ''),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(
              key: const ValueKey('text-input-dialog-confirm'),
              onPressed: submit,
              child: Text(confirmLabel),
            ),
          ],
        );
      });
    },
  ).whenComplete(controller.dispose);
}

/// Confirmation dialog; [destructive] styles the confirm button red.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: AppText.title),
      content: Text(message, style: AppText.body),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('confirm-dialog-ok'),
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

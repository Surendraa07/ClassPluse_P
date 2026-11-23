final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

String? validateEmail(String value) {
  final v = value.trim();
  if (v.isEmpty) return 'Enter your email';
  if (!_emailRe.hasMatch(v)) return 'Enter a valid email address';
  return null;
}

String? validateNewPassword(String value) {
  if (value.length < 8) return 'Password must be at least 8 characters';
  if (value.length > 72) return 'Password must be at most 72 characters';
  return null;
}

String? validateName(String value) => value.trim().isEmpty ? 'Enter your name' : null;

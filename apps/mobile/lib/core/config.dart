import 'dart:io' show Platform;

/// Server base URL (REST + Socket.io), e.g. `--dart-define=API_URL=http://192.168.1.20:4000`.
/// Defaults: Android emulator → host machine via 10.0.2.2; iOS simulator → localhost.
/// Physical phones need API_URL set to the computer's LAN IP.
abstract final class AppConfig {
  static const _fromEnv = String.fromEnvironment('API_URL');

  static String get serverUrl {
    if (_fromEnv.isNotEmpty) return _fromEnv.endsWith('/') ? _fromEnv.substring(0, _fromEnv.length - 1) : _fromEnv;
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:4000';
    } catch (_) {
      // Platform is unavailable on some test hosts.
    }
    return 'http://localhost:4000';
  }

  static String get apiBase => '$serverUrl/api/v1';

  /// Scheme used in session QR codes: classpluse://join/<code>
  static const deepLinkScheme = 'classpluse';
}

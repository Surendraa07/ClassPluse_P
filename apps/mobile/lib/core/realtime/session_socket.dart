import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config.dart';

enum ConnectionStatus { connecting, connected, offline, rejected }

/// Result of an emit with acknowledgement.
class AckResult {
  const AckResult.ok(this.data)
      : ok = true,
        code = null,
        message = null;
  const AckResult.error(this.code, this.message)
      : ok = false,
        data = const {};

  final bool ok;
  final Map<String, dynamic> data;
  final String? code;
  final String? message;

  bool get isTimeout => code == 'TIMEOUT';
}

/// Wraps a socket.io client for one session. Reconnects automatically; the server re-sends the
/// latest state on every (re)connect, so callers only need to listen.
class SessionSocket {
  SessionSocket({required Map<String, dynamic> auth, String? url}) {
    _socket = _zone.run(() => io.io(
          url ?? AppConfig.serverUrl,
          io.OptionBuilder()
              .setTransports(['websocket'])
              .setAuth(auth)
              .disableAutoConnect()
              .enableReconnection()
              .setReconnectionDelay(1000)
              .setReconnectionDelayMax(5000)
              .enableForceNew()
              .build(),
        ));

    _socket.onConnect((_) => _setStatus(ConnectionStatus.connected));
    _socket.onDisconnect((_) {
      if (_status != ConnectionStatus.rejected) _setStatus(ConnectionStatus.offline);
    });
    _socket.onConnectError((err) {
      final code = _errorCode(err);
      if (code == 'SESSION_ENDED' || code == 'UNAUTHORIZED' || code == 'NOT_FOUND') {
        rejectedCode = code;
        _setStatus(ConnectionStatus.rejected);
        _socket.disconnect(); // a manual disconnect stops further reconnection attempts
      } else {
        _setStatus(ConnectionStatus.offline);
      }
    });
  }

  /// socket_io_client throws `WebSocketConnectionClosed` from its own close path when the server
  /// ends the connection (e.g. after `session:end`). It is harmless, so it is swallowed here
  /// instead of surfacing as an uncaught error; everything else is passed on.
  static final Zone _zone = Zone.current.fork(
    specification: ZoneSpecification(
      handleUncaughtError: (self, parent, zone, error, stack) {
        if (isBenignSocketClose(error)) return;
        parent.handleUncaughtError(zone, error, stack);
      },
    ),
  );

  static bool isBenignSocketClose(Object error) => error.runtimeType.toString() == 'WebSocketConnectionClosed';

  /// Runs [f] in the same guarded zone (used by tests that create raw sockets).
  static T runGuarded<T>(T Function() f) => _zone.run(f);

  late final io.Socket _socket;
  final _statusCtrl = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _status = ConnectionStatus.connecting;

  /// Set when the server refused the connection (e.g. `SESSION_ENDED`).
  String? rejectedCode;

  ConnectionStatus get status => _status;
  Stream<ConnectionStatus> get statusStream => _statusCtrl.stream;
  bool get isConnected => _status == ConnectionStatus.connected;

  void connect() => _zone.run(_socket.connect);

  /// Registers a handler for a server event; the payload is passed as a JSON map.
  void on(String event, void Function(Map<String, dynamic> data) handler) {
    _socket.on(event, (data) {
      if (data is Map) handler(Map<String, dynamic>.from(data));
    });
  }

  /// Emits and waits for the server's ack (`{ ok, ...}` / `{ ok: false, error }`).
  Future<AckResult> emit(String event, [Map<String, dynamic>? payload, Duration timeout = const Duration(seconds: 6)]) {
    if (!isConnected) return Future.value(const AckResult.error('OFFLINE', "You're offline"));
    final completer = Completer<AckResult>();
    _socket.emitWithAck(event, payload ?? <String, dynamic>{}, ack: (dynamic res) {
      if (completer.isCompleted) return;
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (map['ok'] == true) {
        completer.complete(AckResult.ok(map));
      } else {
        final err = map['error'] is Map ? Map<String, dynamic>.from(map['error'] as Map) : const <String, dynamic>{};
        completer.complete(AckResult.error(
          (err['code'] ?? 'UNKNOWN').toString(),
          (err['message'] ?? 'Something went wrong').toString(),
        ));
      }
    });
    return completer.future.timeout(timeout, onTimeout: () => const AckResult.error('TIMEOUT', 'No response from the server'));
  }

  void _setStatus(ConnectionStatus s) {
    if (_status == s) return;
    _status = s;
    if (!_statusCtrl.isClosed) _statusCtrl.add(s);
  }

  static String? _errorCode(Object? err) {
    if (err is Map && err['data'] is Map) return (err['data'] as Map)['code']?.toString();
    if (err is Map && err['message'] is String) return _codeFromMessage(err['message'] as String);
    if (err is String) return _codeFromMessage(err);
    return null;
  }

  static String? _codeFromMessage(String m) {
    final lower = m.toLowerCase();
    if (lower.contains('ended')) return 'SESSION_ENDED';
    if (lower.contains('invalid') || lower.contains('credentials')) return 'UNAUTHORIZED';
    if (lower.contains('not found')) return 'NOT_FOUND';
    return null;
  }

  void dispose() {
    _zone.run(_socket.dispose);
    _statusCtrl.close();
  }
}

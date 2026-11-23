import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/realtime/session_socket.dart';
import '../auth/auth_controller.dart';

class LecturerLiveState {
  const LecturerLiveState({
    this.connection = ConnectionStatus.connecting,
    this.live,
    this.participants = 0,
    this.results,
    this.pulse = const PulseTotals(),
    this.busy = false,
    this.error,
    this.rejectedCode,
  });

  final ConnectionStatus connection;
  final LiveState? live;
  final int participants;
  final LiveResults? results;
  final PulseTotals pulse;

  /// An action (start/next/end/toggle) is waiting for the server's ack.
  final bool busy;
  final String? error;
  final String? rejectedCode;

  /// Results for the slide currently shown (ignores late updates for an older slide).
  LiveResults? get currentResults =>
      results != null && results!.slideId == live?.currentSlide?.id ? results : null;

  LecturerLiveState copyWith({
    ConnectionStatus? connection,
    LiveState? live,
    int? participants,
    LiveResults? results,
    PulseTotals? pulse,
    bool? busy,
    String? error,
    bool clearError = false,
    String? rejectedCode,
  }) =>
      LecturerLiveState(
        connection: connection ?? this.connection,
        live: live ?? this.live,
        participants: participants ?? this.participants,
        results: results ?? this.results,
        pulse: pulse ?? this.pulse,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
        rejectedCode: rejectedCode ?? this.rejectedCode,
      );
}

/// Socket connection + live state for one session, as seen by its lecturer.
final lecturerLiveProvider = NotifierProvider.autoDispose.family<LecturerLiveController, LecturerLiveState, String>(
  LecturerLiveController.new,
);

class LecturerLiveController extends Notifier<LecturerLiveState> {
  LecturerLiveController(this.sessionId);
  final String sessionId;

  SessionSocket? _socket;
  StreamSubscription<ConnectionStatus>? _statusSub;

  @override
  LecturerLiveState build() {
    final token = ref.read(authControllerProvider).token;
    final socket = SessionSocket(auth: {'token': token, 'sessionId': sessionId});
    _socket = socket;

    socket.on('session:state', (d) => state = state.copyWith(live: LiveState.fromJson(d)));
    socket.on('participants:count', (d) => state = state.copyWith(participants: (d['count'] as num).toInt()));
    socket.on('results:update', (d) => state = state.copyWith(results: LiveResults.fromJson(d)));
    socket.on('pulse:update', (d) => state = state.copyWith(pulse: PulseTotals.fromJson(d)));
    socket.on('session:ended', (_) {
      final live = state.live;
      if (live != null) {
        state = state.copyWith(
          live: LiveState(
            sessionId: live.sessionId,
            status: SessionStatus.ended,
            showResultsToStudents: live.showResultsToStudents,
            totalSlides: live.totalSlides,
            code: live.code,
            presentationTitle: live.presentationTitle,
          ),
        );
      }
    });
    _statusSub = socket.statusStream.listen((s) {
      state = state.copyWith(connection: s, rejectedCode: socket.rejectedCode);
    });

    ref.onDispose(() {
      _statusSub?.cancel();
      socket.dispose();
    });
    socket.connect();
    return const LecturerLiveState();
  }

  Future<bool> _act(String event, [Map<String, dynamic>? payload]) async {
    final socket = _socket;
    if (socket == null) return false;
    state = state.copyWith(busy: true, clearError: true);
    final res = await socket.emit(event, payload);
    state = state.copyWith(busy: false, error: res.ok ? null : res.message, clearError: res.ok);
    return res.ok;
  }

  Future<bool> start() => _act('session:start');
  Future<bool> next() => _act('slide:next');
  Future<bool> end() => _act('session:end');
  Future<bool> setShowResults(bool show) => _act('results:toggle', {'show': show});

  void clearError() => state = state.copyWith(clearError: true);

  void reconnect() => _socket?.connect();
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/realtime/session_socket.dart';
import '../../core/storage/local_store.dart';

/// What happened to the student's answer for the current slide.
enum AnswerStatus { none, sending, recorded, queued, closed }

class StudentState {
  const StudentState({
    this.connection = ConnectionStatus.connecting,
    this.live,
    this.participants = 0,
    this.results,
    this.selectedOptionId,
    this.submittedOptionId,
    this.answerStatus = AnswerStatus.none,
    this.pulse,
    this.pulsePending = false,
    this.error,
    this.ended = false,
  });

  final ConnectionStatus connection;
  final LiveState? live;
  final int participants;
  final LiveResults? results;

  /// Option tapped but not yet submitted.
  final String? selectedOptionId;

  /// Last option sent (or queued) for the current slide.
  final String? submittedOptionId;
  final AnswerStatus answerStatus;
  final PulseState? pulse;

  /// Pulse chosen while offline; sent on reconnect.
  final bool pulsePending;
  final String? error;
  final bool ended;

  bool get isOffline => connection != ConnectionStatus.connected;
  Slide? get slide => live?.currentSlide;

  /// Results are only kept when the lecturer allows it and they match the current slide.
  LiveResults? get visibleResults =>
      (live?.showResultsToStudents ?? false) && results?.slideId == slide?.id ? results : null;

  StudentState copyWith({
    ConnectionStatus? connection,
    LiveState? live,
    int? participants,
    LiveResults? results,
    String? selectedOptionId,
    bool clearSelected = false,
    String? submittedOptionId,
    bool clearSubmitted = false,
    AnswerStatus? answerStatus,
    PulseState? pulse,
    bool? pulsePending,
    String? error,
    bool clearError = false,
    bool? ended,
  }) =>
      StudentState(
        connection: connection ?? this.connection,
        live: live ?? this.live,
        participants: participants ?? this.participants,
        results: results ?? this.results,
        selectedOptionId: clearSelected ? null : (selectedOptionId ?? this.selectedOptionId),
        submittedOptionId: clearSubmitted ? null : (submittedOptionId ?? this.submittedOptionId),
        answerStatus: answerStatus ?? this.answerStatus,
        pulse: pulse ?? this.pulse,
        pulsePending: pulsePending ?? this.pulsePending,
        error: clearError ? null : (error ?? this.error),
        ended: ended ?? this.ended,
      );
}

/// Student's live connection for the session stored on the phone.
final studentSessionProvider = NotifierProvider.autoDispose<StudentSessionController, StudentState>(
  StudentSessionController.new,
);

class StudentSessionController extends Notifier<StudentState> {
  SessionSocket? _socket;
  StreamSubscription<ConnectionStatus>? _statusSub;
  late StudentSession _session;

  LocalStore get _store => ref.read(localStoreProvider);

  @override
  StudentState build() {
    final session = _store.studentSession;
    if (session == null) return const StudentState(connection: ConnectionStatus.rejected, ended: true);
    _session = session;

    final socket = SessionSocket(auth: {'participantToken': session.participantToken});
    _socket = socket;

    socket.on('session:state', _onState);
    socket.on('participants:count', (d) => state = state.copyWith(participants: (d['count'] as num).toInt()));
    socket.on('results:update', (d) => state = state.copyWith(results: LiveResults.fromJson(d)));
    socket.on('me:state', _onMe);
    socket.on('session:ended', (_) => _markEnded());

    _statusSub = socket.statusStream.listen((s) {
      state = state.copyWith(connection: s);
      if (s == ConnectionStatus.connected) _flush();
      if (s == ConnectionStatus.rejected && socket.rejectedCode == 'SESSION_ENDED') _markEnded();
    });

    ref.onDispose(() {
      _statusSub?.cancel();
      socket.dispose();
    });

    // Restore a queued answer (e.g. after an app restart while offline).
    final queued = _store.answerQueue.where((q) => q.sessionId == session.sessionId).toList();
    socket.connect();
    return StudentState(
      submittedOptionId: queued.isEmpty ? null : queued.last.optionId,
      answerStatus: queued.isEmpty ? AnswerStatus.none : AnswerStatus.queued,
    );
  }

  void _onState(Map<String, dynamic> d) {
    final next = LiveState.fromJson(d);
    final prevSlide = state.live?.currentSlide?.id;
    final newSlide = next.currentSlide?.id;
    if (next.status == SessionStatus.ended) {
      _markEnded();
      return;
    }
    if (prevSlide != null && prevSlide != newSlide) {
      // Lecturer moved on: reset the answer UI for the new question.
      state = state.copyWith(live: next, clearSelected: true, clearSubmitted: true, answerStatus: AnswerStatus.none);
    } else {
      state = state.copyWith(live: next);
    }
  }

  void _onMe(Map<String, dynamic> d) {
    final answer = d['answer'];
    final pulse = PulseState.parse(d['pulse']);
    var next = state;
    if (answer is Map && answer['slideId'] == state.slide?.id && next.answerStatus != AnswerStatus.queued) {
      final optionId = answer['optionId'] as String;
      next = next.copyWith(selectedOptionId: optionId, submittedOptionId: optionId, answerStatus: AnswerStatus.recorded);
    }
    if (pulse != null && !state.pulsePending) next = next.copyWith(pulse: pulse);
    state = next;
  }

  void _markEnded() {
    if (state.ended) return;
    state = state.copyWith(ended: true);
    _store.clearStudentSession();
  }

  void select(String optionId) {
    if (state.answerStatus == AnswerStatus.closed) return;
    state = state.copyWith(selectedOptionId: optionId, clearError: true);
  }

  /// Sends the selected answer, or saves it on the phone when offline.
  Future<void> submit() async {
    final slide = state.slide;
    final optionId = state.selectedOptionId;
    if (slide == null || optionId == null) return;
    final queued = QueuedAnswer(sessionId: _session.sessionId, slideId: slide.id, optionId: optionId);

    if (state.isOffline) {
      await _store.enqueueAnswer(queued);
      state = state.copyWith(submittedOptionId: optionId, answerStatus: AnswerStatus.queued, clearError: true);
      return;
    }
    state = state.copyWith(answerStatus: AnswerStatus.sending, clearError: true);
    final res = await _socket!.emit('answer:submit', {'slideId': slide.id, 'optionId': optionId});
    if (res.ok) {
      await _store.removeQueued(queued);
      state = state.copyWith(submittedOptionId: optionId, answerStatus: AnswerStatus.recorded);
    } else if (res.code == 'OFFLINE' || res.isTimeout) {
      await _store.enqueueAnswer(queued);
      state = state.copyWith(submittedOptionId: optionId, answerStatus: AnswerStatus.queued);
    } else if (res.code == 'SLIDE_CLOSED') {
      state = state.copyWith(answerStatus: AnswerStatus.closed, error: 'This question is closed.');
    } else {
      state = state.copyWith(answerStatus: AnswerStatus.none, error: res.message);
    }
  }

  /// Only the current state counts; repeated taps on the same state send nothing.
  Future<void> setPulse(PulseState p) async {
    if (state.pulse == p && !state.pulsePending) return;
    state = state.copyWith(pulse: p, pulsePending: true);
    if (state.isOffline) return; // sent on reconnect
    final res = await _socket!.emit('pulse:set', {'state': p.api});
    if (res.ok && state.pulse == p) state = state.copyWith(pulsePending: false);
  }

  /// Resends queued answers and a pending pulse after (re)connecting.
  Future<void> _flush() async {
    final socket = _socket;
    if (socket == null) return;
    for (final q in _store.answerQueue.where((q) => q.sessionId == _session.sessionId)) {
      final res = await socket.emit('answer:submit', {'slideId': q.slideId, 'optionId': q.optionId});
      if (res.ok || (res.code != 'OFFLINE' && !res.isTimeout)) await _store.removeQueued(q);
      if (q.slideId == state.slide?.id) {
        state = state.copyWith(
          answerStatus: res.ok ? AnswerStatus.recorded : (res.code == 'SLIDE_CLOSED' ? AnswerStatus.closed : state.answerStatus),
        );
      }
    }
    final p = state.pulse;
    if (state.pulsePending && p != null) {
      final res = await socket.emit('pulse:set', {'state': p.api});
      if (res.ok) state = state.copyWith(pulsePending: false);
    }
  }

  void retryNow() => _socket?.connect();

  Future<void> leave() async {
    await _store.clearStudentSession();
    _socket?.dispose();
  }
}

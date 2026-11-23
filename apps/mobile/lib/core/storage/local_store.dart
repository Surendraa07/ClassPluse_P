import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The student's anonymous session (no personal data).
class StudentSession {
  const StudentSession({required this.participantToken, required this.sessionId, required this.code});

  final String participantToken;
  final String sessionId;
  final String code;

  Map<String, dynamic> toJson() => {'participantToken': participantToken, 'sessionId': sessionId, 'code': code};

  static StudentSession? fromJson(Object? json) {
    if (json is! Map) return null;
    final t = json['participantToken'], s = json['sessionId'], c = json['code'];
    if (t is! String || s is! String || c is! String) return null;
    return StudentSession(participantToken: t, sessionId: s, code: c);
  }
}

/// An answer waiting to be sent because the socket was offline.
class QueuedAnswer {
  const QueuedAnswer({required this.sessionId, required this.slideId, required this.optionId});

  final String sessionId;
  final String slideId;
  final String optionId;

  Map<String, dynamic> toJson() => {'sessionId': sessionId, 'slideId': slideId, 'optionId': optionId};

  static QueuedAnswer? fromJson(Object? json) {
    if (json is! Map) return null;
    final a = json['sessionId'], b = json['slideId'], c = json['optionId'];
    if (a is! String || b is! String || c is! String) return null;
    return QueuedAnswer(sessionId: a, slideId: b, optionId: c);
  }
}

/// Small typed wrapper over shared_preferences.
class LocalStore {
  LocalStore(this._prefs);
  final SharedPreferences _prefs;

  static const _kLecturerToken = 'lecturer.token';
  static const _kLecturer = 'lecturer.profile';
  static const _kStudentSession = 'student.session';
  static const _kAnswerQueue = 'student.answerQueue';
  static const _kHasJoined = 'student.hasJoinedBefore';

  // ---- lecturer ----
  String? get lecturerToken => _prefs.getString(_kLecturerToken);
  Map<String, dynamic>? get lecturerProfile => _decodeMap(_prefs.getString(_kLecturer));

  Future<void> saveLecturer(String token, Map<String, dynamic> profile) async {
    await _prefs.setString(_kLecturerToken, token);
    await _prefs.setString(_kLecturer, jsonEncode(profile));
  }

  Future<void> clearLecturer() async {
    await _prefs.remove(_kLecturerToken);
    await _prefs.remove(_kLecturer);
  }

  // ---- student ----
  StudentSession? get studentSession => StudentSession.fromJson(_decodeMap(_prefs.getString(_kStudentSession)));
  bool get hasJoinedBefore => _prefs.getBool(_kHasJoined) ?? false;

  Future<void> saveStudentSession(StudentSession s) async {
    await _prefs.setString(_kStudentSession, jsonEncode(s.toJson()));
    await _prefs.setBool(_kHasJoined, true);
  }

  Future<void> clearStudentSession() async {
    await _prefs.remove(_kStudentSession);
    await _prefs.remove(_kAnswerQueue);
  }

  /// Only the latest answer per slide is kept.
  List<QueuedAnswer> get answerQueue {
    final raw = _prefs.getString(_kAnswerQueue);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list.map(QueuedAnswer.fromJson).whereType<QueuedAnswer>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> enqueueAnswer(QueuedAnswer a) async {
    final next = [...answerQueue.where((q) => !(q.sessionId == a.sessionId && q.slideId == a.slideId)), a];
    await _prefs.setString(_kAnswerQueue, jsonEncode(next.map((q) => q.toJson()).toList()));
  }

  Future<void> removeQueued(QueuedAnswer a) async {
    final next = answerQueue.where((q) => !(q.sessionId == a.sessionId && q.slideId == a.slideId)).toList();
    await _prefs.setString(_kAnswerQueue, jsonEncode(next.map((q) => q.toJson()).toList()));
  }

  static Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}

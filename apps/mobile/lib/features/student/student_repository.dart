import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/providers.dart';
import '../../core/storage/local_store.dart';

final studentRepositoryProvider = Provider<StudentRepository>(
  (ref) => StudentRepository(ref.watch(apiClientProvider), ref.watch(localStoreProvider)),
);

/// Extracts a 6-digit code from a scanned QR value: `classpluse://join/482913` or `482913`.
String? parseSessionCode(String raw) {
  final v = raw.trim();
  final link = RegExp(r'^classpluse://join/(\d{6})/?$', caseSensitive: false).firstMatch(v);
  if (link != null) return link.group(1);
  final plain = RegExp(r'^\d{6}$').firstMatch(v.replaceAll(' ', ''));
  return plain?.group(0);
}

class StudentRepository {
  StudentRepository(this._api, this._store);
  final ApiClient _api;
  final LocalStore _store;

  /// Joins anonymously. If this phone already joined the same session, it rejoins with the same
  /// token (so it is not counted twice).
  Future<StudentSession> join(String code) async {
    final previous = _store.studentSession;
    final res = await _api.post<Map<String, dynamic>>('/join', {
      'code': code,
      if (previous != null && previous.code == code) 'participantToken': previous.participantToken,
    });
    final session = StudentSession(
      participantToken: res['participantToken'] as String,
      sessionId: res['sessionId'] as String,
      code: code,
    );
    if (previous != null && previous.sessionId != session.sessionId) await _store.clearStudentSession();
    await _store.saveStudentSession(session);
    return session;
  }

  Future<void> leave() => _store.clearStudentSession();
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/providers.dart';

class Lecturer {
  const Lecturer({required this.id, required this.name, required this.email, this.avatarUrl});

  final String id;
  final String name;
  final String email;
  final String? avatarUrl;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  factory Lecturer.fromJson(Map<String, dynamic> j) => Lecturer(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String,
        avatarUrl: j['avatarUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email, 'avatarUrl': avatarUrl};
}

class AuthState {
  const AuthState({this.token, this.lecturer, this.sessionExpired = false});

  final String? token;
  final Lecturer? lecturer;

  /// True right after an automatic logout caused by a 401 (shown on the login screen).
  final bool sessionExpired;

  bool get isLoggedIn => token != null && lecturer != null;
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final store = ref.read(localStoreProvider);
    final token = store.lecturerToken;
    final profile = store.lecturerProfile;
    if (token != null && profile != null) {
      try {
        return AuthState(token: token, lecturer: Lecturer.fromJson(profile));
      } catch (_) {
        // corrupted profile → treat as logged out
      }
    }
    return const AuthState();
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> login({required String email, required String password}) async {
    final res = await _api.post<Map<String, dynamic>>('/auth/login', {'email': email.trim(), 'password': password});
    await _save(res);
  }

  Future<void> register({required String name, required String email, required String password}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/auth/register',
      {'name': name.trim(), 'email': email.trim(), 'password': password},
    );
    await _save(res);
  }

  /// Refreshes the profile; a 401 logs out via the API client's handler.
  Future<void> refreshMe() async {
    if (!state.isLoggedIn) return;
    try {
      final res = await _api.get<Map<String, dynamic>>('/auth/me');
      final lecturer = Lecturer.fromJson(res['lecturer'] as Map<String, dynamic>);
      await ref.read(localStoreProvider).saveLecturer(state.token!, lecturer.toJson());
      state = AuthState(token: state.token, lecturer: lecturer);
    } on ApiException {
      // Offline etc.: keep the cached profile.
    }
  }

  /// Saves a new avatar URL (from a signed upload), or removes the avatar with null.
  Future<void> updateAvatar(String? avatarUrl) async {
    if (!state.isLoggedIn) return;
    final res = await _api.patch<Map<String, dynamic>>('/auth/me', {'avatarUrl': avatarUrl});
    final lecturer = Lecturer.fromJson(res['lecturer'] as Map<String, dynamic>);
    await ref.read(localStoreProvider).saveLecturer(state.token!, lecturer.toJson());
    state = AuthState(token: state.token, lecturer: lecturer);
  }

  Future<void> logout({bool expired = false}) async {
    await ref.read(localStoreProvider).clearLecturer();
    state = AuthState(sessionExpired: expired);
  }

  Future<void> _save(Map<String, dynamic> res) async {
    final token = res['token'] as String;
    final lecturer = Lecturer.fromJson(res['lecturer'] as Map<String, dynamic>);
    await ref.read(localStoreProvider).saveLecturer(token, lecturer.toJson());
    state = AuthState(token: token, lecturer: lecturer);
  }
}

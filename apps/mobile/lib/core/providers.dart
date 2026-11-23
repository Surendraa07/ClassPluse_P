import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/auth/auth_controller.dart';
import 'api/api_client.dart';
import 'storage/local_store.dart';

/// Overridden in main() with the instance loaded before runApp.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override in main'));

final localStoreProvider = Provider<LocalStore>((ref) => LocalStore(ref.watch(sharedPrefsProvider)));

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    token: () => ref.read(authControllerProvider).token,
    onUnauthorized: () => ref.read(authControllerProvider.notifier).logout(expired: true),
  );
});

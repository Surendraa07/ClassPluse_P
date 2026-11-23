import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/welcome/welcome_screen.dart';
import 'routes_lecturer.dart';
import 'routes_student.dart';

/// Matches the path Flutter receives for `classpluse://join/482913` (host "join", path "/482913")
/// as well as `/join/482913`.
final _deepLinkCode = RegExp(r'^/(?:join/)?(\d{6})/?$');

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final path = state.uri.path;

      // Deep link from a QR code → join screen with the code filled in.
      final m = _deepLinkCode.firstMatch(path);
      if (m != null) return '/join?code=${m.group(1)}';

      final loggedIn = ref.read(authControllerProvider).isLoggedIn;
      final isLecturerArea = path.startsWith('/lecturer');
      if (isLecturerArea && !loggedIn) return '/login';
      if ((path == '/login' || path == '/signup') && loggedIn) return '/lecturer';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      ...lecturerRoutes,
      ...studentRoutes,
    ],
    errorBuilder: (context, state) => _NotFound(location: state.uri.toString()),
  );
});

class _NotFound extends StatelessWidget {
  const _NotFound({required this.location});
  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Page not found', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(location, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => context.go('/'), child: const Text('Go home')),
            ],
          ),
        ),
      ),
    );
  }
}

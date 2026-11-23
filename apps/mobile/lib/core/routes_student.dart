import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../features/student/ended_screen.dart';
import '../features/student/join_screen.dart';
import '../features/student/scan_screen.dart';
import '../features/student/student_session_screen.dart';

/// Student area (no account).
final studentRoutes = <RouteBase>[
  GoRoute(
    path: '/join',
    builder: (_, s) => JoinScreen(key: ValueKey(s.uri.toString()), initialCode: s.uri.queryParameters['code']),
  ),
  GoRoute(path: '/join/scan', builder: (_, _) => const ScanScreen()),
  GoRoute(path: '/student/session', builder: (_, _) => const StudentSessionScreen()),
  GoRoute(path: '/student/ended', builder: (_, _) => const SessionEndedScreen()),
];

import 'package:go_router/go_router.dart';

import '../features/lecturer/builder_screen.dart';
import '../features/lecturer/home_screen.dart';
import '../features/lecturer/live_session_screen.dart';
import '../features/lecturer/slide_editor_screen.dart';
import '../features/lecturer/summary_screen.dart';
import 'models.dart';

/// Lecturer area (requires login; see the redirect in router.dart).
final lecturerRoutes = <RouteBase>[
  GoRoute(path: '/lecturer', builder: (_, _) => const LecturerHomeScreen()),
  GoRoute(
    path: '/lecturer/presentations/:id',
    builder: (_, s) => BuilderScreen(presentationId: s.pathParameters['id']!),
  ),
  GoRoute(
    path: '/lecturer/presentations/:id/slides/new',
    builder: (_, s) => SlideEditorScreen(
      presentationId: s.pathParameters['id']!,
      initialType: SlideType.parse(s.uri.queryParameters['type']),
    ),
  ),
  GoRoute(
    path: '/lecturer/presentations/:id/slides/:slideId',
    builder: (_, s) => SlideEditorScreen(presentationId: s.pathParameters['id']!, slideId: s.pathParameters['slideId']),
  ),
  GoRoute(
    path: '/lecturer/sessions/:id',
    builder: (_, s) => LiveSessionScreen(sessionId: s.pathParameters['id']!),
  ),
  GoRoute(
    path: '/lecturer/sessions/:id/summary',
    builder: (_, s) => SummaryScreen(sessionId: s.pathParameters['id']!),
  ),
  GoRoute(
    path: '/lecturer/sessions/:id/summary/:index',
    builder: (_, s) => QuestionDetailScreen(
      sessionId: s.pathParameters['id']!,
      index: int.tryParse(s.pathParameters['index']!) ?? 0,
    ),
  ),
];

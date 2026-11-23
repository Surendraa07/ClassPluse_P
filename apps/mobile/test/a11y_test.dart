// Accessibility guideline checks (tap targets ≥ 48dp Android / 44pt iOS, labelled targets,
// text contrast) on key screens.
import 'package:classpluse/core/providers.dart';
import 'package:classpluse/core/theme/app_theme.dart';
import 'package:classpluse/features/auth/login_screen.dart';
import 'package:classpluse/features/student/ended_screen.dart';
import 'package:classpluse/features/student/join_screen.dart';
import 'package:classpluse/features/welcome/welcome_screen.dart';
import 'package:classpluse/widgets/pulse_button.dart';
import 'package:classpluse/widgets/result_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _app(Widget screen) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => screen)]);
  return ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
  );
}

Future<void> _expectGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  for (final (name, screen) in [
    ('Welcome', const WelcomeScreen()),
    ('Join', const JoinScreen()),
    ('Login', const LoginScreen()),
    ('Session ended', const SessionEndedScreen()),
  ]) {
    testWidgets('$name screen meets tap-target, label and contrast guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(1170, 2532); // iPhone-sized
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await _app(screen));
      await tester.pump();
      await _expectGuidelines(tester);
      handle.dispose();
    });
  }

  testWidgets('pulse buttons and result bars meet the guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PulseButton(kind: PulseKind.following, selected: true, onTap: () {}),
            const SizedBox(height: 16),
            PulseButton(kind: PulseKind.lost, selected: false, onTap: () {}),
            const SizedBox(height: 16),
            const ResultBar(label: 'do-while', percent: 56, count: 13, isCorrect: true, large: true),
            const ResultBar(label: 'for', percent: 28, count: 7),
          ],
        ),
      ),
    ));
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('body text is at least 16px', (tester) async {
    final theme = buildAppTheme();
    expect(theme.textTheme.bodyLarge!.fontSize, greaterThanOrEqualTo(16));
    expect(theme.textTheme.bodyMedium!.fontSize, greaterThanOrEqualTo(16));
    expect(AppText.body.fontSize, 16);
  });
}

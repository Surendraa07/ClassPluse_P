// Renders key screens to PNG with canned data, for design review without a device.
//
//   flutter test tool/screens_test.dart --update-goldens
//
// Output: apps/mobile/build/screenshots/*.png (390×844 pt @2x). Uses the Flutter SDK's Roboto as
// a stand-in for Inter, and the Material Icons font.
import 'dart:io';

import 'package:classpluse/core/models.dart';
import 'package:classpluse/core/providers.dart';
import 'package:classpluse/core/realtime/session_socket.dart';
import 'package:classpluse/core/theme/app_theme.dart';
import 'package:classpluse/features/auth/login_screen.dart';
import 'package:classpluse/features/lecturer/builder_screen.dart';
import 'package:classpluse/features/lecturer/home_screen.dart';
import 'package:classpluse/features/lecturer/live_session_controller.dart';
import 'package:classpluse/features/lecturer/live_session_screen.dart';
import 'package:classpluse/features/lecturer/presentations_controller.dart';
import 'package:classpluse/features/lecturer/slide_editor_screen.dart';
import 'package:classpluse/features/lecturer/summary_screen.dart';
import 'package:classpluse/features/student/ended_screen.dart';
import 'package:classpluse/features/student/join_screen.dart';
import 'package:classpluse/features/student/student_session_controller.dart';
import 'package:classpluse/features/student/student_session_screen.dart';
import 'package:classpluse/features/welcome/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------- canned data

const _poll = Slide(
  id: 's1',
  type: SlideType.poll,
  question: 'Is a string a primitive type?',
  options: [
    SlideOption(id: 'o1', label: 'Yes'),
    SlideOption(id: 'o2', label: 'No'),
    SlideOption(id: 'o3', label: 'Depends on the language'),
  ],
);
const _quiz = Slide(
  id: 's2',
  order: 1,
  type: SlideType.quiz,
  question: 'Which loop always runs at least once?',
  options: [
    SlideOption(id: 'q1', label: 'for'),
    SlideOption(id: 'q2', label: 'while'),
    SlideOption(id: 'q3', label: 'do-while', isCorrect: true),
  ],
);

LiveState _live(SessionStatus status, {Slide? slide, int index = 0, bool show = false, bool lecturer = true}) => LiveState(
      sessionId: 'sess',
      status: status,
      showResultsToStudents: show,
      totalSlides: 2,
      currentSlide: slide,
      currentIndex: slide == null ? null : index,
      code: lecturer ? '482913' : null,
      presentationTitle: 'POP Lecture 4: Loops',
    );

const _results = LiveResults(slideId: 's1', counts: {'o1': 7, 'o2': 13, 'o3': 4}, answered: 24, participants: 28);

class FakePresentations extends PresentationsController {
  @override
  Future<List<PresentationSummary>> build() async => [
        PresentationSummary(id: 'p1', title: 'POP Lecture 4: Loops', slideCount: 2, updatedAt: DateTime.now().subtract(const Duration(hours: 2))),
        PresentationSummary(id: 'p2', title: 'Programming Basics · Week 1', slideCount: 8, updatedAt: DateTime.now().subtract(const Duration(days: 1))),
      ];
}

class FakePresentation extends PresentationController {
  FakePresentation(super.id);
  @override
  Future<Presentation> build() async => const Presentation(id: 'p1', title: 'POP Lecture 4: Loops', slides: [_poll, _quiz]);
}

class FakeLecturerLive extends LecturerLiveController {
  FakeLecturerLive(super.sessionId, this.value);
  final LecturerLiveState value;
  @override
  LecturerLiveState build() => value;
}

class FakeStudent extends StudentSessionController {
  FakeStudent(this.value);
  final StudentState value;
  @override
  StudentState build() => value;
}

// ---------------------------------------------------------------- harness

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String f) async => ByteData.sublistView(await File('$dir/$f').readAsBytes());
  final inter = FontLoader('Inter');
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']) {
    inter.addFont(read(f));
  }
  await inter.load();
  final icons = FontLoader('MaterialIcons')..addFont(read('materialicons-regular.otf'));
  await icons.load();
}

Future<void> _shot(
  WidgetTester tester,
  String name,
  Widget screen, {
  List<dynamic> overrides = const [],
  Map<String, Object> prefs = const {},
  Future<void> Function(WidgetTester)? before,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => screen)]);
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(sp), ...overrides.cast()],
    child: MaterialApp.router(theme: buildAppTheme(), debugShowCheckedModeBanner: false, routerConfig: router),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  if (before != null) await before(tester);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('../build/screenshots/$name.png'));
}

const _loggedIn = {
  'lecturer.token': 'x',
  'lecturer.profile': '{"id":"l1","name":"Suren Thapa","email":"demo@classpluse.app","avatarUrl":null}',
};

void main() {
  setUpAll(_loadFonts);

  testWidgets('01 welcome', (t) => _shot(t, '01-welcome', const WelcomeScreen()));
  testWidgets('02 login', (t) => _shot(t, '02-login', const LoginScreen()));
  testWidgets('03 join', (t) async {
    await _shot(t, '03-join', const JoinScreen(), before: (t) async {
      for (final d in ['4', '8', '2', '9']) {
        await t.tap(find.byKey(ValueKey('keypad-$d')));
      }
      await t.pump();
    });
  });
  testWidgets('04 lecturer home', (t) => _shot(t, '04-lecturer-home', const LecturerHomeScreen(),
      prefs: _loggedIn, overrides: [presentationsProvider.overrideWith(FakePresentations.new)]));
  testWidgets('05 builder', (t) => _shot(t, '05-builder', const BuilderScreen(presentationId: 'p1'),
      prefs: _loggedIn, overrides: [presentationProvider.overrideWith2(FakePresentation.new)]));
  testWidgets('06 slide editor (quiz)', (t) => _shot(t, '06-slide-editor', const SlideEditorScreen(presentationId: 'p1', slideId: 's2'),
      prefs: _loggedIn, overrides: [presentationProvider.overrideWith2(FakePresentation.new)]));
  testWidgets('07 waiting room', (t) => _shot(t, '07-waiting-room', const LiveSessionScreen(sessionId: 'sess'),
      prefs: _loggedIn,
      overrides: [
        lecturerLiveProvider.overrideWith2((id) => FakeLecturerLive(
              id,
              LecturerLiveState(connection: ConnectionStatus.connected, live: _live(SessionStatus.waiting), participants: 12),
            )),
      ]));
  testWidgets('08 live dashboard', (t) => _shot(t, '08-live-dashboard', const LiveSessionScreen(sessionId: 'sess'),
      prefs: _loggedIn,
      overrides: [
        lecturerLiveProvider.overrideWith2((id) => FakeLecturerLive(
              id,
              LecturerLiveState(
                connection: ConnectionStatus.connected,
                live: _live(SessionStatus.live, slide: _poll),
                participants: 28,
                results: _results,
                pulse: const PulseTotals(following: 17, lost: 9),
              ),
            )),
      ]));
  testWidgets('09 summary', (t) => _shot(t, '09-summary', const SummaryScreen(sessionId: 'sess'),
      prefs: _loggedIn,
      overrides: [
        summaryProvider.overrideWith((ref, id) async => SessionSummary(
              sessionId: 'sess',
              presentationTitle: 'POP Lecture 4: Loops',
              status: SessionStatus.ended,
              participants: 28,
              endedAt: DateTime.now().subtract(const Duration(minutes: 3)),
              pulse: const PulseTotals(following: 20, lost: 6),
              slides: const [
                SummarySlide(slideId: 's1', index: 0, type: SlideType.poll, question: 'Is a string a primitive type?', responses: 24, options: [
                  SummaryOption(id: 'o1', label: 'Yes', isCorrect: false, count: 7, percent: 29.2),
                  SummaryOption(id: 'o2', label: 'No', isCorrect: false, count: 13, percent: 54.2),
                  SummaryOption(id: 'o3', label: 'Depends on the language', isCorrect: false, count: 4, percent: 16.7),
                ]),
                SummarySlide(slideId: 's2', index: 1, type: SlideType.quiz, question: 'Which loop always runs at least once?', responses: 22, percentCorrect: 64, options: [
                  SummaryOption(id: 'q1', label: 'for', isCorrect: false, count: 5, percent: 22.7),
                  SummaryOption(id: 'q2', label: 'while', isCorrect: false, count: 3, percent: 13.6),
                  SummaryOption(id: 'q3', label: 'do-while', isCorrect: true, count: 14, percent: 63.6),
                ]),
              ],
            )),
      ]));
  testWidgets('10 student waiting', (t) => _shot(t, '10-student-waiting', const StudentSessionScreen(),
      overrides: [
        studentSessionProvider.overrideWith(() => FakeStudent(StudentState(
              connection: ConnectionStatus.connected,
              live: _live(SessionStatus.waiting, lecturer: false),
              participants: 24,
            ))),
      ]));
  testWidgets('11 student question selected', (t) => _shot(t, '11-student-question', const StudentSessionScreen(),
      overrides: [
        studentSessionProvider.overrideWith(() => FakeStudent(StudentState(
              connection: ConnectionStatus.connected,
              live: _live(SessionStatus.live, slide: _poll, lecturer: false),
              participants: 24,
              selectedOptionId: 'o2',
            ))),
      ]));
  testWidgets('12 student recorded + results', (t) => _shot(t, '12-student-recorded-results', const StudentSessionScreen(),
      overrides: [
        studentSessionProvider.overrideWith(() => FakeStudent(StudentState(
              connection: ConnectionStatus.connected,
              live: _live(SessionStatus.live, slide: _poll, show: true, lecturer: false),
              participants: 28,
              results: _results,
              selectedOptionId: 'o2',
              submittedOptionId: 'o2',
              answerStatus: AnswerStatus.recorded,
            ))),
      ]));
  testWidgets('13 student offline', (t) => _shot(t, '13-student-offline', const StudentSessionScreen(),
      overrides: [
        studentSessionProvider.overrideWith(() => FakeStudent(StudentState(
              connection: ConnectionStatus.offline,
              live: _live(SessionStatus.live, slide: _poll, lecturer: false),
              selectedOptionId: 'o2',
              submittedOptionId: 'o2',
              answerStatus: AnswerStatus.queued,
            ))),
      ]));
  testWidgets('14 student pulse', (t) => _shot(t, '14-student-pulse', const StudentSessionScreen(),
      overrides: [
        studentSessionProvider.overrideWith(() => FakeStudent(StudentState(
              connection: ConnectionStatus.connected,
              live: _live(SessionStatus.live, slide: _poll, lecturer: false),
              pulse: PulseState.following,
            ))),
      ],
      before: (t) async {
        await t.tap(find.byKey(const ValueKey('tab-pulse')));
        await t.pump(const Duration(milliseconds: 400));
      }));
  testWidgets('15 session ended', (t) => _shot(t, '15-session-ended', const SessionEndedScreen()));
}

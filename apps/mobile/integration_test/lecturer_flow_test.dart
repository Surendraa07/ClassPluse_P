// Lecturer UI flow against a running local server, with two simulated students (REST + socket).
//
//   flutter test integration_test/lecturer_flow_test.dart -d flutter-tester   (no phone needed)
//   flutter test integration_test/lecturer_flow_test.dart -d emulator-5554

import 'dart:async';
import 'dart:io' show Platform;

import 'package:classpluse/app.dart';
import 'package:classpluse/core/config.dart';
import 'package:classpluse/core/providers.dart';
import 'package:classpluse/core/realtime/session_socket.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TimeoutException('Timed out waiting for $finder');
}

/// An anonymous student driven through the API and socket.
class SimStudent {
  late io.Socket socket;
  final states = <Map<String, dynamic>>[];
  final results = <Map<String, dynamic>>[];
  bool ended = false;

  Future<void> join(String code) async {
    final res = await Dio(BaseOptions(baseUrl: AppConfig.apiBase)).post<Map<String, dynamic>>('/join', data: {'code': code});
    final token = res.data!['participantToken'] as String;
    final connected = Completer<void>();
    socket = SessionSocket.runGuarded<io.Socket>(() => io.io(
      AppConfig.serverUrl,
      io.OptionBuilder().setTransports(['websocket']).setAuth({'participantToken': token}).enableForceNew().build(),
    ))
      ..onConnect((_) => connected.isCompleted ? null : connected.complete())
      ..on('session:state', (d) => states.add(Map<String, dynamic>.from(d as Map)))
      ..on('results:update', (d) => results.add(Map<String, dynamic>.from(d as Map)))
      ..on('session:ended', (_) => ended = true);
    await connected.future.timeout(const Duration(seconds: 10));
  }

  Map<String, dynamic>? get currentSlide =>
      states.isEmpty ? null : states.last['currentSlide'] as Map<String, dynamic>?;

  Future<Map<String, dynamic>> emit(String event, Map<String, dynamic> payload) {
    final c = Completer<Map<String, dynamic>>();
    socket.emitWithAck(event, payload, ack: (dynamic r) => c.complete(Map<String, dynamic>.from(r as Map)));
    return c.future.timeout(const Duration(seconds: 10));
  }

  Future<void> answer(int optionIndex) async {
    final slide = currentSlide!;
    final option = (slide['options'] as List)[optionIndex] as Map;
    final res = await emit('answer:submit', {'slideId': slide['id'], 'optionId': option['id']});
    expect(res['ok'], isTrue, reason: 'answer:submit failed: $res');
  }

  void dispose() => socket.dispose();
}

/// Ends a session left active by an earlier (failed) run, so "Present" opens a fresh waiting room.
Future<void> endLeftoverSession() async {
  final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBase));
  final login = await dio.post<Map<String, dynamic>>(
    '/auth/login',
    data: {'email': 'demo@classpluse.app', 'password': 'Password123!'},
  );
  final token = login.data!['token'] as String;
  final auth = Options(headers: {'Authorization': 'Bearer $token'});
  final list = await dio.get<List<dynamic>>('/presentations', options: auth);
  final loops = list.data!.cast<Map<String, dynamic>>().firstWhere((p) => p['title'] == 'POP Lecture 4: Loops');
  final s = await dio.post<Map<String, dynamic>>('/sessions', data: {'presentationId': loops['id']}, options: auth);
  if (s.data!['resumed'] != true) {
    // Freshly created WAITING session: fine to reuse.
    return;
  }
  final connected = Completer<void>();
  final socket = SessionSocket.runGuarded<io.Socket>(() => io.io(
    AppConfig.serverUrl,
    io.OptionBuilder().setTransports(['websocket']).setAuth({'token': token, 'sessionId': s.data!['sessionId']}).enableForceNew().build(),
  ))..onConnect((_) => connected.isCompleted ? null : connected.complete());
  await connected.future.timeout(const Duration(seconds: 10));
  final done = Completer<void>();
  socket.emitWithAck('session:end', <String, dynamic>{}, ack: (dynamic _) => done.complete());
  await done.future.timeout(const Duration(seconds: 10));
  socket.dispose();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(endLeftoverSession);

  testWidgets('lecturer logs in, presents, two students answer, results and pulse update live, summary', (tester) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    final students = [SimStudent(), SimStudent()];
    addTearDown(() {
      for (final s in students) {
        try {
          s.dispose();
        } catch (_) {}
      }
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const ClassPluseApp(),
    ));

    // Welcome → login
    await pumpUntil(tester, find.byKey(const ValueKey('welcome-teacher')));
    await tester.tap(find.byKey(const ValueKey('welcome-teacher')));
    await pumpUntil(tester, find.byKey(const ValueKey('login-email')));
    await tester.enterText(find.byKey(const ValueKey('login-email')), 'demo@classpluse.app');
    await tester.enterText(find.byKey(const ValueKey('login-password')), 'Password123!');
    await tester.tap(find.byKey(const ValueKey('login-submit')));

    // Home → presentation → Present
    await pumpUntil(tester, find.text('POP Lecture 4: Loops'));
    await tester.tap(find.text('POP Lecture 4: Loops').first);
    await pumpUntil(tester, find.byKey(const ValueKey('present')));
    await pumpUntil(tester, find.textContaining('Is a string a primitive type?'));
    await tester.tap(find.byKey(const ValueKey('present')));

    // Waiting room: QR + code
    await pumpUntil(tester, find.byKey(const ValueKey('session-code')));
    expect(find.byKey(const ValueKey('session-qr')), findsOneWidget);
    final code = tester.widget<Text>(find.byKey(const ValueKey('session-code'))).data!.replaceAll(' ', '');
    expect(code, matches(RegExp(r'^\d{6}$')));

    // Two students join → live count
    for (final s in students) {
      await s.join(code);
    }
    await pumpUntil(tester, find.text('2 students joined'));

    // Start
    await tester.tap(find.byKey(const ValueKey('start-lecture')));
    await pumpUntil(tester, find.byKey(const ValueKey('next-slide')));
    expect(find.text('Is a string a primitive type?'), findsOneWidget);
    await pumpUntil(tester, find.text('0 answered'));

    // Students answer → bars and answered count update live
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (students.any((s) => s.currentSlide == null) && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await students[0].answer(0); // Yes
    await students[1].answer(2); // Depends on the language
    await pumpUntil(tester, find.text('2 answered'));
    expect(find.bySemanticsLabel(RegExp(r'^Yes: 50%, 1 response')), findsOneWidget);

    // Confusion pulse
    await students[0].emit('pulse:set', {'state': 'FOLLOWING'});
    await students[1].emit('pulse:set', {'state': 'LOST'});
    // Broadcasts are throttled (300 ms), so wait for the final state rather than the first update.
    await pumpUntil(tester, find.text('Lost · 1'));
    expect(find.text('Following · 1'), findsOneWidget);
    expect(find.text('2 of 2 responded'), findsOneWidget);

    // Results hidden from students until toggled on
    expect(students[0].results, isEmpty);
    await tester.ensureVisible(find.byKey(const ValueKey('toggle-results')));
    await tester.tap(find.byKey(const ValueKey('toggle-results')));
    final end2 = DateTime.now().add(const Duration(seconds: 10));
    while (students[0].results.isEmpty && DateTime.now().isBefore(end2)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(students[0].results.last['answered'], 2);

    // Next slide (quiz) → Finish on the last slide → confirm → summary
    await tester.tap(find.byKey(const ValueKey('next-slide')));
    await pumpUntil(tester, find.text('Which loop always runs at least once?'));
    await students[0].answer(2); // do-while (correct)
    await pumpUntil(tester, find.text('1 answered'));
    await tester.tap(find.byKey(const ValueKey('finish-session')));
    await pumpUntil(tester, find.byKey(const ValueKey('confirm-dialog-ok')));
    await tester.tap(find.byKey(const ValueKey('confirm-dialog-ok')));

    await pumpUntil(tester, find.text('Participants'));
    expect(find.text('Responses'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // 2 + 1 responses
    expect(find.textContaining('100% correct'), findsOneWidget);
    expect(students.every((s) => s.ended), isTrue);
  });
}

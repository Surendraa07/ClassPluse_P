// Student join → answer flow against a running local server.
//
// Prerequisites: server running (`npm run dev` in apps/server) with the seed data loaded.
// Run on an Android emulator:   flutter test integration_test -d emulator-5554
// (Physical device: add --dart-define=API_URL=http://<your-LAN-IP>:4000)

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

/// Pumps until [finder] matches or [timeout] passes (the app has live sockets, so
/// pumpAndSettle is not suitable).
Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TimeoutException('Timed out waiting for $finder');
}

/// Lecturer side driven directly through the API + socket.
class LecturerDriver {
  late final Dio dio = Dio(BaseOptions(baseUrl: AppConfig.apiBase));
  late String token;
  late String sessionId;
  late String code;
  io.Socket? socket;
  final results = <Map<String, dynamic>>[];

  Future<void> startSession() async {
    final login = await dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': 'demo@classpluse.app', 'password': 'Password123!'},
    );
    token = login.data!['token'] as String;
    final auth = Options(headers: {'Authorization': 'Bearer $token'});
    final list = await dio.get<List<dynamic>>('/presentations', options: auth);
    final loops = list.data!.cast<Map<String, dynamic>>().firstWhere((p) => p['title'] == 'POP Lecture 4: Loops');
    final s = await dio.post<Map<String, dynamic>>('/sessions', data: {'presentationId': loops['id']}, options: auth);
    sessionId = s.data!['sessionId'] as String;
    code = s.data!['code'] as String;

    final connected = Completer<void>();
    socket = SessionSocket.runGuarded<io.Socket>(() => io.io(
      AppConfig.serverUrl,
      io.OptionBuilder().setTransports(['websocket']).setAuth({'token': token, 'sessionId': sessionId}).enableForceNew().build(),
    ))
      ..onConnect((_) => connected.isCompleted ? null : connected.complete())
      ..on('results:update', (d) => results.add(Map<String, dynamic>.from(d as Map)));
    await connected.future.timeout(const Duration(seconds: 10));
  }

  Future<Map<String, dynamic>> emit(String event, [Map<String, dynamic>? payload]) {
    final c = Completer<Map<String, dynamic>>();
    socket!.emitWithAck(event, payload ?? <String, dynamic>{}, ack: (dynamic r) => c.complete(Map<String, dynamic>.from(r as Map)));
    return c.future.timeout(const Duration(seconds: 10));
  }

  Future<void> close() async {
    if (socket != null) {
      try {
        await emit('session:end');
      } catch (_) {}
      socket!.dispose();
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('student joins with a code, answers, and the lecturer sees it', (tester) async {
    final lecturer = LecturerDriver();
    await lecturer.startSession();
    addTearDown(lecturer.close);

    // Also runnable without a phone: `flutter test integration_test -d flutter-tester` (desktop
    // test device; native storage is replaced by an in-memory store, network calls are real).
    final onTester = Platform.environment.containsKey('FLUTTER_TEST');
    if (onTester) {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const ClassPluseApp(),
    ));
    await pumpUntil(tester, find.byKey(const ValueKey('welcome-join')));

    // Welcome → Join
    await tester.tap(find.byKey(const ValueKey('welcome-join')));
    await pumpUntil(tester, find.byKey(const ValueKey('join-code')));

    // A wrong code first: error banner, digits kept.
    final wrong = lecturer.code == '000000' ? '000001' : '000000';
    for (final d in wrong.split('')) {
      await tester.tap(find.byKey(ValueKey('keypad-$d')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('join-submit')));
    await pumpUntil(tester, find.byKey(const ValueKey('join-error')));
    expect(find.text("We couldn't find that session"), findsOneWidget);

    // Clear and type the real code with the on-screen keypad.
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const ValueKey('keypad-delete')));
    }
    for (final d in lecturer.code.split('')) {
      await tester.tap(find.byKey(ValueKey('keypad-$d')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('join-submit')));

    // Waiting room
    await pumpUntil(tester, find.byKey(const ValueKey('youre-in')));
    expect(find.textContaining('1 student joined'), findsOneWidget);

    // Lecturer starts → first question appears.
    expect((await lecturer.emit('session:start'))['ok'], isTrue);
    await pumpUntil(tester, find.text('Is a string a primitive type?'));

    // Submit is disabled until an option is chosen.
    final submit = find.byKey(const ValueKey('submit-answer'));
    expect(tester.widget<FilledButton>(find.descendant(of: submit, matching: find.byType(FilledButton))).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('option-2'))); // "Depends on the language"
    await tester.pump();
    await tester.tap(submit);
    await pumpUntil(tester, find.byKey(const ValueKey('answer-recorded')));

    // Lecturer receives the aggregated result.
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (!lecturer.results.any((r) => r['answered'] == 1) && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(lecturer.results.any((r) => r['answered'] == 1), isTrue);

    // Change the answer before the lecturer moves on.
    await tester.tap(find.byKey(const ValueKey('option-0'))); // "Yes"
    await tester.pump();
    await tester.tap(submit);
    await pumpUntil(tester, find.byKey(const ValueKey('answer-recorded')));

    // Pulse tab: "I'm lost"
    await tester.tap(find.byKey(const ValueKey('tab-pulse')));
    await pumpUntil(tester, find.byKey(const ValueKey('pulse-lost')));
    await tester.tap(find.byKey(const ValueKey('pulse-lost')));
    await pumpUntil(tester, find.text('Recorded just now'));

    // Lecturer ends → "Thanks for joining".
    expect((await lecturer.emit('session:end'))['ok'], isTrue);
    await pumpUntil(tester, find.byKey(const ValueKey('thanks')));
    expect(find.byKey(const ValueKey('join-another')), findsOneWidget);

    // Summary has one "Yes" for the first question and one lost pulse.
    final summary = await lecturer.dio.get<Map<String, dynamic>>(
      '/sessions/${lecturer.sessionId}/summary',
      options: Options(headers: {'Authorization': 'Bearer ${lecturer.token}'}),
    );
    final q1 = (summary.data!['slides'] as List).first as Map;
    final yes = (q1['options'] as List).first as Map;
    expect(yes['label'], 'Yes');
    expect(yes['count'], 1);
    expect((summary.data!['pulse'] as Map)['lost'], 1);
  });
}

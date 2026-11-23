import 'package:classpluse/core/theme/app_theme.dart';
import 'package:classpluse/core/theme/tokens.dart';
import 'package:classpluse/widgets/code_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(CodeInputController c, {bool hasError = false, ValueChanged<String>? onCompleted}) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: CodeInput(controller: c, hasError: hasError, onCompleted: onCompleted, autofocus: true),
          ),
          const Spacer(),
          NumberKeypad(controller: c),
        ],
      ),
    ),
  );
}

String _digitAt(WidgetTester tester, int i) {
  final box = find.byKey(ValueKey('code-digit-$i'));
  final text = tester.widget<Text>(find.descendant(of: box, matching: find.byType(Text)));
  return text.data ?? '';
}

Color _borderColorAt(WidgetTester tester, int i) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(of: find.byKey(ValueKey('code-digit-$i')), matching: find.byType(AnimatedContainer)).first,
  );
  final deco = container.decoration! as BoxDecoration;
  return (deco.border! as Border).top.color;
}

void main() {
  group('CodeInputController', () {
    test('keeps only up to 6 digits', () {
      final c = CodeInputController();
      for (final d in '1234567'.split('')) {
        c.append(d);
      }
      expect(c.value, '123456');
      expect(c.isComplete, isTrue);
      c.append('x');
      expect(c.value, '123456');
    });

    test('setCode strips non-digits (QR / paste)', () {
      final c = CodeInputController()..setCode('482 913');
      expect(c.value, '482913');
      c.setCode('classpluse://join/1234567');
      expect(c.value, '123456');
    });
  });

  testWidgets('renders six empty boxes and fills them from the keypad', (tester) async {
    final c = CodeInputController();
    await tester.pumpWidget(_host(c));

    for (var i = 0; i < 6; i++) {
      expect(find.byKey(ValueKey('code-digit-$i')), findsOneWidget);
      expect(_digitAt(tester, i), '');
    }
    // First box is the active one.
    expect(_borderColorAt(tester, 0), AppColors.brand);

    for (final d in ['4', '8', '2']) {
      await tester.tap(find.byKey(ValueKey('keypad-$d')));
      await tester.pump();
    }
    expect(c.value, '482');
    expect(_digitAt(tester, 0), '4');
    expect(_digitAt(tester, 2), '2');
    expect(_digitAt(tester, 3), '');
    expect(_borderColorAt(tester, 3), AppColors.brand);
  });

  testWidgets('delete removes the last digit', (tester) async {
    final c = CodeInputController(text: '4829');
    await tester.pumpWidget(_host(c));
    await tester.tap(find.byKey(const ValueKey('keypad-delete')));
    await tester.pump();
    expect(c.value, '482');
    expect(_digitAt(tester, 3), '');
  });

  testWidgets('does not accept a 7th digit and fires onCompleted once', (tester) async {
    final c = CodeInputController();
    final completed = <String>[];
    await tester.pumpWidget(_host(c, onCompleted: completed.add));
    for (final d in ['1', '2', '3', '4', '5', '6', '7']) {
      await tester.tap(find.byKey(ValueKey('keypad-$d')));
      await tester.pump();
    }
    expect(c.value, '123456');
    expect(completed, ['123456']);
    expect(_digitAt(tester, 5), '6');
  });

  testWidgets('error state keeps the digits and shows red borders', (tester) async {
    final c = CodeInputController(text: '482915');
    await tester.pumpWidget(_host(c, hasError: true));
    expect(_digitAt(tester, 5), '5');
    for (var i = 0; i < 6; i++) {
      expect(_borderColorAt(tester, i), AppColors.danger);
    }
    // Correct the last digit.
    await tester.tap(find.byKey(const ValueKey('keypad-delete')));
    await tester.tap(find.byKey(const ValueKey('keypad-3')));
    await tester.pump();
    expect(c.value, '482913');
  });

  testWidgets('accepts hardware keyboard digits and backspace', (tester) async {
    final c = CodeInputController();
    await tester.pumpWidget(_host(c));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(c.value, '71');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(c.value, '7');
  });

  testWidgets('announces progress to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    final c = CodeInputController(text: '48');
    await tester.pumpWidget(_host(c));
    expect(find.bySemanticsLabel('Session code, 2 of 6 digits entered: 4 8'), findsOneWidget);
    expect(find.bySemanticsLabel('Delete last digit'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('keypad keys meet the 44pt touch target', (tester) async {
    final c = CodeInputController();
    await tester.pumpWidget(_host(c));
    final size = tester.getSize(find.byKey(const ValueKey('keypad-5')));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
  });
}

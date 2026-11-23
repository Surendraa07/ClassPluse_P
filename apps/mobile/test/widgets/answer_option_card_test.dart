import 'package:classpluse/core/theme/app_theme.dart';
import 'package:classpluse/core/theme/tokens.dart';
import 'package:classpluse/widgets/answer_option_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

void main() {
  testWidgets('shows the label and calls onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(AnswerOptionCard(label: 'do-while', selected: false, onTap: () => taps++)));
    expect(find.text('do-while'), findsOneWidget);
    await tester.tap(find.byType(AnswerOptionCard));
    expect(taps, 1);
  });

  testWidgets('is at least 64pt tall, even with long labels', (tester) async {
    await tester.pumpWidget(_wrap(AnswerOptionCard(label: 'Yes', selected: false, onTap: () {})));
    expect(tester.getSize(find.byType(AnswerOptionCard)).height, greaterThanOrEqualTo(64));

    await tester.pumpWidget(_wrap(AnswerOptionCard(
      label: 'A very long answer option that needs to wrap over more than one line on a phone screen',
      selected: false,
      onTap: () {},
    )));
    expect(tester.getSize(find.byType(AnswerOptionCard)).height, greaterThan(64));
  });

  testWidgets('selected state uses more than colour: check icon + bold label + thicker border', (tester) async {
    await tester.pumpWidget(_wrap(AnswerOptionCard(label: 'No', selected: false, onTap: () {})));
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    final unselected = tester.widget<Text>(find.text('No')).style!;

    await tester.pumpWidget(_wrap(AnswerOptionCard(label: 'No', selected: true, onTap: () {})));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    final selected = tester.widget<Text>(find.text('No')).style!;
    expect(selected.fontWeight, FontWeight.w600);
    expect(unselected.fontWeight, isNot(FontWeight.w600));

    final material = tester.widget<Material>(
      find.descendant(of: find.byType(AnswerOptionCard), matching: find.byType(Material)).first,
    );
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.side.width, 2);
    expect(shape.side.color, AppColors.brand);
    expect(material.color, AppColors.brandTint);
  });

  testWidgets('disabled card ignores taps', (tester) async {
    await tester.pumpWidget(_wrap(const AnswerOptionCard(label: 'Yes', selected: false, onTap: null)));
    await tester.tap(find.byType(AnswerOptionCard), warnIfMissed: false);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
  });

  testWidgets('exposes position, label and selected state to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(AnswerOptionCard(label: 'while', selected: true, onTap: () {}, index: 1, total: 3)));
    expect(
      tester.getSemantics(find.byType(AnswerOptionCard)),
      isSemantics(
        label: 'Option 2 of 3. while',
        isSelected: true,
        isButton: true,
        isInMutuallyExclusiveGroup: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}

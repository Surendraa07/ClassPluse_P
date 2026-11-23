import 'package:classpluse/core/theme/app_theme.dart';
import 'package:classpluse/core/theme/tokens.dart';
import 'package:classpluse/widgets/pulse_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two pulse buttons with "current state only" behaviour, like the student screen.
class _PulseHost extends StatefulWidget {
  const _PulseHost({required this.onSend});
  final ValueChanged<PulseKind> onSend;

  @override
  State<_PulseHost> createState() => _PulseHostState();
}

class _PulseHostState extends State<_PulseHost> {
  PulseKind? current;

  void _tap(PulseKind k) {
    if (current == k) return; // no spam: re-tapping the current state sends nothing
    setState(() => current = k);
    widget.onSend(k);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PulseButton(kind: PulseKind.following, selected: current == PulseKind.following, onTap: () => _tap(PulseKind.following)),
        const SizedBox(height: 16),
        PulseButton(kind: PulseKind.lost, selected: current == PulseKind.lost, onTap: () => _tap(PulseKind.lost)),
      ],
    );
  }
}

Widget _wrap(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

void main() {
  testWidgets('renders both labels with distinct icons', (tester) async {
    await tester.pumpWidget(_wrap(_PulseHost(onSend: (_) {})));
    expect(find.text("I'm following"), findsOneWidget);
    expect(find.text("I'm lost"), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.text('Selected'), findsNothing);
  });

  testWidgets('selecting shows a "Selected" tag and a filled colour', (tester) async {
    await tester.pumpWidget(_wrap(_PulseHost(onSend: (_) {})));
    await tester.tap(find.text("I'm lost"));
    await tester.pump();

    expect(find.text('Selected'), findsOneWidget);
    final lostMaterial = tester.widget<Material>(
      find.descendant(of: find.widgetWithText(PulseButton, "I'm lost"), matching: find.byType(Material)).first,
    );
    expect(lostMaterial.color, AppColors.danger);
  });

  testWidgets('only the current state counts: switching sends once per change, repeats send nothing', (tester) async {
    final sent = <PulseKind>[];
    await tester.pumpWidget(_wrap(_PulseHost(onSend: sent.add)));

    await tester.tap(find.text("I'm following"));
    await tester.pump();
    await tester.tap(find.text("I'm following"));
    await tester.tap(find.text("I'm following"));
    await tester.pump();
    await tester.tap(find.text("I'm lost"));
    await tester.pump();

    expect(sent, [PulseKind.following, PulseKind.lost]);
    expect(find.text('Selected'), findsOneWidget);
  });

  testWidgets('is a large touch target', (tester) async {
    await tester.pumpWidget(_wrap(PulseButton(kind: PulseKind.following, selected: false, onTap: () {})));
    final size = tester.getSize(find.byType(PulseButton));
    expect(size.height, greaterThanOrEqualTo(122));
  });

  testWidgets('screen readers get label, selected state and a hint', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(Column(children: [
      PulseButton(kind: PulseKind.following, selected: true, onTap: () {}),
      PulseButton(kind: PulseKind.lost, selected: false, onTap: () {}),
    ])));
    expect(
      tester.getSemantics(find.byType(PulseButton).first),
      isSemantics(label: "I'm following", isSelected: true, isButton: true, isInMutuallyExclusiveGroup: true),
    );
    expect(
      tester.getSemantics(find.byType(PulseButton).last),
      isSemantics(label: "I'm lost", isSelected: false, hint: 'Tell your teacher you are lost'),
    );
    handle.dispose();
  });

  testWidgets('disabled button does nothing', (tester) async {
    await tester.pumpWidget(_wrap(const PulseButton(kind: PulseKind.lost, selected: false, onTap: null)));
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
  });
}

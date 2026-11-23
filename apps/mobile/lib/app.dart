import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme/app_theme.dart';

class ClassPluseApp extends ConsumerWidget {
  const ClassPluseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ClassPluse',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      themeMode: ThemeMode.light, // dark mode is out of MVP scope
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) {
        // Respect the user's text size but cap it so layouts stay usable.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.6)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

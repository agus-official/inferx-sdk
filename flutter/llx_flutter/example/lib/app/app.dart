import 'package:flutter/material.dart';
import '../design_system/theme.dart';
import 'router.dart';

class LlxExampleApp extends StatelessWidget {
  const LlxExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LLX Flutter',
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.dark(),
      theme: AppTheme.light(),
      onGenerateRoute: AppRouter.onGenerateRoute,
      initialRoute: AppRouter.initialRoute,
    );
  }
}

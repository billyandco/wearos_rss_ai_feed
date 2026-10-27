import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'router/app_router.dart';

class WearRssApp extends StatelessWidget {
  const WearRssApp({super.key, required this.router});

  final AppRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AI Today',
      debugShowCheckedModeBanner: false,
      theme: buildWearTheme(),
      routerConfig: router.config(),
    );
  }
}

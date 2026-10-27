import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/router/app_router.dart';
import 'core/di/injection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();

  runApp(WearRssApp(router: AppRouter()));
}

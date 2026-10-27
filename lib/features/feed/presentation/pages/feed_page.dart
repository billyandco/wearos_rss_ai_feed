import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../bloc/feed_bloc.dart';
import '../bloc/feed_event.dart';
import '../widgets/feed_view.dart';

/// Route entry point: owns the bloc lifecycle for the single watch screen.
@RoutePage()
class FeedPage extends StatelessWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<FeedBloc>(
      create: (_) => sl<FeedBloc>()..add(const FeedStarted()),
      child: const FeedView(),
    );
  }
}

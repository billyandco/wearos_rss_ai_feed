import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../layout/round_geometry.dart';

/// A vertical list whose rows are inset so they follow the circular display.
///
/// Items use a fixed [itemExtent] so each row's distance from the screen centre
/// is known while scrolling; that distance drives the horizontal inset.
class CurvedListView extends StatefulWidget {
  const CurvedListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.itemExtent,
    this.topPadding = 0,
    this.bottomPadding = 0,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double itemExtent;
  final double topPadding;
  final double bottomPadding;

  @override
  State<CurvedListView> createState() => _CurvedListViewState();
}

class _CurvedListViewState extends State<CurvedListView> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final radius =
            math.min(constraints.maxWidth, constraints.maxHeight) / 2;
        final screenCenter = constraints.maxHeight / 2;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final scrollOffset = _controller.hasClients
                ? _controller.offset
                : 0.0;

            return ListView.builder(
              key: const Key('feed-list'),
              controller: _controller,
              padding: EdgeInsets.only(
                top: widget.topPadding,
                bottom: widget.bottomPadding,
              ),
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              itemExtent: widget.itemExtent,
              itemCount: widget.itemCount,
              itemBuilder: (context, index) {
                final itemCenter =
                    widget.topPadding +
                    index * widget.itemExtent +
                    widget.itemExtent / 2 -
                    scrollOffset;
                // Keep a minimum content width: rows at the very top/bottom
                // of the circle are clipped by the round display, and letting
                // their width collapse would make the row's metadata overflow.
                final maxInset = math.max(
                  0.0,
                  (constraints.maxWidth - 128) / 2,
                );
                final inset = math.min(
                  roundHorizontalInset(
                    distanceFromCenter: itemCenter - screenCenter,
                    radius: radius,
                  ),
                  maxInset,
                );

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  child: widget.itemBuilder(context, index),
                );
              },
            );
          },
        );
      },
    );
  }
}

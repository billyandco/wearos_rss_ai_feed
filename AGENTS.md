# AGENTS.md — working guide for this repo

AI Today: a single-screen Flutter RSS reader for the Pixel Watch 1 (round
panel; **192 dp** logical at dpr 2). Merges 8 AI news feeds into a today-only
list capped at 20, cached in Hive, plus a local saved-articles store; tap opens
a detail page, double-tap sends the link to the paired phone, and tapping the
`TODAY` pill switches the list to `SAVED`. See `README.md` for the full picture.

## Canvas facts (do not mix these up)

| Context | Logical size | Why |
| --- | --- | --- |
| Real watch | **192 dp** (dpr 2 → 384 px framebuffer) | `screencap` returns 384×384; the detail page's `0.06·d` insets measure 11.5 dp there |
| Interaction/widget tests | 450 dp (`physicalSize 450²`, dpr 1) | fast, tap-target-friendly; **does not** reproduce round-chord clipping |
| Golden tests | **192 dp** (384² @ dpr 2) | the design acceptance artifact — must match the device |

A layout can pass at 450 dp and overflow at 192 dp (it already happened: the
saved empty state overflowed by 8 dp and its title sat under the pill). Any new
screen must get a 192 dp golden.

## Toolchain

- **Always use `fvm`** — never bare `flutter`/`dart`: `fvm flutter test`,
  `fvm flutter analyze`, `fvm dart format`, `fvm dart run build_runner build`.
  Pinned Flutter 3.47.7 / Dart 3.13.5 (`.fvmrc`).
- Release for the watch is 32-bit ARM: `fvm flutter build apk --release
  --target-platform android-arm` → `build/app/outputs/flutter-apk/app-release.apk`.

## Before you finish

1. `fvm flutter test` — all **240** must pass. **Never edit a test to make it
   pass**; a red test is a contract — report it and stop. The 8 golden
   comparisons are part of that count.
2. `fvm flutter analyze` — must be clean.
3. `fvm dart format --set-exit-if-changed lib test` — must report 0 changed.
4. If you changed a screen, regenerate the goldens
   (`fvm flutter test test/goldens --update-goldens`), re-run them **without**
   the flag twice to prove determinism, and say which PNGs changed and why.
   Goldens need the SDK's `material_fonts` artifact
   (`$FLUTTER_ROOT/bin/cache/artifacts/material_fonts/`); `test/goldens/golden_fonts.dart`
   resolves it via `FLUTTER_ROOT` or the `dart` executable path.
5. Update `README.md` if you changed behaviour: feature list, round-screen
   numbers, test count, verification status.

## Architecture (short)

`FeedView → FeedBloc → use cases → ArticleRepository / SavedArticleRepository
(domain)`; the data layer implements them with Dio / Hive / MethodChannel.
Domain imports no Flutter. `app_router.gr.dart` is committed — regenerate with
build_runner after touching routes (adding a route arg counts). DI lives in one
`get_it` container (`sl`); tests use fakes in `test/support/`, injectable
clocks, and the canvas noted above. The saved store is a second Hive key
(`saved_articles`) in the **same** box as the feed cache (`today_articles`).

## Conventions

- Colours come from `core/theme/app_theme.dart` (`kWear*` + `buildWearTheme`).
  Black backdrop is load-bearing (OLED + transition flash, below).
- Keep widgets small, stateless where possible; header-only rebuilds go
  through `ValueNotifier` + `ValueListenableBuilder`, never `setState` on the
  page for scroll-driven UI.
- No new runtime dependencies without asking. Match the existing style
  (doc comments on public widgets, `const` where possible).

## Hard-won gotchas (all verified on hardware or by probe)

1. `RefreshIndicator` only arms when `metrics.extentBefore == 0` at drag
   start — the list must rest at scroll offset 0 (`feed_view.dart`).
2. `GestureDetector` with both `onTap` + `onDoubleTap` delays the tap ~300 ms;
   rows use `InkWell` inside `Material` for instant ripple, tests pump 400 ms
   after a single tap. Fast double-taps can't be synthesized with
   `adb shell input tap`.
3. Android's default zoom page transition snapshots the entering route and
   flashes white — the theme pins `FadeForwardsPageTransitionsBuilder` with
   `kWearBackground` for **all six** `TargetPlatform` values
   (`app_theme.dart`, pinned by `test/core/theme/app_theme_test.dart`).
4. No elevated widgets exist in the app, so nothing paints a shadow;
   `colorScheme.shadow` is black and `surfaceTint` is still the M3 default
   (harmless until something gets elevation).
5. Header visibility is driven by `ScrollNotification`s; reset it when the
   article list is replaced or it can stick hidden (`_resetHeader`).
6. `onRefresh` subscribes to the bloc's idle state **before** dispatching,
   with a 120 s timeout (above the 15 s connect / 90 s read budget).
7. Hero tags are `'article-hero-${article.identity}'` on both ends; `identity`
   (guid ‖ link) is unique per the merger, so no duplicate-hero crashes.
8. Flat `ListView.builder` with fixed `itemExtent` — a previous
   `ListWheelScrollView` was removed for scroll feel and per-frame cost.
9. `screenrecord` is refused on the watch (`INVALID_LAYER_STACK`); verify UI
   with `screencap` (+ `KEYCODE_WAKEUP` first, screen sleeps fast).
10. `adb` hygiene: mDNS entries go stale and pairing ports rotate — re-pair
    when refused; `uiautomator dump` returns empty text under Flutter; revert
    `stayon` / `screen_off_timeout` after testing.
11. Saved articles are a second key (`saved_articles`) in the **same** Hive box.
    Never `box.clear()` and never write the other key: both directions are
    pinned by tests, and clobbering `today_articles` would wipe the feed.
12. TODAY and SAVED must never be in the widget tree at the same time — both
    lists use `article-hero-${identity}` and a duplicate tag crashes any push.
    `_FeedBody` switches between them; do not "optimise" this into an
    `IndexedStack`/`PageView`.
13. A section switch must reset both the header and the scroll position: the
    lists carry different keys (`feed-list` / `saved-list`), and
    `_resetHeader()` clears `_lastPixels` — without it the header sticks faded
    and the next scroll delta jumps.
14. In SAVED the header is **pinned** (it is the only mode indicator and the
    only way back) and sits on a full-width 45 dp black scrim; without the scrim
    a scrolled row is sliced by the pill's corner arc and leaves a glyph speck
    above it. TODAY keeps fade-on-scroll.
15. `SnackBarAction` resolves to `colorScheme.inversePrimary` (`#6750A4`,
    **2.87:1** on `kWearSurface`) unless the theme overrides
    `actionTextColor` — it does (`kWearAccent`, 12.3:1). Floating snackbars also
    need the `insetPadding` bottom (52 dp) or their corners fall outside the
    circle's chord.
16. Golden tests only mean something with real fonts: without loading
    `material_fonts` every glyph renders as a box. Register Roboto +
    MaterialIcons for the golden file only (a global `flutter_test_config.dart`
    would change text metrics for all 232 interaction tests).
17. `InkWell` with `onTap` + `onDoubleTap` + `onLongPress` works, but only the
    saved rows pass `onLongPress`; TODAY rows must keep exactly two gestures.
    Saved rows also carry their own semantics hint, since a long-press has no
    visual affordance.

## Device cheat sheet

```bash
adb pair <watch-ip>:<pair-port> <code>
adb connect <watch-ip>:<debug-port>
adb -s <device> install -r build/app/outputs/flutter-apk/app-release.apk
adb -s <device> shell am start -n com.wearrss.wearos_rss_ai_feed/.MainActivity
adb -s <device> shell input keyevent KEYCODE_WAKEUP
adb -s <device> exec-out screencap -p > /tmp/watch.png
```

# AGENTS.md — working guide for this repo

AI Today: a single-screen Flutter RSS reader for the Pixel Watch 1 (round
450 × 450). Merges 7 AI news feeds into a today-only list capped at 20, cached
in Hive; tap opens a detail page, double-tap sends the link to the paired
phone. See `README.md` for the full picture.

## Toolchain

- **Always use `fvm`** — never bare `flutter`/`dart`: `fvm flutter test`,
  `fvm flutter analyze`, `fvm dart format`, `fvm dart run build_runner build`.
  Pinned Flutter 3.47.7 / Dart 3.13.5 (`.fvmrc`).
- Release for the watch is 32-bit ARM: `fvm flutter build apk --release
  --target-platform android-arm` → `build/app/outputs/flutter-apk/app-release.apk`.

## Before you finish

1. `fvm flutter test` — all 130 must pass. **Never edit a test to make it
   pass**; a red test is a contract — report it and stop.
2. `fvm flutter analyze` — must be clean.
3. `fvm dart format --set-exit-if-changed lib test` — must report 0 changed.
4. Update `README.md` if you changed behaviour: feature list, round-screen
   numbers, test count, verification status.

## Architecture (short)

`FeedView → FeedBloc → use cases → ArticleRepository (domain)`; data layer
implements it with Dio / Hive / MethodChannel. Domain imports no Flutter.
`app_router.gr.dart` is committed — regenerate with build_runner after touching
routes. DI lives in one `get_it` container (`sl`); tests use fakes in
`test/support/`, injectable clocks, and a 450 × 450 `tester.view`.

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

## Device cheat sheet

```bash
adb pair <watch-ip>:<pair-port> <code>
adb connect <watch-ip>:<debug-port>
adb -s <device> install -r build/app/outputs/flutter-apk/app-release.apk
adb -s <device> shell am start -n com.wearrss.wearos_rss_ai_feed/.MainActivity
adb -s <device> shell input keyevent KEYCODE_WAKEUP
adb -s <device> exec-out screencap -p > /tmp/watch.png
```

# AI Today — a Wear OS RSS reader

A single-screen Flutter app for the **Pixel Watch 1** (450 × 450 round, 1.2")
that merges seven AI news feeds into one today-only list. Double-tap an article
and it opens in the browser of the paired phone.

Built with a strict Clean Architecture split, BLoC, get_it, auto_route, dio,
hive_ce and `package:xml`, using **fvm / Flutter 3.47.7**.

## Features

- **One merged list, newest first** across The Decoder, TechCrunch AI, OpenAI
  News, Hugging Face Blog, Interconnects, MIT Tech Review AI and Ars Technica
  AI.
- **Today only**: at fetch time, items outside the device-local calendar day are
  dropped — in the parser isolate, before they reach the UI or the cache.
- **Deduplicated** by guid, falling back to link, keeping the newest copy.
- **Double-tap to open on the phone** via AndroidX `RemoteActivityHelper`
  (`ACTION_VIEW` + `CATEGORY_BROWSABLE`), with a snackbar when the phone cannot
  be reached.
- **Round-screen UI**: curved list insets computed from the screen radius, true
  black OLED background, 116 dp rows, 48 dp header tap target, two-line title
  and summary.
- **Offline-friendly**: last successful fetch is cached in Hive and shown
  immediately (as-is) while the refresh runs.
- **Resilient**: a single broken feed does not blank the screen; only a total
  failure shows the retry state. A corrupt cache is treated as empty.

## Stack

| Concern | Choice |
| --- | --- |
| SDK | fvm, Flutter 3.47.7 (pinned in `.fvmrc`) |
| State | `flutter_bloc` |
| DI | `get_it` (single `sl` container) |
| Navigation | `auto_route` (+ generated `app_router.gr.dart`) |
| HTTP | `dio` |
| Cache | `hive_ce` / `hive_ce_flutter` |
| XML | `xml` |
| Codegen | `build_runner`, `auto_route_generator` (dev only) |

No additional runtime packages were added. `path_provider` and
`cupertino_icons` from the Flutter template were removed: hive_ce_flutter brings
its own storage-path dependency, and no Cupertino icon is used.

## Architecture

```
lib/
├── main.dart                      # bootstrap: DI, then runApp
├── app/
│   ├── app.dart                   # MaterialApp.router + theme
│   └── router/app_router.dart     # auto_route config (+ .gr.dart)
├── core/
│   ├── di/injection.dart          # get_it graph
│   ├── network/dio_client.dart    # timeouts, UA, plain-text responses
│   ├── errors/feed_failure.dart   # sealed failure types
│   ├── layout/round_geometry.dart # pure circular inset maths
│   ├── theme/app_theme.dart       # OLED dark theme
│   ├── utils/relative_time.dart   # now / 7m / 3h / 2d
│   └── widgets/curved_list_view.dart
└── features/feed/
    ├── domain/                    # pure Dart, inward-most
    │   ├── entities/              # Article, FeedSource
    │   ├── repositories/          # abstract ArticleRepository, RemoteArticleOpener
    │   ├── services/              # ArticleMerger (day filter, dedupe, sort)
    │   └── usecases/              # LoadCachedArticles, RefreshTodayArticles, OpenArticleOnPhone
    ├── data/
    │   ├── datasources/           # Dio remote source, Hive cache, MethodChannel opener
    │   ├── models/                # ArticleModel JSON DTO
    │   ├── services/              # RSS parser + isolate, RFC 822 date parser
    │   ├── repositories/          # ArticleRepositoryImpl
    │   └── feed_sources.dart      # const kFeedSources (7 feeds)
    └── presentation/
        ├── bloc/                  # FeedBloc / FeedEvent / FeedState
        ├── pages/feed_page.dart   # @RoutePage, owns the bloc
        └── widgets/               # FeedView, ArticleTile
```

Dependency arrows point inward only:

```
FeedView → FeedBloc → use cases → ArticleRepository (domain interface)
                                        ↑
                          ArticleRepositoryImpl (data) → Dio / Hive / platform channel
```

The domain layer imports no Flutter, Dio, Hive or Android code. Tests exercise it
without mocks of those packages.

### Fetch flow

1. `FeedPage` creates `FeedBloc` and dispatches `FeedStarted`.
2. Bloc emits `loading`, reads the Hive cache and shows it immediately if present
   (no re-filtering: cached results are returned as-is).
3. Bloc dispatches `FeedRefreshRequested`. The repository asks the remote source
   for all seven feeds **in parallel** (15 s connect / 90 s read timeouts).
4. Each feed is parsed by `parseFeedXml` inside `compute()` — OpenAI (~1,300
   items) and Hugging Face (~900 items) never block the UI isolate. The parser
   keeps only items on the current local day, normalizes dates to local time,
   strips HTML, caps descriptions at 400 characters and skips broken items.
5. `ArticleMerger` applies the domain rules again (defensive): today-only,
   dedupe by guid→link, newest first with deterministic title tie-break.
6. The merged list is written to Hive and emitted as `ready`.
7. Double-tap dispatches `FeedArticleOpened`; `OpenArticleOnPhone` validates the
   URL and calls the MethodChannel, implemented with `RemoteActivityHelper` in
   `MainActivity.kt`.

If every feed fails, a `FeedUnavailableFailure` is shown. If some succeed, their
articles are used. A failed refresh leaves the previous cache untouched.

## Round-screen design

- The content circle radius is derived from the shorter viewport side.
- Every row computes `roundHorizontalInset(distanceFromCenter, radius)`, so rows
  near the top and bottom of the circle are narrower; rows at the centre get a
  12 dp gutter. The maths is unit-tested independently of Flutter.
- Fixed 116 dp row height gives ~3.4 visible articles and a large touch target.
- Header sits at the circle's top: `TODAY`, a 48 dp refresh target, and an
  inline one-line error strip when cached rows are still visible.
- No status/navigation bar chrome; black window background from launch.

## Android / Wear OS integration

- `MainActivity.kt` registers MethodChannel
  `com.wearrss.wearos_rss_ai_feed/remote_activity` with method `openOnPhone`.
- Kotlin builds `Intent(ACTION_VIEW, uri)` with `CATEGORY_BROWSABLE`, calls
  `RemoteActivityHelper(applicationContext, mainExecutor).startRemoteActivity(intent, null)`
  (no target node id → paired phone) and completes the Dart future on success or
  failure.
- Dependency: `androidx.wear:wear-remote-interactions:1.2.0` (stable per the
  AndroidX Wear release notes).
- Manifest: `INTERNET` (the watch fetches feeds), watch hardware feature,
  `com.google.android.wearable.standalone=false` (opening articles requires the
  paired phone), launcher activity, black launch/normal themes.
- `minSdk = 30` (Wear OS 3, the Pixel Watch 1 baseline).
- A `<queries>` entry is not required for the remote hand-off: the intent is
  resolved on the phone, not on the watch.
- Sources: AndroidX Wear release notes
  <https://developer.android.com/jetpack/androidx/releases/wear>,
  RemoteActivityHelper reference
  <https://developer.android.com/reference/androidx/wear/remote/interactions/RemoteActivityHelper>,
  standalone-vs-non-standalone guidance
  <https://developer.android.com/training/wearables/apps/standalone-apps>.

## Commands

```bash
fvm install
fvm flutter pub get
fvm dart run build_runner build        # regenerates app_router.gr.dart
fvm flutter test
fvm flutter analyze
fvm flutter build apk --debug
# Pixel Watch 1: 32-bit armeabi-v7a, release/AOT build (~15 MB)
fvm flutter build apk --release --target-platform android-arm --split-per-abi
# -> build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
```

Running on a watch:

```bash
# Enable developer options + wireless debugging on the watch, pair it, then:
adb pair <watch-ip>:<pair-port>
adb connect <watch-ip>:<debug-port>
fvm flutter devices
fvm flutter run -d <watch-device-id>
```

## Tests

Tests are the contracts each implementation had to satisfy. The data, BLoC and
UI layers were written against failing tests; the domain rules were pinned with
unit tests in the same step. Suites are organised by layer:

| Suite | What it covers |
| --- | --- |
| `test/features/feed/domain` | Entity identity/equality and local-day checks; merge filter, dedupe, sort, tie-break, invalid items; use-case delegation and URL validation |
| `test/features/feed/data` | RFC 822/ISO dates (GMT, numeric offsets, named zones, two-digit years), parser normalization (CDATA, HTML, `content:encoded`, missing description/author, guid fallback), isolate parsing, 400-char cap, `FeedRemoteDataSource` partial/all failure, Hive round-trip and corrupt-cache recovery, repository cache/no-overwrite failure rules, MethodChannel opener |
| `test/features/feed/presentation` | BLoC cached-first/refresh/failure/notice/one-refresh-at-a-time behaviour; widget rendering of source, relative time, title, null description, double-tap, retry and empty states at 450 × 450 |
| `test/core` | Relative time, circular inset geometry, get_it graph wiring across all 7 sources |

Supporting test utilities: fake `HttpClientAdapter`, RSS XML builder with
timezone-independent dates, article factory, fake repository/opener, and
MethodChannel mocking. Fixtures mirror real feed shapes (WordPress `+0000`
dates, `dc:creator`, CDATA HTML, Hugging Face items with no description/author).

Deterministic-time strategy: use cases receive `now` from the bloc's injectable
clock; the UI receives the same clock; the parser receives the fetch time.

## Verification status

Verified in this workspace with Flutter 3.47.7 / Dart 3.13.5:

- `fvm flutter test` — **99 tests pass**.
- `fvm flutter analyze` — **no issues**.
- `fvm dart format` — clean.
- `fvm flutter build apk --debug` — **succeeds** (Gradle 9.3.1, AGP 9.1.0,
  Kotlin 2.4.0). Artifact: `build/app/outputs/flutter-apk/app-debug.apk`
  (ignored by Git).
- **Pixel Watch 1 release APK** — `app-armeabi-v7a-release.apk`, 15.2 MB,
  AOT release build with tree-shaken icons, only `armeabi-v7a` native code
  (the original Pixel Watch is 32-bit), `minSdkVersion=30`,
  `targetSdkVersion=36`, APK Signature Scheme v2 verified. It is signed with
  the Flutter template's debug key, so it is ready to sideload but needs a
  proper release keystore before Play upload.
- Packaged manifest inspected with `aapt2`: `minSdkVersion=30`,
  `targetSdkVersion=36`, `android.hardware.type.watch` feature, portrait
  activity, `INTERNET`, `com.google.android.wearable.standalone=false`, and
  `androidx.wear:wear-remote-interactions:1.2.0` resolved by Gradle.

The APK requires an Android SDK with API 36 + build-tools 36 and JDK 21; unit
and widget tests do not need the Android SDK.

### Known limitations

- No physical Pixel Watch / paired phone was available in this environment, so
  the phone hand-off was verified by compiling the Android app, testing the Dart
  platform-channel contract, and reviewing the documented platform API — not by
  a live double-tap on hardware.
- Refresh happens on launch and on demand; there is no background sync (Wear OS
  restricts background work).
- The watch shows headlines only; reading happens in the phone browser.
- "Today" is the device-local calendar day at fetch time. Cached articles are
  intentionally not re-filtered until the next successful fetch, per the
  requirement.
- Descriptions are converted to plain text and capped at 400 characters; author
  is stored but not shown, to keep rows readable at 1.2".
- The delivered release APK is debug-signed for sideloading; a Play upload needs
  your own release keystore and, per the 2026 Wear OS rule, both 32-bit and
  64-bit native code for new Play releases.

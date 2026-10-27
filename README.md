# AI Today — a Wear OS RSS reader

A Flutter app for the **Pixel Watch 1** (450 × 450 round, 1.2") that merges
seven AI news feeds into one today-only list. Tap an article to read it in full
on the watch; double-tap it to open it in the browser of the paired phone.

Built with a strict Clean Architecture split, BLoC, get_it, auto_route, dio,
hive_ce and `package:xml`, using **fvm / Flutter 3.47.7**.

## Features

- **One merged list, newest first** across The Decoder, TechCrunch AI, OpenAI
  News, Hugging Face Blog, Interconnects, MIT Tech Review AI and Ars Technica
  AI — capped at the **20 newest** (`kMaxFeedArticles`).
- **Today only**: at fetch time, items outside the device-local calendar day are
  dropped — in the parser isolate, before they reach the UI or the cache.
- **Deduplicated** by guid, falling back to link, keeping the newest copy.
- **Tap to read on the watch**: a single tap opens a detail page with the
  full title and untruncated summary via a shared-element `Hero` transition.
- **Double-tap to open on the phone** via AndroidX `RemoteActivityHelper`
  (`ACTION_VIEW` + `CATEGORY_BROWSABLE`), with a snackbar when the phone cannot
  be reached. Rows use an `InkWell`, so the press ripple appears on tap-down
  instead of after the double-tap window.
- **Round-screen UI**: flat `ListView.builder` feed with fixed 116 dp rows,
  true black OLED background, two-line title and summary.
- **Offline-friendly**: last successful fetch is cached in Hive and shown
  immediately (as-is) while the refresh runs.
- **Resilient**: a single broken feed does not blank the screen; only a total
  failure shows the retry state. A corrupt cache is treated as empty.

## Feed sources

The list is curated and hardcoded (`lib/features/feed/data/feed_sources.dart`
— no source-management UI by design). All seven are fetched in parallel on
every refresh:

| Source | Feed URL |
| --- | --- |
| The Decoder | `https://the-decoder.com/feed/` |
| TechCrunch AI | `https://techcrunch.com/category/artificial-intelligence/feed/` |
| OpenAI News | `https://openai.com/news/rss.xml` |
| Hugging Face Blog | `https://huggingface.co/blog/feed.xml` |
| Interconnects | `https://www.interconnects.ai/feed` |
| MIT Tech Review AI | `https://www.technologyreview.com/topic/artificial-intelligence/feed/` |
| Ars Technica AI | `https://arstechnica.com/ai/feed/` |

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
│   ├── theme/app_theme.dart       # OLED dark theme
│   └── utils/relative_time.dart   # now / 7m / 3h / 2d
└── features/feed/
    ├── domain/                    # pure Dart, inward-most
    │   ├── entities/              # Article, FeedSource
    │   ├── repositories/          # abstract ArticleRepository, RemoteArticleOpener
    │   ├── services/              # ArticleMerger (day filter, dedupe, sort, 20-cap)
    │   └── usecases/              # LoadCachedArticles, RefreshTodayArticles, OpenArticleOnPhone
    ├── data/
    │   ├── datasources/           # Dio remote source, Hive cache, MethodChannel opener
    │   ├── models/                # ArticleModel JSON DTO
    │   ├── services/              # RSS parser + isolate, RFC 822 date parser
    │   ├── repositories/          # ArticleRepositoryImpl
    │   └── feed_sources.dart      # const kFeedSources (7 feeds)
    └── presentation/
        ├── bloc/                  # FeedBloc / FeedEvent / FeedState
        ├── pages/
        │   ├── feed_page.dart     # @RoutePage, owns the bloc
        │   └── article_detail_page.dart # @RoutePage, bezel-safe full article
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
   dedupe by guid→link, newest first with deterministic title tie-break, then
   capped at the 20 newest (`kMaxFeedArticles`). The same capped list is what
   gets cached and emitted.
6. The merged list is written to Hive and emitted as `ready`.
7. A double tap dispatches `FeedArticleOpened` — `OpenArticleOnPhone`
   validates the URL and calls the MethodChannel, implemented with
   `RemoteActivityHelper` in `MainActivity.kt`; a single tap pushes the detail
   page instead.

If every feed fails, a `FeedUnavailableFailure` is shown. If some succeed, their
articles are used. A failed refresh leaves the previous cache untouched.

## Round-screen design

- The feed is a flat `ListView.builder` with a fixed 116 dp row extent, so rows
  sit straight and scroll 1:1 with the finger.
- Each row keeps an 8 dp horizontal gutter so it never touches the display edge.
- Fixed 116 dp row height gives ~2.9 visible articles and a large touch target.
- The header (`TODAY` plus a one-line inline error strip) is overlaid on the top
  of the circle: an opaque black pill, so rows scrolling underneath never show
  through the text. The list starts below it (`48 dp`, or `72 dp` while the
  inline error is shown), so row 0 is never hidden. The header animates out when
  you scroll down, back in when you scroll up, and is always visible at the top
  of the list.
- Refresh is pull-to-refresh (`RefreshIndicator`) over the feed; the empty state
  keeps its own button because there is no list to pull.
- No status/navigation bar chrome; black window background from launch.
- The detail page is one scroll view (button travels with the content) with
  size-relative insets (6% sides, 5% top, 30% trailing space after the button),
  so the button can be scrolled up into the wide middle band of the circle.
- Page transitions are an explicit black fade on every platform
  (`FadeForwardsPageTransitionsBuilder(backgroundColor: kWearBackground)`):
  Android's default zoom transition snapshots the entering route and flashes
  white behind the hero flight.
- Custom launcher icon (all densities): mint `#6EE7C8` RSS disc on OLED black,
  drawn to stay inside the circular mask.

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

All Flutter/Dart commands go through fvm (never bare `flutter`):

```bash
fvm install
fvm flutter pub get
fvm dart run build_runner build        # regenerates app_router.gr.dart
fvm flutter test
fvm flutter analyze
fvm dart format --set-exit-if-changed lib test
# Pixel Watch 1: 32-bit armeabi-v7a, release/AOT build (~15.6 MB)
fvm flutter build apk --release --target-platform android-arm
# -> build/app/outputs/flutter-apk/app-release.apk
```

Running on a watch:

```bash
# Enable developer options + wireless debugging on the watch, pair it, then:
adb pair <watch-ip>:<pair-port> <code>
adb connect <watch-ip>:<debug-port>
adb -s <device> install -r build/app/outputs/flutter-apk/app-release.apk
adb -s <device> shell am start -n com.wearrss.wearos_rss_ai_feed/.MainActivity
```

## Tests

Tests are the contracts each implementation had to satisfy. The data, BLoC and
UI layers were written against failing tests; the domain rules were pinned with
unit tests in the same step. Suites are organised by layer:

| Suite | What it covers |
| --- | --- |
| `test/features/feed/domain` | Entity identity/equality and local-day checks; merge filter, dedupe, sort, tie-break, invalid items, 20-newest cap (after dedupe, tie-break respected); use-case delegation and URL validation |
| `test/features/feed/data` | RFC 822/ISO dates (GMT, numeric offsets, named zones, two-digit years), parser normalization (CDATA, HTML, `content:encoded`, missing description/author, guid fallback), isolate parsing, 400-char cap, `FeedRemoteDataSource` partial/all failure, Hive round-trip and corrupt-cache recovery, repository cache/no-overwrite failure rules, MethodChannel opener |
| `test/features/feed/presentation` | BLoC cached-first/refresh/failure/notice/one-refresh-at-a-time behaviour; widget rendering of source, relative time, title, null description, tap→detail navigation, double-tap→phone, retry and empty states at 450 × 450; the detail page (full description, hero tag, open-on-phone success/failure); header fade out on scroll-down / back on scroll-up / reset when the list is replaced; pull-to-refresh via a real drag gesture |
| `test/core` | Relative time; theme palette wiring and the black page-transition backdrop on all platforms; get_it graph wiring across all 7 sources |
| `test/app` | Router registers the feed (initial) and detail routes |

Supporting test utilities: fake `HttpClientAdapter`, RSS XML builder with
timezone-independent dates, article factory, fake repository/opener, and
MethodChannel mocking. Fixtures mirror real feed shapes (WordPress `+0000`
dates, `dc:creator`, CDATA HTML, Hugging Face items with no description/author).

Deterministic-time strategy: use cases receive `now` from the bloc's injectable
clock; the UI receives the same clock; the parser receives the fetch time.

## Verification status

Verified in this workspace with Flutter 3.47.7 / Dart 3.13.5:

- `fvm flutter test` — **130 tests pass**.
- `fvm flutter analyze` — **no issues**.
- `fvm dart format` — clean.
- `fvm flutter build apk --release --target-platform android-arm` —
  **succeeds** (Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0). Artifact:
  `build/app/outputs/flutter-apk/app-release.apk` (~15.6 MB, ignored by Git).
- **Physical Pixel Watch 1** — release APK installed and exercised on hardware
  (screenshots): feed renders at rest, header hides on scroll-down and returns
  on scroll-up, tap opens the detail page with the hero card, the "Open on
  phone" button scrolls with the article and fires the snackbar, back returns
  to the feed with scroll position preserved. Packaged manifest inspected with
  `aapt2`: `minSdkVersion=30`, `targetSdkVersion=36`,
  `android.hardware.type.watch` feature, portrait activity, `INTERNET`,
  `com.google.android.wearable.standalone=false`, and
  `androidx.wear:wear-remote-interactions:1.2.0` resolved by Gradle.

The APK requires an Android SDK with API 36 + build-tools 36 and JDK 21; unit
and widget tests do not need the Android SDK.

### Known limitations

- Refresh happens on launch and on demand; there is no background sync (Wear OS
  restricts background work).
- The watch shows the full summary on the detail page; the browser on the phone
  is still where the article itself is read.
- "Today" is the device-local calendar day at fetch time. Cached articles are
  intentionally not re-filtered until the next successful fetch, per the
  requirement. On quiet days the list holds fewer than 20 articles by design
  (cap, not fill).
- Descriptions are converted to plain text and capped at 400 characters; author
  is stored but not shown, to keep rows readable at 1.2".
- The release APK is debug-signed for sideloading; a Play upload needs your own
  release keystore and, per the 2026 Wear OS rule, both 32-bit and 64-bit native
  code for new Play releases.

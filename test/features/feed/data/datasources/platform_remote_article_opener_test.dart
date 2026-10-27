import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/core/errors/feed_failure.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/datasources/platform_remote_article_opener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/remote_activity');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('sends the URL to the Wear OS RemoteActivityHelper channel', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    const opener = PlatformRemoteArticleOpener(channel: channel);

    await opener.openOnPhone(Uri.parse('https://example.com/article'));

    expect(calls, hasLength(1));
    expect(calls.single.method, 'openOnPhone');
    expect(calls.single.arguments, {'url': 'https://example.com/article'});
  });

  test(
    'throws RemoteOpenFailure when no phone app accepted the link',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      const opener = PlatformRemoteArticleOpener(channel: channel);

      await expectLater(
        opener.openOnPhone(Uri.parse('https://example.com/article')),
        throwsA(isA<RemoteOpenFailure>()),
      );
    },
  );

  test('wraps PlatformException as RemoteOpenFailure', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(
        code: 'open_failed',
        message: 'Phone not connected',
      ),
    );
    const opener = PlatformRemoteArticleOpener(channel: channel);

    await expectLater(
      opener.openOnPhone(Uri.parse('https://example.com/article')),
      throwsA(
        isA<RemoteOpenFailure>().having(
          (failure) => failure.message,
          'message',
          contains('Phone not connected'),
        ),
      ),
    );
  });

  test(
    'wraps a missing platform implementation as RemoteOpenFailure',
    () async {
      const opener = PlatformRemoteArticleOpener(
        channel: MethodChannel('test/remote_activity_not_registered'),
      );

      await expectLater(
        opener.openOnPhone(Uri.parse('https://example.com/article')),
        throwsA(isA<RemoteOpenFailure>()),
      );
    },
  );
}

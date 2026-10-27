import 'package:flutter/services.dart';

import '../../../../core/errors/feed_failure.dart';
import '../../domain/repositories/remote_article_opener.dart';

/// Bridges to Wear OS `RemoteActivityHelper` in `MainActivity.kt`.
class PlatformRemoteArticleOpener implements RemoteArticleOpener {
  const PlatformRemoteArticleOpener({this.channel = defaultChannel});

  static const String channelName =
      'com.wearrss.wearos_rss_ai_feed/remote_activity';
  static const String methodName = 'openOnPhone';

  /// Method name used by the Android side; kept public for the platform test.
  static const MethodChannel defaultChannel = MethodChannel(channelName);

  final MethodChannel channel;

  @override
  Future<void> openOnPhone(Uri url) async {
    try {
      final accepted = await channel.invokeMethod<bool>(methodName, {
        'url': url.toString(),
      });
      if (accepted != true) {
        throw const RemoteOpenFailure(
          'No app on your phone could open this link.',
        );
      }
    } on MissingPluginException catch (error) {
      throw RemoteOpenFailure(
        'Opening links on your phone is unavailable on this device.',
        cause: error,
      );
    } on PlatformException catch (error) {
      throw RemoteOpenFailure(
        error.message ?? 'Could not reach your phone.',
        cause: error,
      );
    }
  }
}

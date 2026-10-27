/// Base failure type shared by the data and domain layers.
///
/// The domain layer never imports networking or storage packages, so its
/// contracts are expressed with this lightweight, framework-free type.
sealed class FeedFailure implements Exception {
  const FeedFailure(this.message, {this.cause});

  /// A short message that is safe to display on a tiny watch screen.
  final String message;

  /// The underlying error, kept for logging/debugging only.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// A feed could not be downloaded or the device is offline.
final class FeedNetworkFailure extends FeedFailure {
  const FeedNetworkFailure(super.message, {super.cause});
}

/// A feed response could not be understood as RSS.
final class FeedParseFailure extends FeedFailure {
  const FeedParseFailure(super.message, {super.cause});
}

/// No feed could be loaded at all.
final class FeedUnavailableFailure extends FeedFailure {
  const FeedUnavailableFailure(super.message, {super.cause});
}

/// The local cache could not be read or written.
final class FeedCacheFailure extends FeedFailure {
  const FeedCacheFailure(super.message, {super.cause});
}

/// The phone could not be asked to open the article.
final class RemoteOpenFailure extends FeedFailure {
  const RemoteOpenFailure(super.message, {super.cause});
}

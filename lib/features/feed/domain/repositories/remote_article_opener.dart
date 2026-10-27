/// Opens an article's web page on the phone paired with the watch.
///
/// Wear OS exposes this through `RemoteActivityHelper`; the domain stays
/// platform agnostic and only sees this capability.
abstract interface class RemoteArticleOpener {
  /// Throws [RemoteOpenFailure] when the phone cannot be reached.
  Future<void> openOnPhone(Uri url);
}

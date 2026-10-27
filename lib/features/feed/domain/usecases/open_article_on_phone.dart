import '../../../../core/errors/feed_failure.dart';
import '../entities/article.dart';
import '../repositories/remote_article_opener.dart';

/// Asks the paired phone to open the article's link.
class OpenArticleOnPhone {
  const OpenArticleOnPhone(this._opener);

  final RemoteArticleOpener _opener;

  Future<void> call(Article article) async {
    final uri = Uri.tryParse(article.link.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const RemoteOpenFailure('This article has no valid link.');
    }
    await _opener.openOnPhone(uri);
  }
}

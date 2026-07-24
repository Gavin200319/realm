import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/news_article.dart';
import '../services/news_service.dart';
import '../services/supabase_service.dart';
import '../services/local_cache_service.dart';
import '../services/article_image_service.dart';
import '../services/generated_image_service.dart';
import '../theme/rm_theme.dart';
import '../widgets/news_card.dart';
import 'news_comments_sheet.dart';
import 'news_detail_screen.dart';
import 'news_redrop_sheet.dart';

/// The "Updates" side of the Realm tab's Drops/Updates toggle — real
/// news, syndicated from Kenyan outlets first (general + entertainment),
/// then Africa, then the rest of the world. Every card links back to
/// the original publisher; nothing here is stored or reproduced beyond
/// a headline and a short summary.
class UpdatesView extends StatefulWidget {
  const UpdatesView({super.key});

  @override
  State<UpdatesView> createState() => UpdatesViewState();
}

class UpdatesViewState extends State<UpdatesView> {
  static const _cacheKey = 'news_updates';

  List<NewsArticle> _articles = [];
  bool _loading = true;
  bool _offline = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCached();
    refresh();
  }

  Future<void> _loadCached() async {
    final cached = await LocalCacheService.instance.loadList(_cacheKey);
    if (cached != null && cached.isNotEmpty && mounted && _articles.isEmpty) {
      setState(() {
        _articles = cached.map(NewsArticle.fromMap).toList();
        _loading = false;
      });
    }
  }

  /// Called on pull-to-refresh, and whenever the Updates segment is
  /// (re)selected from [FeedScreen] — same "never sit on stale data"
  /// contract as the Drops feed.
  Future<void> refresh() async {
    if (_articles.isEmpty) setState(() { _loading = true; _error = null; });
    try {
      final articles = await NewsService.instance.latest();
      if (mounted) {
        setState(() {
          _articles = articles;
          _offline = false;
          _error = null;
        });
      }
      await LocalCacheService.instance
          .saveList(_cacheKey, articles.map((a) => a.toMap()).toList());
    } catch (e) {
      if (mounted) {
        if (_articles.isNotEmpty) {
          setState(() => _offline = true);
        } else {
          setState(() => _error = 'Could not load news right now.');
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openExternal(NewsArticle article) async {
    final uri = Uri.tryParse(article.link);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openDetail(NewsArticle article) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NewsDetailScreen(article: article)),
    );
  }

  Future<void> _openComments(NewsArticle article) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NewsCommentsSheet(article: article),
    );
  }

  Future<RedropOutcome?> _openRedropSheet(NewsArticle article) {
    return showModalBottomSheet<RedropOutcome>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NewsRedropSheet(article: article),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _articles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: RMColors.primary),
            SizedBox(height: 16),
            Text('Fetching the latest…',
                style: TextStyle(color: RMColors.textSecondary)),
          ],
        ),
      );
    }
    if (_error != null && _articles.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, color: RMColors.textHint, size: 48),
              SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: RMColors.textSecondary)),
              SizedBox(height: 20),
              OutlinedButton(onPressed: refresh, child: Text('Try again')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: RMColors.primary,
      backgroundColor: RMColors.surface,
      onRefresh: refresh,
      child: ListView.separated(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _articles.length + (_offline ? 1 : 0),
        separatorBuilder: (_, __) => SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (_offline && index == 0) {
            return Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: RMColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_rounded,
                      size: 16, color: RMColors.textHint),
                  SizedBox(width: 8),
                  Text('Offline — showing saved stories',
                      style: TextStyle(
                          color: RMColors.textSecondary, fontSize: 12)),
                ],
              ),
            );
          }
          final article = _articles[index - (_offline ? 1 : 0)];
          return _NewsCardWithCount(
            key: ValueKey(article.id),
            article: article,
            onOpenDetail: _openDetail,
            onOpenExternal: _openExternal,
            onOpenComments: _openComments,
            onOpenRedropSheet: _openRedropSheet,
          );
        },
      ),
    );
  }
}

/// Wraps [NewsCard] with a lazily-fetched comment count, resolved
/// once per card the same way [DropCard] lazily resolves its place
/// name — cheap, best-effort, and never blocks the card from showing.
class _NewsCardWithCount extends StatefulWidget {
  final NewsArticle article;
  final void Function(NewsArticle) onOpenDetail;
  final void Function(NewsArticle) onOpenExternal;
  final Future<void> Function(NewsArticle) onOpenComments;
  final Future<RedropOutcome?> Function(NewsArticle) onOpenRedropSheet;

  const _NewsCardWithCount({
    super.key,
    required this.article,
    required this.onOpenDetail,
    required this.onOpenExternal,
    required this.onOpenComments,
    required this.onOpenRedropSheet,
  });

  @override
  State<_NewsCardWithCount> createState() => _NewsCardWithCountState();
}

class _NewsCardWithCountState extends State<_NewsCardWithCount> {
  int? _count;
  int? _redropCount;
  bool _iRedropped = false;
  NewsArticle? _resolvedArticle;

  @override
  void initState() {
    super.initState();
    _loadCount();
    _loadRedropState();
    _resolveImageIfMissing();
  }

  @override
  void didUpdateWidget(_NewsCardWithCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.article.id != widget.article.id) {
      _resolvedArticle = null;
      _resolveImageIfMissing();
    }
  }

  Future<void> _loadCount() async {
    try {
      final count =
          await SupabaseService.instance.fetchNewsCommentCount(widget.article.link);
      if (mounted) setState(() => _count = count);
    } catch (_) {
      // Best-effort — the count pill just stays generic without it.
    }
  }

  Future<void> _loadRedropState() async {
    try {
      final results = await Future.wait([
        SupabaseService.instance.fetchNewsRedropCount(widget.article.link),
        SupabaseService.instance.fetchMyNewsRedrop(widget.article.link),
      ]);
      if (!mounted) return;
      setState(() {
        _redropCount = results[0] as int;
        _iRedropped = (results[1] as Map<String, dynamic>?) != null;
      });
    } catch (_) {
      // Best-effort, same contract as _loadCount above.
    }
  }

  /// If the feed didn't give us an image, first look one up from the
  /// story's own page (see [ArticleImageService]); if that also comes
  /// up empty, fall back to a generated illustration (see
  /// [GeneratedImageService], which is itself a no-op unless the
  /// person running this app has opted in with an API key). Same
  /// "cheap, best-effort, never blocks the card" contract throughout.
  Future<void> _resolveImageIfMissing() async {
    if (widget.article.imageUrl != null) return;
    try {
      final result =
          await ArticleImageService.instance.resolve(widget.article.link);
      if (result != null) {
        if (!mounted) return;
        setState(() {
          _resolvedArticle = widget.article.withResolvedImage(
            imageUrl: result.imageUrl,
            imageCredit: result.credit,
          );
        });
        return;
      }
    } catch (_) {
      // Fall through to the generated-illustration attempt below.
    }

    if (!GeneratedImageService.instance.shouldGenerate(widget.article)) {
      return;
    }
    try {
      final bytes =
          await GeneratedImageService.instance.generate(widget.article);
      if (bytes == null || !mounted) return;
      setState(() {
        _resolvedArticle = widget.article.withGeneratedImage(bytes);
      });
    } catch (_) {
      // No image, generated or otherwise — the card still works fine.
    }
  }

  Future<void> _handleRedrop() async {
    final outcome = await widget.onOpenRedropSheet(_resolvedArticle ?? widget.article);
    if (outcome == null || !mounted) return;
    if (outcome == RedropOutcome.sharedToStatus) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Shared to your status')));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Redropped')));
    }
    _loadRedropState();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolvedArticle ?? widget.article;
    return NewsCard(
      article: resolved,
      commentCount: _count,
      redropCount: _redropCount,
      iRedropped: _iRedropped,
      onOpenDetail: () => widget.onOpenDetail(resolved),
      onOpenExternal: () => widget.onOpenExternal(resolved),
      onOpenComments: () async {
        // Refresh the count once the sheet actually closes, in case
        // the person just added a comment. Passing the resolved
        // article through means the comments sheet's header (if it
        // shows one) also gets the story's image, same as the detail
        // screen and redrop sheet.
        await widget.onOpenComments(resolved);
        _loadCount();
      },
      onRedrop: _handleRedrop,
    );
  }
}

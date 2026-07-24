import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/news_article.dart';
import '../theme/rm_theme.dart';

/// The Updates-tab counterpart to [DropCard] — same rounded surface,
/// same border/spacing rhythm, so switching between Drops and Updates
/// doesn't feel like landing in a different app. Tapping the card
/// opens this app's own detail view (summary + comments + engagement)
/// rather than jumping straight out to the publisher; the "View full
/// story" link is the explicit way out to the original article.
/// Tapping the comment pill opens the comment thread directly, and
/// the redrop pill opens the redrop/share-to-status composer.
class NewsCard extends StatelessWidget {
  final NewsArticle article;
  final int? commentCount;
  final int? redropCount;
  final bool iRedropped;
  final VoidCallback onOpenDetail;
  final VoidCallback onOpenExternal;
  final VoidCallback onOpenComments;
  final VoidCallback onRedrop;

  const NewsCard({
    super.key,
    required this.article,
    required this.onOpenDetail,
    required this.onOpenExternal,
    required this.onOpenComments,
    required this.onRedrop,
    this.commentCount,
    this.redropCount,
    this.iRedropped = false,
  });

  Color get _tierColor {
    switch (article.tier) {
      case NewsTier.kenya:
        return RMColors.success;
      case NewsTier.africa:
        return RMColors.accent;
      case NewsTier.world:
        return RMColors.textSecondary;
    }
  }

  String get _tierLabel {
    switch (article.tier) {
      case NewsTier.kenya:
        return 'KENYA';
      case NewsTier.africa:
        return 'AFRICA';
      case NewsTier.world:
        return 'WORLD';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpenDetail,
      child: Container(
        decoration: BoxDecoration(
          color: RMColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: RMColors.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Source + tier badge ─────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: _tierColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      _tierLabel,
                      style: TextStyle(
                        color: _tierColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      article.category != null
                          ? '${article.sourceName} · ${article.category}'
                          : article.sourceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: RMColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    article.timeAgoLabel,
                    style: TextStyle(color: RMColors.textHint, fontSize: 12),
                  ),
                ],
              ),
            ),

            // ── Image ────────────────────────────────────────────
            if (article.imageUrl != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: article.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: RMColors.surfaceAlt),
                          errorWidget: (_, __, ___) =>
                              Container(color: RMColors.surfaceAlt),
                        ),
                        // Attribution line — only present for images
                        // we resolved ourselves from the story's own
                        // page (see ArticleImageService); a
                        // feed-supplied image doesn't need this since
                        // the publisher/source badge above already
                        // covers it.
                        if (article.imageCredit != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: EdgeInsets.fromLTRB(10, 14, 10, 6),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.55),
                                  ],
                                ),
                              ),
                              child: Text(
                                article.imageCredit!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              )
            else if (article.generatedImageBytes != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          article.generatedImageBytes!,
                          fit: BoxFit.cover,
                        ),
                        // Deliberately a solid, always-visible badge —
                        // not the same subtle bottom-gradient treatment
                        // as a real photo credit above. This image
                        // isn't a photo of the story; nothing about
                        // its presentation should let it read as one.
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding:
                                EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_awesome_rounded,
                                    size: 12, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'AI illustration',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            SizedBox(height: 12),

            // ── Headline + summary ───────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: RMColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 1.25,
                    ),
                  ),
                  if (article.summary != null) ...[
                    SizedBox(height: 6),
                    Text(
                      article.summary!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: RMColors.textSecondary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            Divider(height: 1, color: RMColors.border),

            // ── Actions: view full story / redrop / comments ──────
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: onOpenExternal,
                      icon: Icon(Icons.open_in_new_rounded,
                          size: 16, color: RMColors.primary),
                      label: Text(
                        'View full story',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: RMColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onRedrop,
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 8)),
                    icon: Icon(Icons.repeat_rounded,
                        size: 16,
                        color: iRedropped
                            ? RMColors.success
                            : RMColors.textSecondary),
                    label: Text(
                      redropCount == null || redropCount == 0
                          ? 'Redrop'
                          : '$redropCount',
                      style: TextStyle(
                          color: iRedropped
                              ? RMColors.success
                              : RMColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onOpenComments,
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 8)),
                    icon: Icon(Icons.mode_comment_outlined,
                        size: 16, color: RMColors.textSecondary),
                    label: Text(
                      commentCount == null || commentCount == 0
                          ? 'Comment'
                          : '$commentCount',
                      style: TextStyle(
                          color: RMColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/rm_theme.dart';

/// A soft, animated "blur-up" placeholder shown behind media while it
/// loads — a subtle pulsing gradient seen through a blur, classic
/// progressive-loading feel without needing a low-res thumbnail source.
class BlurPlaceholder extends StatefulWidget {
  final double? height;
  final IconData icon;

  BlurPlaceholder({super.key, this.height, this.icon = Icons.image_rounded});

  @override
  State<BlurPlaceholder> createState() => _BlurPlaceholderState();
}

class _BlurPlaceholderState extends State<BlurPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    RMColors.surfaceAlt,
                    Color.lerp(RMColors.primaryDim, RMColors.surfaceAlt,
                        _ctrl.value)!,
                    RMColors.surfaceAlt,
                  ],
                ),
              ),
            ),
          ),
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Center(
              child: Icon(widget.icon,
                  size: 40, color: RMColors.textHint.withOpacity(0.6)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps a network image with a blurred pulsing placeholder that
/// cross-fades into the loaded image once it arrives — the classic
/// "blur-up" progressive image loading pattern.
class BlurUpImage extends StatelessWidget {
  final String url;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  /// Decodes the image at this pixel width instead of its native
  /// resolution — cheap way to cut memory/CPU cost for thumbnails that
  /// never render anywhere near full size (e.g. feed cards). Leave
  /// null for full-resolution decoding (detail screens, galleries).
  final int? cacheWidth;
  /// When true (and [fit] is BoxFit.contain), the empty space left by
  /// showing the full, uncropped image is filled with a blurred,
  /// darkened copy of the same image rather than a flat background —
  /// so every card is the same size without ever hiding part of the
  /// photo or video thumbnail, and the letterbox bars still look
  /// intentional instead of like empty gaps.
  final bool letterboxFill;

  BlurUpImage({
    super.key,
    required this.url,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.cacheWidth,
    this.letterboxFill = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      memCacheWidth: cacheWidth,
      fadeInDuration: Duration(milliseconds: 400),
      progressIndicatorBuilder: (context, url, progress) => Stack(
        fit: StackFit.expand,
        children: [
          BlurPlaceholder(height: height, icon: Icons.image_rounded),
          if (progress.progress != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: 80,
                  child: LinearProgressIndicator(
                    value: progress.progress,
                    minHeight: 3,
                    backgroundColor: Colors.black26,
                    valueColor: AlwaysStoppedAnimation(RMColors.primary),
                  ),
                ),
              ),
            ),
        ],
      ),
      errorWidget: (context, url, error) => Container(
        height: height,
        color: RMColors.surfaceAlt,
        child: Center(
          child: Icon(Icons.broken_image_rounded,
              color: RMColors.textHint, size: 32),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: letterboxFill
            ? Stack(
                fit: StackFit.expand,
                children: [
                  // Decorative backdrop only — small mem-cache width
                  // since it's blurred into a soft smear anyway, and
                  // its own load/error states don't matter, the
                  // foreground image above carries those.
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      memCacheWidth: 120,
                    ),
                  ),
                  Container(color: Colors.black.withOpacity(0.28)),
                  Center(child: foreground),
                ],
              )
            : foreground,
      ),
    );
  }
}

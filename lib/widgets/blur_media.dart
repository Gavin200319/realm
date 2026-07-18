import 'dart:ui';
import 'package:flutter/material.dart';
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

  BlurUpImage({
    super.key,
    required this.url,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.all(Radius.circular(14)),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Image.network(
          url,
          fit: fit,
          loadingBuilder: (context, child, progress) {
            if (progress == null) {
              // Loaded — crossfade in.
              return AnimatedOpacity(
                opacity: 1,
                duration: Duration(milliseconds: 400),
                curve: Curves.easeOut,
                child: child,
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                BlurPlaceholder(height: height, icon: Icons.image_rounded),
                if (progress.expectedTotalBytes != null)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        width: 80,
                        child: LinearProgressIndicator(
                          value: progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!,
                          minHeight: 3,
                          backgroundColor: Colors.black26,
                          valueColor: AlwaysStoppedAnimation(
                              RMColors.primary),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
          errorBuilder: (context, error, stack) => Container(
            height: height,
            color: RMColors.surfaceAlt,
            child: Center(
              child: Icon(Icons.broken_image_rounded,
                  color: RMColors.textHint, size: 32),
            ),
          ),
        ),
      ),
    );
  }
}

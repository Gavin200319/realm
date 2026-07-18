import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/drop.dart';
import '../theme/rm_theme.dart';
import 'blur_media.dart';

/// A compact preview of a drop's first attachment for use in feed cards.
/// - Locked drops (or drops with no media) show a blurred lock placeholder.
/// - Photos use the existing blur-up progressive loader.
/// - Videos show a real first-frame thumbnail with a small play badge.
/// - Documents show a generic file tile.
class MediaThumbnailPreview extends StatelessWidget {
  final DropMediaItem? item;
  final bool locked;
  final double height;
  final BorderRadius borderRadius;

  const MediaThumbnailPreview({
    super.key,
    required this.item,
    required this.locked,
    this.height = 160,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  @override
  Widget build(BuildContext context) {
    final media = item;
    if (locked || media == null) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: BlurPlaceholder(
          height: height,
          icon: locked ? Icons.lock_rounded : Icons.location_on_rounded,
        ),
      );
    }

    switch (media.type) {
      case DropMediaType.photo:
        return BlurUpImage(
          url: media.url,
          height: height,
          borderRadius: borderRadius,
        );
      case DropMediaType.video:
        return ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: _VideoThumbnail(url: media.url),
          ),
        );
      case DropMediaType.document:
        return ClipRRect(
          borderRadius: borderRadius,
          child: Container(
            height: height,
            width: double.infinity,
            color: RMColors.surfaceAlt,
            child: Center(
              child: Icon(Icons.insert_drive_file_rounded,
                  color: RMColors.textHint, size: 36),
            ),
          ),
        );
    }
  }
}

/// A static, non-interactive first-frame preview of a video — same
/// play/pause priming trick as the full gallery video tile, minus the
/// tap-to-play controls, since feed cards should open the drop detail
/// screen on tap rather than start playing inline.
class _VideoThumbnail extends StatefulWidget {
  final String url;
  const _VideoThumbnail({required this.url});

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
      // Force the first frame to actually render (see note in
      // drop_detail_screen's _VideoTile) instead of showing black.
      await controller.play();
      await controller.pause();
      await controller.seekTo(Duration.zero);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_failed) {
      return Container(
        color: RMColors.surfaceAlt,
        child: Center(
          child: Icon(Icons.videocam_off_rounded,
              color: RMColors.textHint, size: 32),
        ),
      );
    }
    if (c == null) {
      return BlurPlaceholder(icon: Icons.videocam_rounded);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: c.value.size.width,
            height: c.value.size.height,
            child: VideoPlayer(c),
          ),
        ),
        Container(
          color: Colors.black26,
          child: Center(
            child: Icon(Icons.play_circle_fill_rounded,
                color: Colors.white, size: 40),
          ),
        ),
      ],
    );
  }
}

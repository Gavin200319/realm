import 'package:flutter/material.dart';
import '../models/drop.dart';
import '../services/geocoding_service.dart';
import '../theme/rm_theme.dart';
import 'media_thumbnail.dart';

/// The single visual representation of a drop, shared by every place a
/// drop can be listed (the Explore feed, the Compass tab's nearby list,
/// etc.) so a drop looks and behaves identically no matter where you
/// found it — same media thumbnail (including video frames), same
/// location badge, same lock/unlock affordance.
class DropCard extends StatefulWidget {
  final Drop drop;
  final VoidCallback onTap;

  const DropCard({super.key, required this.drop, required this.onTap});

  @override
  State<DropCard> createState() => _DropCardState();
}

class _DropCardState extends State<DropCard> {
  String? _placeLabel;

  @override
  void initState() {
    super.initState();
    _resolveLocation();
  }

  @override
  void didUpdateWidget(covariant DropCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drop.id != widget.drop.id) {
      _placeLabel = null;
      _resolveLocation();
    }
  }

  /// Best-effort place name for the location badge on top of the post.
  /// Falls back silently to the distance label if this never resolves
  /// (offline, rate-limited, etc.) — see _locationText.
  Future<void> _resolveLocation() async {
    final drop = widget.drop;
    if (drop.dropLat == null || drop.dropLng == null) return;
    final label = await GeocodingService.instance
        .reverseGeocode(drop.dropLat!, drop.dropLng!);
    if (mounted && label != null) setState(() => _placeLabel = label);
  }

  String get _locationText {
    final drop = widget.drop;
    // Locked drops intentionally keep their exact location a mystery —
    // only the distance is meaningful until the drop is unlocked.
    if (!drop.isUnlocked) return drop.distanceLabel;
    return _placeLabel ?? drop.distanceLabel;
  }

  @override
  Widget build(BuildContext context) {
    final drop = widget.drop;
    final locked = !drop.isUnlocked;
    final canUnlock = drop.isWithinUnlockRange && locked;
    final media = drop.mediaItems.isNotEmpty
        ? drop.mediaItems.first
        : (drop.mediaUrl != null && drop.mediaType != null
            ? DropMediaItem(
                url: drop.mediaUrl!,
                type: drop.mediaType!,
                sizeBytes: drop.mediaSizeBytes)
            : null);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: RMColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: canUnlock
                ? RMColors.accent.withOpacity(0.6)
                : drop.isUnlocked
                    ? RMColors.success.withOpacity(0.3)
                    : RMColors.border,
            width: canUnlock ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Location badge — always on top of the post ──────────
            Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  Icon(Icons.location_on_rounded,
                      size: 14,
                      color: locked ? RMColors.textHint : RMColors.primary),
                  SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _locationText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            locked ? RMColors.textHint : RMColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (drop.isPrivate)
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: RMColors.primaryDim,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'PRIVATE',
                        style: TextStyle(
                            color: RMColors.primary,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5),
                      ),
                    ),
                ],
              ),
            ),

            // ── Media thumbnail ───────────────────────────────────────
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: MediaThumbnailPreview(item: media, locked: locked),
            ),
            SizedBox(height: 12),

            // ── Caption + meta + unlock affordance ────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: locked
                          ? RMColors.surfaceAlt
                          : RMColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      locked
                          ? (canUnlock
                              ? Icons.lock_open_rounded
                              : Icons.lock_rounded)
                          : Icons.lock_open_rounded,
                      color: locked
                          ? (canUnlock ? RMColors.accent : RMColors.textHint)
                          : RMColors.success,
                      size: 17,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          locked ? 'Locked drop' : (drop.caption ?? ''),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: locked
                                ? RMColors.textSecondary
                                : RMColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            fontStyle:
                                locked ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                        if (!locked) ...[
                          SizedBox(height: 2),
                          Text('by ${drop.creatorUsername}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  if (canUnlock)
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: RMColors.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: RMColors.accent.withOpacity(0.4)),
                      ),
                      child: Text(
                        'Unlock',
                        style: TextStyle(
                            color: RMColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    )
                  else
                    Icon(Icons.chevron_right_rounded,
                        color: RMColors.textHint),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated entrance wrapper (fade + slight upward slide, staggered by
/// list index) around a [DropCard] — shared by the Explore feed and the
/// Compass tab's nearby list so both lists animate in identically.
class AnimatedDropCard extends StatefulWidget {
  final Drop drop;
  final int index;
  final VoidCallback onTap;

  const AnimatedDropCard({
    super.key,
    required this.drop,
    required this.index,
    required this.onTap,
  });

  @override
  State<AnimatedDropCard> createState() => _AnimatedDropCardState();
}

class _AnimatedDropCardState extends State<AnimatedDropCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 350 + widget.index * 60),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    Future.delayed(Duration(milliseconds: widget.index * 60), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: DropCard(drop: widget.drop, onTap: widget.onTap),
        ),
      ),
    );
  }
}

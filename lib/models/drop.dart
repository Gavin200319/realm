enum DropVisibility { public, private }
enum DropMediaType { photo, video, document }

DropMediaType? parseDropMediaType(String? raw) {
  switch (raw) {
    case 'photo': return DropMediaType.photo;
    case 'video': return DropMediaType.video;
    case 'document': return DropMediaType.document;
    default: return null;
  }
}

/// A single attachment on a drop. A drop can carry more than one file
/// (e.g. a couple of photos plus a document) — [Drop.mediaItems] holds
/// the full list, while [Drop.mediaUrl]/[Drop.mediaType]/[Drop.mediaSizeBytes]
/// mirror the first item for anything that only cares about "the" media.
class DropMediaItem {
  final String url;
  final DropMediaType type;
  final int? sizeBytes;
  final String? name;
  /// For videos only: a small pre-generated JPEG frame, uploaded
  /// alongside the video, so feed/grid views can show a lightweight
  /// static image instead of spinning up a real video player per card.
  final String? thumbUrl;

  DropMediaItem({
    required this.url,
    required this.type,
    this.sizeBytes,
    this.name,
    this.thumbUrl,
  });

  factory DropMediaItem.fromMap(Map<String, dynamic> map) {
    return DropMediaItem(
      url: map['url'] as String,
      type: parseDropMediaType(map['type'] as String?) ?? DropMediaType.photo,
      sizeBytes: (map['size_bytes'] as num?)?.toInt(),
      name: map['name'] as String?,
      thumbUrl: map['thumb_url'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'url': url,
        'type': switch (type) {
          DropMediaType.photo => 'photo',
          DropMediaType.video => 'video',
          DropMediaType.document => 'document',
        },
        'size_bytes': sizeBytes,
        'name': name,
        'thumb_url': thumbUrl,
      };

  /// Human-readable size, e.g. "1.4 MB". Returns null if unknown.
  String? get sizeLabel => formatFileSize(sizeBytes);
}

/// Formats a byte count as a short human-readable label ("482 KB",
/// "3.1 MB"). Returns null for an unknown/zero-or-negative size.
String? formatFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return null;
  const units = ['B', 'KB', 'MB', 'GB'];
  double size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  final decimals = unitIndex == 0 ? 0 : 1;
  return '${size.toStringAsFixed(decimals)} ${units[unitIndex]}';
}

class Drop {
  final String id;
  final String creatorId;
  final String creatorUsername;
  final String? caption;
  final String? mediaUrl;
  final DropMediaType? mediaType;
  final int? mediaSizeBytes;
  final bool allowDownload;
  final List<DropMediaItem> mediaItems;
  final DropVisibility visibility;
  final int unlockRadiusM;
  final double distanceM;
  final double? dropLat;
  final double? dropLng;
  final bool isUnlocked;
  final DateTime createdAt;

  Drop({
    required this.id,
    required this.creatorId,
    required this.creatorUsername,
    required this.caption,
    required this.mediaUrl,
    required this.mediaType,
    this.mediaSizeBytes,
    this.allowDownload = true,
    this.mediaItems = const [],
    required this.visibility,
    required this.unlockRadiusM,
    required this.distanceM,
    this.dropLat,
    this.dropLng,
    required this.isUnlocked,
    required this.createdAt,
  });

  factory Drop.fromMap(Map<String, dynamic> map) {
    final rawItems = map['media_items'];
    final items = <DropMediaItem>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is Map<String, dynamic>) {
          items.add(DropMediaItem.fromMap(raw));
        } else if (raw is Map) {
          items.add(DropMediaItem.fromMap(Map<String, dynamic>.from(raw)));
        }
      }
    }

    return Drop(
      id: map['id'] as String,
      creatorId: map['creator_id'] as String,
      creatorUsername: map['creator_username'] as String? ?? 'unknown',
      caption: map['caption'] as String?,
      mediaUrl: map['media_url'] as String?,
      mediaType: parseDropMediaType(map['media_type'] as String?),
      mediaSizeBytes: (map['media_size_bytes'] as num?)?.toInt(),
      allowDownload: map['allow_download'] as bool? ?? true,
      mediaItems: items,
      visibility: (map['visibility'] as String?) == 'private'
          ? DropVisibility.private
          : DropVisibility.public,
      unlockRadiusM: (map['unlock_radius_m'] as num).toInt(),
      distanceM: (map['distance_m'] as num).toDouble(),
      dropLat: (map['drop_lat'] as num?)?.toDouble(),
      dropLng: (map['drop_lng'] as num?)?.toDouble(),
      isUnlocked: map['is_unlocked'] as bool,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  String get distanceLabel {
    if (distanceM < 1000) return '${distanceM.round()}m away';
    return '${(distanceM / 1000).toStringAsFixed(1)}km away';
  }

  bool get isWithinUnlockRange => distanceM <= unlockRadiusM;
  bool get isPrivate => visibility == DropVisibility.private;

  /// Total size across every attachment, or null if none are known.
  int? get totalSizeBytes {
    if (mediaItems.isEmpty) return mediaSizeBytes;
    final known = mediaItems.where((m) => m.sizeBytes != null);
    if (known.isEmpty) return mediaSizeBytes;
    return known.fold<int>(0, (sum, m) => sum + m.sizeBytes!);
  }

  String? get totalSizeLabel => formatFileSize(totalSizeBytes);
}

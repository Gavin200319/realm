class ProfileStats {
  final String userId;
  final String username;
  final String? avatarUrl;
  final int dropsCreated;
  final int dropsUnlocked;
  final int followerCount;

  ProfileStats({
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.dropsCreated,
    required this.dropsUnlocked,
    this.followerCount = 0,
  });

  factory ProfileStats.fromMap(Map<String, dynamic> map) {
    return ProfileStats(
      userId: map['user_id'] as String,
      username: map['username'] as String,
      avatarUrl: map['avatar_url'] as String?,
      dropsCreated: (map['drops_created'] as num).toInt(),
      dropsUnlocked: (map['drops_unlocked'] as num).toInt(),
      followerCount: (map['follower_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'user_id': userId,
        'username': username,
        'avatar_url': avatarUrl,
        'drops_created': dropsCreated,
        'drops_unlocked': dropsUnlocked,
        'follower_count': followerCount,
      };
}

class ProfileStats {
  final String userId;
  final String username;
  final int dropsCreated;
  final int dropsUnlocked;

  ProfileStats({
    required this.userId,
    required this.username,
    required this.dropsCreated,
    required this.dropsUnlocked,
  });

  factory ProfileStats.fromMap(Map<String, dynamic> map) {
    return ProfileStats(
      userId: map['user_id'] as String,
      username: map['username'] as String,
      dropsCreated: (map['drops_created'] as num).toInt(),
      dropsUnlocked: (map['drops_unlocked'] as num).toInt(),
    );
  }
}

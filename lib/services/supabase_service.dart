import 'dart:async';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/drop.dart';
import '../models/profile_stats.dart';
import '../models/public_profile.dart';
import '../models/flick.dart';
import '../models/status_post.dart';
import 'app_storage_service.dart';
import 'local_cache_service.dart';

/// Thin wrapper around the Supabase client. Keeping all Supabase calls
/// in one place makes it easy to swap the backend later if v2 ever
/// needs a custom service for something Supabase can't do.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ---------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signUp({
    required String email,
    required String password,
    required String username,
    required String displayName,
    required String homeCity,
  }) async {
    final res = await _client.auth.signUp(email: email, password: password);
    final user = res.user;
    if (user == null) {
      throw Exception('Sign up failed — no user returned.');
    }
    await _client.from('profiles').insert({
      'id': user.id,
      'username': username,
      'display_name': displayName,
      'home_city': homeCity,
    });
  }

  Future<void> signIn({
    required String identifier, // email or username
    required String password,
  }) async {
    String email = identifier;

    // Allow login by username by resolving it to an email first.
    if (!identifier.contains('@')) {
      final profile = await _client
          .from('profiles')
          .select('id')
          .eq('username', identifier)
          .maybeSingle();
      if (profile == null) {
        throw Exception('No account found for that username.');
      }
      // Supabase auth requires email for password sign-in; in a real
      // build, store email lookup via a secure RPC instead of relying
      // on client-side profile reads for this. This is a v1 shortcut.
      throw Exception(
        'Username login requires a server-side email lookup RPC — '
        'sign in with email for v1, or add a `resolve_login_email` '
        'RPC before shipping username login.',
      );
    }

    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    await LocalCacheService.instance.clearAll();
    await AppStorageService.instance.clearAll();
  }

  // ---------------------------------------------------------------
  // Drops
  // ---------------------------------------------------------------

  Future<List<Drop>> fetchNearbyDrops({
    required double lat,
    required double lng,
    int radiusM = 2000,
  }) async {
    final rows = await _client.rpc('nearby_drops', params: {
      'user_lat': lat,
      'user_lng': lng,
      'radius_m': radiusM,
    });
    return (rows as List)
        .map((row) => Drop.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// All drops made by one specific user — locked ones included, with
  /// distance from [lat]/[lng] so they can still be navigated to. This
  /// is how a locked drop is meant to be found now that the Explore
  /// feed only shows already-unlocked drops: search for the person who
  /// left it, then browse their profile.
  Future<List<Drop>> fetchUserDrops({
    required String userId,
    required double lat,
    required double lng,
  }) async {
    final rows = await _client.rpc('user_drops', params: {
      'target_user_id': userId,
      'user_lat': lat,
      'user_lng': lng,
    });
    return (rows as List)
        .map((row) => Drop.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Attempts to unlock a drop. The server independently verifies
  /// proximity — the client's claimed location is never trusted for
  /// the actual unlock decision.
  Future<bool> attemptUnlock({
    required String dropId,
    required double lat,
    required double lng,
  }) async {
    final result = await _client.rpc('attempt_unlock', params: {
      'target_drop_id': dropId,
      'user_lat': lat,
      'user_lng': lng,
    });
    return result as bool;
  }

  Future<void> createDrop({
    required double lat,
    required double lng,
    required String caption,
    String? mediaUrl,
    String? mediaType,
    int? mediaSizeBytes,
    bool allowDownload = true,
    List<Map<String, dynamic>> mediaItems = const [],
    int unlockRadiusM = 50,
    String visibility = 'public',
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Must be signed in to create a drop.');

    await _client.from('drops').insert({
      'creator_id': user.id,
      'location': 'SRID=4326;POINT($lng $lat)',
      'caption': caption,
      'media_url': mediaUrl,
      'media_type': mediaType,
      'media_size_bytes': mediaSizeBytes,
      'allow_download': allowDownload,
      'media_items': mediaItems,
      'unlock_radius_m': unlockRadiusM,
      'visibility': visibility,
    });
  }

  /// Uploads a single file's bytes to the `drop-media` bucket and returns
  /// its public URL. [onProgress] is called with a 0.0–1.0 fraction.
  ///
  /// The Supabase storage client doesn't expose true byte-level upload
  /// progress for `uploadBinary`, so progress here is simulated: it
  /// climbs smoothly toward ~90% for as long as the upload future is
  /// still pending (scaled roughly to the file size so bigger files
  /// "feel" slower), then snaps to 100% the moment the upload actually
  /// completes. This keeps the progress toast honest about "still
  /// working" vs "done" without pretending to know exact byte counts.
  Future<String> uploadDropMedia({
    required Uint8List bytes,
    required String mediaType, // 'photo', 'video', 'document'
    String extension = 'jpg',
    void Function(double progress)? onProgress,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Must be signed in to upload media.');

    final fileName =
        '${user.id}/${DateTime.now().millisecondsSinceEpoch}_'
        '${bytes.length}.$extension';

    Timer? ticker;
    if (onProgress != null) {
      // Roughly 1 simulated "tick" per 150ms; total ramp time scales
      // with file size (capped) so a 50MB video doesn't rocket to 90%
      // in half a second while a 20KB photo doesn't crawl either.
      final estimatedMs = (bytes.length / 1024 / 40).clamp(600, 12000);
      final steps = (estimatedMs / 150).clamp(4, 80).round();
      var step = 0;
      onProgress(0.02);
      ticker = Timer.periodic(Duration(milliseconds: 150), (t) {
        step++;
        final fraction = (step / steps) * 0.9;
        onProgress(fraction.clamp(0.0, 0.9));
        if (step >= steps) t.cancel();
      });
    }

    try {
      await _client.storage.from('drop-media').uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(upsert: false),
          );
    } finally {
      ticker?.cancel();
    }

    onProgress?.call(1.0);
    return _client.storage.from('drop-media').getPublicUrl(fileName);
  }

  /// Deletes a drop. Row-level security (see schema.sql, "Users can
  /// delete their own drops") means this silently affects zero rows if
  /// the caller isn't the creator, so callers should still gate the
  /// delete button on ownership client-side for a sane UX.
  Future<void> deleteDrop(String dropId) async {
    await _client.from('drops').delete().eq('id', dropId);
  }

  /// Grant a specific user access to a private drop by username.
  /// Returns false if the username doesn't exist.
  Future<bool> grantDropAccess({
    required String dropId,
    required String username,
  }) async {
    final result = await _client.rpc('grant_drop_access', params: {
      'target_drop_id': dropId,
      'target_username': username,
    });
    return result as bool;
  }

  /// Search profiles by username prefix — used for the access allowlist
  /// picker when creating a private drop, starting a chat, and the
  /// Explore feed's user search. Excludes anyone who's turned off
  /// "Allow discovery" in their privacy settings.
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.length < 2) return [];
    final rows = await _client
        .from('profiles')
        .select('id, username, display_name, avatar_url')
        .ilike('username', '$query%')
        .eq('allow_discovery', true)
        .limit(10);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Everyone who follows the current user — for the "Followers" list
  /// on the current user's own profile. Unlike [fetchMutualFollows],
  /// this doesn't require the current user to follow back.
  Future<List<Map<String, dynamic>>> fetchFollowers() async {
    final rows = await _client.rpc('get_followers');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// The current user's own drops, newest first, for the "Dropped"
  /// gallery on their profile. Always reports each drop as unlocked —
  /// you never need to walk back to your own drop to see it.
  Future<List<Drop>> fetchMyDrops() async {
    final rows = await _client.rpc('get_my_drops');
    return (rows as List)
        .map((row) => Drop.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Everyone the current user follows who also follows them back —
  /// used to show a "Friends" list when starting a new chat, so people
  /// don't have to type a username for someone they already talk to.
  Future<List<Map<String, dynamic>>> fetchMutualFollows() async {
    final rows = await _client.rpc('get_mutual_follows');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Returns the most recently created drop id by a user.
  /// Used after createDrop to grant allowlist access.
  Future<String?> fetchLatestDropId(String userId) async {
    final row = await _client
        .from('drops')
        .select('id')
        .eq('creator_id', userId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row?['id'] as String?;
  }

  // ---------------------------------------------------------------
  // Interactions (likes + comments)
  // ---------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchInteractions({
    required String dropId,
  }) async {
    final rows = await _client
        .from('drop_interactions')
        .select('*, profiles(username, avatar_url)')
        .eq('drop_id', dropId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> addLike({required String dropId}) async {
    await _client.from('drop_interactions').insert({
      'user_id': currentUser!.id,
      'drop_id': dropId,
      'type': 'like',
      'content': null,
    });
  }

  Future<void> removeLike({required String dropId}) async {
    await _client
        .from('drop_interactions')
        .delete()
        .eq('drop_id', dropId)
        .eq('user_id', currentUser!.id)
        .eq('type', 'like');
  }

  Future<void> addComment({
    required String dropId,
    required String content,
  }) async {
    // Comments bypass the unique(user_id, drop_id, type) constraint
    // by using a raw insert with upsert disabled — multiple comments
    // per user on same drop are fine.
    await _client.from('drop_interactions').insert({
      'user_id': currentUser!.id,
      'drop_id': dropId,
      'type': 'comment',
      'content': content,
    });
  }

  Future<ProfileStats?> fetchProfileStats(String userId) async {
    final row = await _client
        .from('profile_stats')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return ProfileStats.fromMap(row);
  }

  /// The privacy-filtered view of a profile shown to visitors: any
  /// field the owner has marked private is already null by the time it
  /// gets here (enforced server-side in `get_public_profile`), plus
  /// follow counts and whether the current user follows them.
  Future<PublicProfile?> fetchPublicProfile(String userId) async {
    final rows = await _client.rpc('get_public_profile', params: {
      'target_user_id': userId,
    });
    final list = rows as List;
    if (list.isEmpty) return null;
    return PublicProfile.fromMap(list.first as Map<String, dynamic>);
  }

  /// Follows/unfollows [userId] as the current user. Returns the new
  /// state — true if now following, false if now unfollowed.
  Future<bool> toggleFollow(String userId) async {
    final result = await _client.rpc('toggle_follow', params: {
      'target_user_id': userId,
    });
    return result as bool;
  }

  /// The current user's own privacy flags, for the Privacy settings sheet.
  Future<Map<String, dynamic>?> fetchPrivacySettings(String userId) async {
    final row = await _client
        .from('profiles')
        .select('show_home_city, show_display_name, show_stats, allow_discovery')
        .eq('id', userId)
        .maybeSingle();
    return row;
  }

  /// Persists one or more privacy flags for the current user. Each
  /// controls a specific detail on their public-facing profile — see
  /// `get_public_profile`.
  Future<void> updatePrivacySettings({
    required String userId,
    bool? showHomeCity,
    bool? showDisplayName,
    bool? showStats,
    bool? allowDiscovery,
  }) async {
    final updates = <String, dynamic>{};
    if (showHomeCity != null) updates['show_home_city'] = showHomeCity;
    if (showDisplayName != null) updates['show_display_name'] = showDisplayName;
    if (showStats != null) updates['show_stats'] = showStats;
    if (allowDiscovery != null) updates['allow_discovery'] = allowDiscovery;
    if (updates.isEmpty) return;
    await _client.from('profiles').update(updates).eq('id', userId);
  }

  /// Everything the "Edit profile" sheet's User details section needs
  /// in one call — username/display name/home city come from
  /// `profiles`, email comes from the Auth user since it isn't
  /// mirrored into that table.
  Future<Map<String, String?>> fetchAccountDetails() async {
    final user = currentUser;
    if (user == null) throw Exception('Not signed in.');
    final row = await _client
        .from('profiles')
        .select('username, display_name, home_city')
        .eq('id', user.id)
        .single();
    return {
      'username': row['username'] as String?,
      'display_name': row['display_name'] as String?,
      'home_city': row['home_city'] as String?,
      'email': user.email,
    };
  }

  Future<void> updateProfile({
    required String userId,
    String? username,
    String? displayName,
    String? homeCity,
    String? avatarUrl,
  }) async {
    final updates = <String, dynamic>{};
    if (username != null) updates['username'] = username;
    if (displayName != null) updates['display_name'] = displayName;
    if (homeCity != null) updates['home_city'] = homeCity;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (updates.isEmpty) return;
    try {
      await _client.from('profiles').update(updates).eq('id', userId);
    } on PostgrestException catch (e) {
      // 23505 = unique_violation — the only column here with a UNIQUE
      // constraint is username, so a conflict always means "taken."
      if (e.code == '23505') {
        throw Exception('That username is already taken.');
      }
      rethrow;
    }
  }

  /// Changes the account's login email. Supabase sends a confirmation
  /// link to the new address by default — the change only actually
  /// takes effect once that's clicked, so the caller should tell the
  /// user to go check their inbox rather than assume it's done.
  Future<void> updateEmail(String newEmail) async {
    await _client.auth.updateUser(UserAttributes(email: newEmail));
  }

  /// Uploads a profile picture to the `avatars` bucket under the current
  /// user's own folder (required by the storage RLS policies — see
  /// v5-migration.sql), writes the resulting public URL onto the
  /// profile row, and returns that URL so the caller can update local
  /// state immediately without a round trip.
  ///
  /// Each upload gets a fresh, cache-busting filename rather than
  /// overwriting a fixed `avatar.jpg` — CDNs and image widgets both
  /// tend to cache aggressively by URL, and a stable filename would
  /// mean a freshly-changed picture doesn't show up right away.
  Future<String> uploadAvatar({
    required Uint8List bytes,
    String extension = 'jpg',
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Must be signed in to change your avatar.');

    final fileName = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$extension';

    await _client.storage.from('avatars').uploadBinary(
          fileName,
          bytes,
          fileOptions: FileOptions(upsert: false, contentType: 'image/$extension'),
        );

    final url = _client.storage.from('avatars').getPublicUrl(fileName);
    await updateProfile(userId: user.id, avatarUrl: url);
    return url;
  }

  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) return;
    await _client.from('profiles').delete().eq('id', user.id);
    await signOut();
  }

  // ---------------------------------------------------------------
  // Chats (direct messages)
  // ---------------------------------------------------------------

  /// One row per person the current user has exchanged messages with,
  /// newest conversation first. Backed by the `list_conversations` RPC
  /// (see v4-migration.sql).
  Future<List<Map<String, dynamic>>> fetchConversations() async {
    final rows = await _client.rpc('list_conversations');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Full message history between the current user and [otherUserId],
  /// oldest first (ready to feed straight into a chat list).
  Future<List<Map<String, dynamic>>> fetchMessages(
      {required String otherUserId}) async {
    final me = currentUser?.id;
    if (me == null) throw Exception('Must be signed in to view messages.');
    final rows = await _client
        .from('messages')
        .select()
        .or('and(sender_id.eq.$me,recipient_id.eq.$otherUserId),'
            'and(sender_id.eq.$otherUserId,recipient_id.eq.$me)')
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// A realtime stream of every row in `messages` between the current
  /// user and [otherUserId] — used to live-update an open chat thread.
  Stream<List<Map<String, dynamic>>> watchMessages(
      {required String otherUserId}) {
    final me = currentUser?.id;
    if (me == null) return const Stream.empty();
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) => rows.where((r) {
              final sender = r['sender_id'] as String?;
              final recipient = r['recipient_id'] as String?;
              return (sender == me && recipient == otherUserId) ||
                  (sender == otherUserId && recipient == me);
            }).toList());
  }

  /// A realtime stream of every incoming message addressed to the
  /// current user, across *all* conversations — unlike [watchMessages]
  /// this isn't scoped to a single thread. Used to drive things like
  /// the drawer's "new message" popup, which needs to know a message
  /// arrived regardless of which conversation it belongs to.
  Stream<Map<String, dynamic>> watchIncomingMessages() {
    final me = currentUser?.id;
    if (me == null) return const Stream.empty();
    final seen = <Object>{};
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .expand((rows) => rows.where((r) => r['recipient_id'] == me))
        .where((r) {
          final id = r['id'];
          if (id == null || seen.contains(id)) return false;
          seen.add(id);
          return true;
        });
  }

  Future<void> sendMessage({
    required String recipientId,
    required String content,
  }) async {
    final me = currentUser;
    if (me == null) throw Exception('Must be signed in to send messages.');
    await _client.from('messages').insert({
      'sender_id': me.id,
      'recipient_id': recipientId,
      'content': content,
    });
  }

  Future<void> markConversationRead(String otherUserId) async {
    await _client.rpc('mark_conversation_read',
        params: {'other_user_id': otherUserId});
  }

  // ---------------------------------------------------------------
  // Flicks (short vertical videos, not location-gated)
  // ---------------------------------------------------------------

  /// The 30-second cap enforced client-side before upload — the
  /// `duration_seconds` column also has a matching DB check constraint
  /// as a second line of defense.
  static const flickMaxDurationSeconds = 30;

  Future<List<Flick>> fetchFlicks({
    int limit = 20,
    DateTime? beforeCreatedAt,
  }) async {
    final rows = await _client.rpc('fetch_flicks', params: {
      'limit_count': limit,
      if (beforeCreatedAt != null)
        'before_created_at': beforeCreatedAt.toIso8601String(),
    });
    return (rows as List)
        .map((row) => Flick.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Uploads a flick video (and optional thumbnail) to the same
  /// `drop-media` bucket used for drop attachments (via the same
  /// per-user folder as [uploadDropMedia]), then creates the `flicks`
  /// row.
  Future<Flick> createFlick({
    required Uint8List videoBytes,
    required String extension,
    required int durationSeconds,
    String? caption,
    Uint8List? thumbBytes,
    void Function(double progress)? onProgress,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Must be signed in to post a flick.');
    if (durationSeconds > flickMaxDurationSeconds) {
      throw Exception('Flicks can be at most $flickMaxDurationSeconds seconds.');
    }

    final videoUrl = await uploadDropMedia(
      bytes: videoBytes,
      mediaType: 'video',
      extension: extension,
      onProgress: onProgress,
    );

    String? thumbUrl;
    if (thumbBytes != null) {
      thumbUrl = await uploadDropMedia(
        bytes: thumbBytes,
        mediaType: 'photo',
        extension: 'jpg',
      );
    }

    final row = await _client
        .from('flicks')
        .insert({
          'creator_id': user.id,
          'caption': caption,
          'video_url': videoUrl,
          'thumb_url': thumbUrl,
          'duration_seconds': durationSeconds,
        })
        .select('id, created_at')
        .single();

    final profile = await _client
        .from('profiles')
        .select('username, avatar_url')
        .eq('id', user.id)
        .single();

    return Flick(
      id: row['id'] as String,
      creatorId: user.id,
      creatorUsername: profile['username'] as String? ?? 'unknown',
      creatorAvatarUrl: profile['avatar_url'] as String?,
      caption: caption,
      videoUrl: videoUrl,
      thumbUrl: thumbUrl,
      durationSeconds: durationSeconds,
      likeCount: 0,
      commentCount: 0,
      isLiked: false,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  Future<void> deleteFlick(String flickId) async {
    await _client.from('flicks').delete().eq('id', flickId);
  }

  /// Toggles the current user's like on a flick. Returns the new
  /// liked state (true = now liked).
  Future<bool> toggleFlickLike(String flickId) async {
    final result =
        await _client.rpc('toggle_flick_like', params: {'target_flick_id': flickId});
    return result as bool;
  }

  /// Top-level comments on a flick, newest first.
  Future<List<FlickComment>> fetchFlickComments(String flickId) async {
    final rows = await _client
        .rpc('fetch_flick_comments', params: {'target_flick_id': flickId});
    return (rows as List)
        .map((row) => FlickComment.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Replies to a single top-level comment, oldest first.
  Future<List<FlickComment>> fetchCommentReplies(String commentId) async {
    final rows = await _client
        .rpc('fetch_comment_replies', params: {'target_comment_id': commentId});
    return (rows as List)
        .map((row) => FlickComment.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Posts a comment (or, with [parentCommentId] set, a reply) and
  /// returns the new comment's id.
  Future<String> addFlickComment({
    required String flickId,
    required String content,
    String? parentCommentId,
  }) async {
    final id = await _client.rpc('add_flick_comment', params: {
      'target_flick_id': flickId,
      'comment_content': content,
      if (parentCommentId != null) 'parent_comment_id': parentCommentId,
    });
    return id as String;
  }

  /// Toggles the current user's like on a comment or reply. Returns
  /// the new liked state.
  Future<bool> toggleCommentLike(String commentId) async {
    final result = await _client
        .rpc('toggle_comment_like', params: {'target_comment_id': commentId});
    return result as bool;
  }

  // ---------------------------------------------------------------
  // Status (disappearing photo/video posts — WhatsApp/IG-style,
  // 12h lifespan)
  // ---------------------------------------------------------------

  /// The 12h window is really enforced by Postgres — see the
  /// generated `expires_at` column and its RLS select policy in
  /// v11-migration.sql — this constant just mirrors it so client-side
  /// validation (e.g. rejecting an obviously-too-long video) has a
  /// single source to reference. See also [StatusPost.lifespan] for
  /// the same window used to render the countdown label.
  static const statusMaxVideoDurationSeconds = 30;

  /// One row per creator who currently has an active status, ordered
  /// by the server as "you first, then unseen, then most recent" —
  /// see fetch_status_feed in v11-migration.sql.
  Future<List<StatusFeedEntry>> fetchStatusFeed() async {
    final rows = await _client.rpc('fetch_status_feed');
    return (rows as List)
        .map((row) => StatusFeedEntry.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// A single creator's active statuses, oldest first — the order a
  /// story viewer pages through them in.
  Future<List<StatusPost>> fetchUserStatuses(String creatorId) async {
    final rows = await _client
        .rpc('get_user_statuses', params: {'target_user_id': creatorId});
    return (rows as List)
        .map((row) => StatusPost.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Uploads the status's media to the same `drop-media` bucket used
  /// by drops and flicks (same per-user folder convention — see
  /// [uploadDropMedia]), then creates the `statuses` row. The 12h
  /// clock (see [StatusPost.lifespan]) starts ticking from whatever
  /// `created_at` the database assigns, not from whenever this future
  /// happens to resolve on the client.
  Future<StatusPost> createStatus({
    required Uint8List mediaBytes,
    required String mediaType, // 'photo' or 'video'
    required String extension,
    String? caption,
    void Function(double progress)? onProgress,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Must be signed in to post a status.');

    final mediaUrl = await uploadDropMedia(
      bytes: mediaBytes,
      mediaType: mediaType,
      extension: extension,
      onProgress: onProgress,
    );

    final row = await _client
        .from('statuses')
        .insert({
          'creator_id': user.id,
          'media_url': mediaUrl,
          'media_type': mediaType,
          'caption': caption,
        })
        .select('id, created_at')
        .single();

    final profile = await _client
        .from('profiles')
        .select('username, avatar_url')
        .eq('id', user.id)
        .single();

    return StatusPost(
      id: row['id'] as String,
      creatorId: user.id,
      creatorUsername: profile['username'] as String? ?? 'unknown',
      creatorAvatarUrl: profile['avatar_url'] as String?,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      caption: caption,
      viewCount: 0,
      isViewedByMe: true,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  /// Deletes a status early, before its 12h window is up. RLS means
  /// this silently affects zero rows if the caller isn't the creator
  /// (same caveat as [deleteDrop]).
  Future<void> deleteStatus(String statusId) async {
    await _client.from('statuses').delete().eq('id', statusId);
  }

  /// Records that the current user has seen a status. Best-effort —
  /// a missed "seen" marker just means the status shows as unviewed a
  /// little longer, which isn't worth surfacing an error for.
  Future<void> markStatusViewed(String statusId) async {
    try {
      await _client
          .rpc('mark_status_viewed', params: {'target_status_id': statusId});
    } catch (_) {
      // Non-fatal, see doc comment above.
    }
  }

  /// Who has viewed one of the current user's own statuses, most
  /// recent view first. The RPC itself enforces that only the
  /// creator can call this for their own status.
  Future<List<Map<String, dynamic>>> fetchStatusViewers(
      String statusId) async {
    final rows = await _client
        .rpc('get_status_viewers', params: {'target_status_id': statusId});
    return List<Map<String, dynamic>>.from(rows as List);
  }
}

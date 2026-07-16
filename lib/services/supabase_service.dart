import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/drop.dart';
import '../models/profile_stats.dart';

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

  Future<void> signOut() => _client.auth.signOut();

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
      'unlock_radius_m': unlockRadiusM,
      'visibility': visibility,
    });
  }

  Future<String> uploadDropMedia({
    required Uint8List bytes,
    required String mediaType, // 'photo', 'video', 'document'
    String extension = 'jpg',
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Must be signed in to upload media.');

    final fileName =
        '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _client.storage.from('drop-media').uploadBinary(fileName, bytes);
    return _client.storage.from('drop-media').getPublicUrl(fileName);
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
  /// picker when creating a private drop.
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.length < 2) return [];
    final rows = await _client
        .from('profiles')
        .select('id, username, display_name')
        .ilike('username', '$query%')
        .limit(10);
    return List<Map<String, dynamic>>.from(rows);
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
        .select('*, profiles(username)')
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

  Future<void> updateProfile({
    required String userId,
    String? displayName,
    String? homeCity,
  }) async {
    final updates = <String, dynamic>{};
    if (displayName != null) updates['display_name'] = displayName;
    if (homeCity != null) updates['home_city'] = homeCity;
    if (updates.isEmpty) return;
    await _client.from('profiles').update(updates).eq('id', userId);
  }

  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) return;
    await _client.from('profiles').delete().eq('id', user.id);
    await signOut();
  }
}

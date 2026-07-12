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
    int unlockRadiusM = 50,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Must be signed in to create a drop.');

    await _client.from('drops').insert({
      'creator_id': user.id,
      // PostGIS geography(Point) accepts WKT via this cast in PostgREST.
      'location': 'SRID=4326;POINT($lng $lat)',
      'caption': caption,
      'media_url': mediaUrl,
      'unlock_radius_m': unlockRadiusM,
    });
  }

  Future<String> uploadDropPhoto({required Uint8List bytes}) async {
    final user = currentUser;
    if (user == null) throw Exception('Must be signed in to upload media.');

    final fileName =
        '${user.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('drop-media').uploadBinary(fileName, bytes);
    return _client.storage.from('drop-media').getPublicUrl(fileName);
  }

  // ---------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------

  Future<ProfileStats?> fetchProfileStats(String userId) async {
    final row = await _client
        .from('profile_stats')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return ProfileStats.fromMap(row);
  }
}

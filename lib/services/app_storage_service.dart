import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Durable, account-scoped local storage for data the user would
/// actually be upset to lose — chat history/outbox, profile stats,
/// privacy settings, etc.
///
/// This is intentionally a *separate* store from [LocalCacheService].
/// `LocalCacheService` holds disposable, always-refetchable content
/// (the drops feed, flicks, nearby drops) under an `rm_cache_` prefix
/// — it's fine for that to be wiped at any time, worst case is a
/// re-fetch. This service uses a different prefix (`rm_data_`) and,
/// critically, nothing in the app is allowed to blanket-clear it the
/// way a "reset cache" style action might clear `LocalCacheService`.
/// The only thing that clears it is [clearAll], called from
/// `SupabaseService.signOut()` — because at that point it genuinely
/// should stop being on the device.
///
/// Same cache-first idiom as [LocalCacheService]:
///   1. Read what's stored, show it immediately (works fully offline).
///   2. Fetch fresh in the background; on success, overwrite.
///   3. On failure (offline), just keep showing what's stored.
class AppStorageService {
  AppStorageService._();
  static final AppStorageService instance = AppStorageService._();

  static const _prefix = 'rm_data_';

  Future<void> saveList(String key, List<Map<String, dynamic>> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$key', jsonEncode(items));
    } catch (_) {
      // Storage is best-effort — never let a write failure surface.
    }
  }

  Future<List<Map<String, dynamic>>?> loadList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  /// For single objects — a profile's stats, a settings blob — rather
  /// than a list.
  Future<void> saveMap(String key, Map<String, dynamic> value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$key', jsonEncode(value));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> loadMap(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$key');
    } catch (_) {}
  }

  /// Wipes every durable key. Only ever called on sign-out — this is
  /// account-scoped data, so it's correct (and necessary, for
  /// privacy) to drop it when the account signs out. It must never be
  /// wired up to any in-app "clear cache" style action.
  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}

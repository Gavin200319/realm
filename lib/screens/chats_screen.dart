import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../services/local_cache_service.dart';
import '../theme/rm_theme.dart';
import 'chat_conversation_screen.dart';

class ChatsScreen extends StatefulWidget {
  ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  static const _cacheKey = 'conversations';

  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCached();
    _load();
  }

  /// Shows whatever conversation list was cached last time immediately
  /// — no spinner, works with zero connection.
  Future<void> _loadCached() async {
    final cached = await LocalCacheService.instance.loadList(_cacheKey);
    if (cached != null && cached.isNotEmpty && mounted && _conversations.isEmpty) {
      setState(() {
        _conversations = cached;
        _loading = false;
      });
    }
  }

  Future<void> _load() async {
    if (_conversations.isEmpty) {
      setState(() { _loading = true; _error = null; });
    }
    try {
      final conversations = await SupabaseService.instance.fetchConversations();
      if (mounted) setState(() { _conversations = conversations; _error = null; });
      await LocalCacheService.instance.saveList(_cacheKey, conversations);
    } catch (e) {
      // Already showing cached conversations — don't replace them with
      // an error screen just because the refresh failed offline.
      if (mounted && _conversations.isEmpty) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openConversation(Map<String, dynamic> convo) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatConversationScreen(
          otherUserId: convo['other_user_id'] as String,
          otherUsername: convo['other_username'] as String? ?? 'unknown',
        ),
      ),
    );
    _load();
  }

  Future<void> _startNewChat() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: RMColors.surface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NewChatSheet(),
    );
    if (picked == null) return;

    final me = SupabaseService.instance.currentUser?.id;
    if (picked['id'] == me) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("You can't message yourself.")),
        );
      }
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatConversationScreen(
          otherUserId: picked['id'] as String,
          otherUsername: picked['username'] as String,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RMColors.background,
      appBar: AppBar(
        title: Text('Chats'),
        backgroundColor: RMColors.background,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewChat,
        backgroundColor: RMColors.primary,
        foregroundColor: Colors.white,
        child: Icon(Icons.edit_rounded),
      ),
      body: RefreshIndicator(
        color: RMColors.primary,
        backgroundColor: RMColors.surface,
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: RMColors.primary));
    }
    if (_error != null) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: RMColors.textSecondary)),
              ),
            ),
          ),
        ),
      );
    }
    if (_conversations.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline_rounded,
                      color: RMColors.textHint, size: 48),
                  SizedBox(height: 12),
                  Text('No conversations yet.',
                      style: TextStyle(
                          color: RMColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('Tap the pencil to message someone.',
                      style: TextStyle(color: RMColors.textSecondary)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      physics: AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _conversations.length,
      separatorBuilder: (_, __) => SizedBox(height: 8),
      itemBuilder: (context, i) {
        final c = _conversations[i];
        final unread = (c['unread_count'] as num?)?.toInt() ?? 0;
        final createdAt =
            DateTime.tryParse(c['last_message_at'] as String? ?? '');
        final me = SupabaseService.instance.currentUser?.id;
        final youSent = c['last_sender_id'] == me;

        return Material(
          color: RMColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openConversation(c),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: RMColors.border),
              ),
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: RMColors.primaryDim,
                    backgroundImage: c['other_avatar_url'] != null
                        ? CachedNetworkImageProvider(c['other_avatar_url'] as String)
                        : null,
                    child: c['other_avatar_url'] == null
                        ? Icon(Icons.person_rounded, color: RMColors.primary)
                        : null,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c['other_username'] as String? ?? 'unknown',
                          style: TextStyle(
                              color: RMColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '${youSent ? 'You: ' : ''}${c['last_message'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unread > 0
                                ? RMColors.textPrimary
                                : RMColors.textSecondary,
                            fontWeight:
                                unread > 0 ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (youSent) ...[
                            Icon(
                              Icons.done_all_rounded,
                              size: 13,
                              color: c['last_message_read_at'] != null
                                  ? Color(0xFF4FC3F7)
                                  : RMColors.textHint,
                            ),
                            SizedBox(width: 3),
                          ],
                          if (createdAt != null)
                            Text(
                              DateFormat('MMM d, h:mm a').format(createdAt),
                              style: TextStyle(
                                  color: RMColors.textHint, fontSize: 10),
                            ),
                        ],
                      ),
                      if (unread > 0) ...[
                        SizedBox(height: 4),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: RMColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$unread',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NewChatSheet extends StatefulWidget {
  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  final _ctrl = TextEditingController();

  List<Map<String, dynamic>> _friends = [];
  bool _loadingFriends = true;
  String? _friendsError;

  List<Map<String, dynamic>> _results = [];
  bool _searching = false;

  bool get _isSearchMode => _ctrl.text.trim().length >= 2;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() { _loadingFriends = true; _friendsError = null; });
    try {
      final friends = await SupabaseService.instance.fetchMutualFollows();
      if (mounted) setState(() => _friends = friends);
    } catch (e) {
      if (mounted) setState(() => _friendsError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingFriends = false);
    }
  }

  Future<void> _search(String query) async {
    // Below the 2-char threshold we just fall back to the friends list
    // rather than firing a query that searchUsers() would reject anyway.
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await SupabaseService.instance.searchUsers(query);
      if (mounted) setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pick(Map<String, dynamic> user) {
    Navigator.of(context).pop(user);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _userTile(Map<String, dynamic> r) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: RMColors.primaryDim,
        backgroundImage: r['avatar_url'] != null
            ? CachedNetworkImageProvider(r['avatar_url'] as String)
            : null,
        child: r['avatar_url'] == null
            ? Icon(Icons.person_rounded, color: RMColors.primary)
            : null,
      ),
      title: Text(r['username'] as String? ?? ''),
      subtitle: (r['display_name'] as String?)?.isNotEmpty == true
          ? Text(r['display_name'] as String)
          : null,
      onTap: () => _pick(r),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: RMColors.textHint,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_isSearchMode) {
      if (_searching && _results.isEmpty) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      if (_results.isEmpty) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('No users found.',
                style: TextStyle(color: RMColors.textSecondary)),
          ),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Search results'),
          ..._results.map(_userTile),
        ],
      );
    }

    // Default view: friends (people you follow who follow you back).
    if (_loadingFriends) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_friendsError != null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('Couldn\'t load friends.',
              style: TextStyle(color: RMColors.textSecondary)),
        ),
      );
    }
    if (_friends.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No friends yet — follow each other to see\nthem here, or search a username above.',
            textAlign: TextAlign.center,
            style: TextStyle(color: RMColors.textSecondary),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Friends'),
        ..._friends.map(_userTile),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New message',
              style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search by username',
              suffixIcon: _searching
                  ? Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            onChanged: (v) {
              setState(() {}); // toggle friends vs. search sections
              _search(v);
            },
          ),
          SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(child: _buildList()),
          ),
        ],
      ),
    );
  }
}

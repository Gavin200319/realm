import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../services/app_storage_service.dart';
import '../services/sms_bridge_service.dart';
import '../theme/rm_theme.dart';
import 'chat_conversation_screen.dart';
import 'sms_conversation_screen.dart';
import 'gateway_setup_screen.dart';

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
    final cached = await AppStorageService.instance.loadList(_cacheKey);
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
      final dm = await SupabaseService.instance.fetchConversations();
      // SMS threads live in a separate table (see v14-migration.sql),
      // so they're fetched separately and adapted into the same shape
      // as a DM conversation row, then merged newest-first — the
      // person just sees one chat list either way.
      List<Map<String, dynamic>> sms;
      try {
        final smsRows = await SmsBridgeService.instance.fetchSmsConversations();
        sms = smsRows.map(_smsRowToChatRow).toList();
      } catch (_) {
        sms = [];
      }
      final merged = [...dm, ...sms]
        ..sort((a, b) {
          final at = DateTime.tryParse(a['last_message_at'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bt = DateTime.tryParse(b['last_message_at'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });
      if (mounted) setState(() { _conversations = merged; _error = null; });
      await AppStorageService.instance.saveList(_cacheKey, merged);
    } catch (e) {
      // Already showing cached conversations — don't replace them with
      // an error screen just because the refresh failed offline.
      if (mounted && _conversations.isEmpty) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Adapts a `list_sms_conversations()` row into the same shape the
  /// chat list tile already renders for a DM row, tagged `_kind: 'sms'`
  /// so `_openConversation` knows where to route it. There's no
  /// `other_user_id`/username for an SMS thread — just a phone number,
  /// which is exactly what should show in the list per the bridge's
  /// design (the SMS side has no app account).
  Map<String, dynamic> _smsRowToChatRow(Map<String, dynamic> c) {
    return {
      '_kind': 'sms',
      'thread_id': c['thread_id'],
      'gateway_device_id': c['gateway_device_id'],
      'phone_number': c['phone_number'],
      'other_username': (c['display_name'] as String?) ?? (c['phone_number'] as String?) ?? 'Unknown',
      'last_message': c['last_message'],
      'last_message_at': c['last_message_at'],
      'last_sender_id': c['last_direction'] == 'outbound' ? SupabaseService.instance.currentUser?.id : null,
      'unread_count': c['unread_count'],
    };
  }

  Future<void> _openConversation(Map<String, dynamic> convo) async {
    if (convo['_kind'] == 'sms') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SmsConversationScreen(
            threadId: convo['thread_id'] as String,
            gatewayDeviceId: convo['gateway_device_id'] as String,
            phoneNumber: convo['phone_number'] as String,
            displayName: convo['other_username'] as String?,
          ),
        ),
      );
      _load();
      return;
    }
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

  /// Starts (or opens) a bridged SMS thread. Needs at least one
  /// gateway device already set up (see GatewaySetupScreen) — if none
  /// exists yet, sends the person there instead of failing silently.
  Future<void> _startNewSmsChat() async {
    List<Map<String, dynamic>> gateways;
    try {
      gateways = await SmsBridgeService.instance.fetchMyGatewayDevices();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load gateways: $e')));
      }
      return;
    }

    if (gateways.isEmpty) {
      if (!mounted) return;
      final goSetUp = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: RMColors.surface,
          title: Text('No SMS gateway yet'),
          content: Text(
              'Set up a gateway phone first — that\'s the device with the SIM that will actually send and receive the texts.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Set up gateway')),
          ],
        ),
      );
      if (goSetUp == true && mounted) {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => GatewaySetupScreen()));
      }
      return;
    }

    final gatewayId = gateways.first['id'] as String;
    final phoneCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final entered = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: RMColors.surface,
        title: Text('Text a phone number'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(hintText: '+1 555 123 4567'),
              autofocus: true,
            ),
            SizedBox(height: 8),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(hintText: 'Label (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true), child: Text('Start')),
        ],
      ),
    );
    if (entered != true) return;
    final phone = phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    final label = nameCtrl.text.trim();

    // The thread itself is created lazily server-side on the first
    // send_sms_message RPC call (find-or-create — see v14-migration.sql),
    // so there's no thread id yet; SmsConversationScreen sends its
    // first message using the phone number directly and only needs a
    // real threadId for realtime/history once one exists.
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SmsConversationScreen(
          threadId: '',
          gatewayDeviceId: gatewayId,
          phoneNumber: phone,
          displayName: label.isEmpty ? null : label,
        ),
      ),
    );
    _load();
  }

  Future<void> _showStartChatOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: RMColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.person_rounded, color: RMColors.primary),
              title: Text('Message a user'),
              onTap: () => Navigator.pop(context, 'user'),
            ),
            ListTile(
              leading: Icon(Icons.sms_rounded, color: RMColors.primary),
              title: Text('Text a phone number'),
              subtitle:
                  Text('Sent via your SMS gateway', style: TextStyle(fontSize: 11)),
              onTap: () => Navigator.pop(context, 'sms'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'user') {
      await _startNewChat();
    } else if (choice == 'sms') {
      await _startNewSmsChat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RMColors.background,
      appBar: AppBar(
        title: Text('Chats'),
        backgroundColor: RMColors.background,
        actions: [
          IconButton(
            icon: Icon(Icons.sms_outlined),
            tooltip: 'SMS Gateway',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => GatewaySetupScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showStartChatOptions,
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
                  c['_kind'] == 'sms'
                      ? CircleAvatar(
                          radius: 22,
                          backgroundColor: RMColors.primaryDim,
                          child: Icon(Icons.sms_rounded, color: RMColors.primary),
                        )
                      : CircleAvatar(
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

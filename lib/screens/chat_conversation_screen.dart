import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../services/app_storage_service.dart';
import '../theme/rm_theme.dart';

class ChatConversationScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUsername;

  ChatConversationScreen({
    super.key,
    required this.otherUserId,
    required this.otherUsername,
  });

  @override
  State<ChatConversationScreen> createState() =>
      _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  // Messages Supabase has actually persisted for this thread.
  List<Map<String, dynamic>> _serverMessages = [];

  // Messages typed locally that haven't been confirmed by the server
  // yet — either still in flight, or queued because the send failed
  // (offline). Kept in AppStorageService (durable — not tied to any
  // disposable-content cache) so a queued message survives an app
  // restart instead of silently vanishing.
  List<Map<String, dynamic>> _outbox = [];

  bool _loading = true;
  bool _sending = false;
  bool _flushingOutbox = false;
  String? _error;

  String get _cacheKey => 'chat_messages_${widget.otherUserId}';
  String get _outboxKey => 'chat_outbox_${widget.otherUserId}';

  /// Server-confirmed history plus anything still queued locally,
  /// oldest first. This is what actually renders — it's how a message
  /// you just sent (or typed while offline) never appears to "lose"
  /// it, even before it round-trips through Supabase.
  List<Map<String, dynamic>> get _messages {
    final merged = <Map<String, dynamic>>[..._serverMessages];
    for (final pending in _outbox) {
      final alreadyLanded = _serverMessages.any((m) =>
          m['sender_id'] == pending['sender_id'] &&
          m['content'] == pending['content'] &&
          m['created_at'] == pending['created_at']);
      if (!alreadyLanded) merged.add(pending);
    }
    merged.sort((a, b) {
      final at =
          DateTime.tryParse(a['created_at'] as String? ?? '') ?? DateTime.now();
      final bt =
          DateTime.tryParse(b['created_at'] as String? ?? '') ?? DateTime.now();
      return at.compareTo(bt);
    });
    return merged;
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 1. Cache-first: show whatever was on screen last time immediately,
    // no spinner, works with zero connection.
    final cachedMessages = await AppStorageService.instance.loadList(_cacheKey);
    final cachedOutbox = await AppStorageService.instance.loadList(_outboxKey);
    if (mounted) {
      setState(() {
        if (cachedMessages != null) _serverMessages = cachedMessages;
        if (cachedOutbox != null) _outbox = cachedOutbox;
        if (cachedMessages != null) _loading = false;
      });
      if (cachedMessages != null) _scrollToEnd();
    }

    // 2. Kick off a fresh fetch in the background. Replace on success;
    // on failure (offline) just keep showing the cached thread.
    try {
      final history = await SupabaseService.instance
          .fetchMessages(otherUserId: widget.otherUserId);
      if (mounted) {
        setState(() {
          _serverMessages = history;
          _loading = false;
          _error = null;
        });
        _scrollToEnd();
      }
      await AppStorageService.instance.saveList(_cacheKey, history);
    } catch (e) {
      if (mounted && _serverMessages.isEmpty) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }

    // Live updates for this thread — new messages just append, no
    // manual refresh needed while the conversation is open. Each
    // successful emission also means we have connectivity, so it's a
    // good moment to retry anything still stuck in the outbox.
    _sub = SupabaseService.instance
        .watchMessages(otherUserId: widget.otherUserId)
        .listen((rows) {
      if (!mounted) return;
      setState(() => _serverMessages = rows);
      AppStorageService.instance.saveList(_cacheKey, rows);
      _scrollToEnd();
      _flushOutbox();
    });

    SupabaseService.instance.markConversationRead(widget.otherUserId);
    _flushOutbox();
  }

  /// Retries every queued outbound message in order. Stops at the
  /// first failure — if we're still offline there's no point hammering
  /// the rest of the queue, and preserving order matters for a chat.
  Future<void> _flushOutbox() async {
    if (_flushingOutbox || _outbox.isEmpty) return;
    _flushingOutbox = true;
    try {
      final queue = List<Map<String, dynamic>>.from(_outbox);
      for (final pending in queue) {
        try {
          await SupabaseService.instance.sendMessage(
            recipientId: widget.otherUserId,
            content: pending['content'] as String,
          );
          if (mounted) {
            setState(() =>
                _outbox.removeWhere((m) => m['_localId'] == pending['_localId']));
          } else {
            _outbox.removeWhere((m) => m['_localId'] == pending['_localId']);
          }
          await AppStorageService.instance.saveList(_outboxKey, _outbox);
        } catch (_) {
          // Still offline (or the request genuinely failed) — leave it
          // queued and stop; we'll try again on the next stream tick.
          break;
        }
      }
    } finally {
      _flushingOutbox = false;
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    final me = SupabaseService.instance.currentUser?.id;
    if (me == null) return;

    _msgCtrl.clear();

    // Optimistic add: shows instantly with a single "sending" tick,
    // regardless of whether the network call below succeeds straight
    // away, queues, or fails outright.
    final pending = {
      '_localId': '${DateTime.now().microsecondsSinceEpoch}',
      '_pending': true,
      'sender_id': me,
      'recipient_id': widget.otherUserId,
      'content': text,
      'created_at': DateTime.now().toIso8601String(),
      'read_at': null,
    };
    setState(() {
      _outbox.add(pending);
      _sending = true;
    });
    await AppStorageService.instance.saveList(_outboxKey, _outbox);
    _scrollToEnd();

    try {
      await SupabaseService.instance.sendMessage(
        recipientId: widget.otherUserId,
        content: text,
      );
      if (mounted) {
        setState(() =>
            _outbox.removeWhere((m) => m['_localId'] == pending['_localId']));
      } else {
        _outbox.removeWhere((m) => m['_localId'] == pending['_localId']);
      }
      await AppStorageService.instance.saveList(_outboxKey, _outbox);
    } catch (_) {
      // Offline (or a transient failure) — leave it queued in the
      // outbox. It's already persisted to cache above, shows with a
      // "sending" tick, and _flushOutbox() will retry it later.
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = SupabaseService.instance.currentUser?.id;
    final messages = _messages;

    return Scaffold(
      backgroundColor: RMColors.background,
      appBar: AppBar(
        title: Text(widget.otherUsername),
        backgroundColor: RMColors.background,
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? Center(
                    child:
                        CircularProgressIndicator(color: RMColors.primary))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Text(_error!,
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: RMColors.textSecondary)),
                        ),
                      )
                    : messages.isEmpty
                        ? Center(
                            child: Text(
                              'Say hi to ${widget.otherUsername} 👋',
                              style: TextStyle(color: RMColors.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: EdgeInsets.all(16),
                            itemCount: messages.length,
                            itemBuilder: (context, i) {
                              final m = messages[i];
                              final mine = m['sender_id'] == me;
                              final createdAt = DateTime.tryParse(
                                      m['created_at'] as String? ?? '') ??
                                  DateTime.now();
                              return _MessageBubble(
                                text: m['content'] as String? ?? '',
                                time: createdAt,
                                mine: mine,
                                pending: m['_pending'] == true,
                                read: m['read_at'] != null,
                              );
                            },
                          ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Message...',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String text;
  final DateTime time;
  final bool mine;
  final bool pending;
  final bool read;

  const _MessageBubble({
    required this.text,
    required this.time,
    required this.mine,
    this.pending = false,
    this.read = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: mine ? RMColors.primary : RMColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: RMColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: TextStyle(
                color: mine ? Colors.white : RMColors.textPrimary,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('h:mm a').format(time),
                  style: TextStyle(
                    color: mine ? Colors.white70 : RMColors.textHint,
                    fontSize: 10,
                  ),
                ),
                if (mine) ...[
                  SizedBox(width: 4),
                  MessageTicks(pending: pending, read: read),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// WhatsApp-style status ticks for a message the current user sent:
///  - a single outline clock while it's still queued/in flight
///    (typed offline, or the request hasn't confirmed yet)
///  - a double grey check once Supabase has persisted it
///  - a double blue check once the recipient has read it
class MessageTicks extends StatelessWidget {
  final bool pending;
  final bool read;

  const MessageTicks({super.key, required this.pending, required this.read});

  @override
  Widget build(BuildContext context) {
    if (pending) {
      return Icon(Icons.schedule_rounded, size: 13, color: Colors.white70);
    }
    return Icon(
      Icons.done_all_rounded,
      size: 15,
      color: read ? Color(0xFF4FC3F7) : Colors.white70,
    );
  }
}

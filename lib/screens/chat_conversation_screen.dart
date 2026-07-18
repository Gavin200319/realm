import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
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
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final history = await SupabaseService.instance
          .fetchMessages(otherUserId: widget.otherUserId);
      if (mounted) {
        setState(() {
          _messages = history;
          _loading = false;
        });
        _scrollToEnd();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }

    // Live updates for this thread — new messages just append, no
    // manual refresh needed while the conversation is open.
    _sub = SupabaseService.instance
        .watchMessages(otherUserId: widget.otherUserId)
        .listen((rows) {
      if (!mounted) return;
      setState(() => _messages = rows);
      _scrollToEnd();
    });

    SupabaseService.instance.markConversationRead(widget.otherUserId);
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
    setState(() => _sending = true);
    try {
      await SupabaseService.instance.sendMessage(
        recipientId: widget.otherUserId,
        content: text,
      );
      _msgCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
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
                    : _messages.isEmpty
                        ? Center(
                            child: Text(
                              'Say hi to ${widget.otherUsername} 👋',
                              style: TextStyle(color: RMColors.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: EdgeInsets.all(16),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) {
                              final m = _messages[i];
                              final mine = m['sender_id'] == me;
                              final createdAt = DateTime.tryParse(
                                      m['created_at'] as String? ?? '') ??
                                  DateTime.now();
                              return _MessageBubble(
                                text: m['content'] as String? ?? '',
                                time: createdAt,
                                mine: mine,
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

  const _MessageBubble(
      {required this.text, required this.time, required this.mine});

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
            Text(
              DateFormat('h:mm a').format(time),
              style: TextStyle(
                color: mine ? Colors.white70 : RMColors.textHint,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

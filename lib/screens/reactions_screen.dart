import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';

class ReactionsScreen extends StatefulWidget {
  final String dropId;
  const ReactionsScreen({super.key, required this.dropId});

  @override
  State<ReactionsScreen> createState() => _ReactionsScreenState();
}

class _ReactionsScreenState extends State<ReactionsScreen> {
  List<Map<String, dynamic>> _comments = [];
  int _likeCount = 0;
  bool _hasLiked = false;
  bool _loading = true;
  final _commentCtrl = TextEditingController();
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final interactions = await SupabaseService.instance
          .fetchInteractions(dropId: widget.dropId);
      final currentUser = SupabaseService.instance.currentUser;

      setState(() {
        _comments = interactions
            .where((i) => i['type'] == 'comment')
            .toList();
        _likeCount =
            interactions.where((i) => i['type'] == 'like').length;
        _hasLiked = interactions.any((i) =>
            i['type'] == 'like' && i['user_id'] == currentUser?.id);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleLike() async {
    try {
      if (_hasLiked) {
        await SupabaseService.instance.removeLike(dropId: widget.dropId);
        setState(() {
          _hasLiked = false;
          _likeCount--;
        });
      } else {
        await SupabaseService.instance.addLike(dropId: widget.dropId);
        setState(() {
          _hasLiked = true;
          _likeCount++;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _postComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);
    try {
      await SupabaseService.instance.addComment(
        dropId: widget.dropId,
        content: text,
      );
      _commentCtrl.clear();
      await _load();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reactions')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Like bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _toggleLike,
                        child: Row(
                          children: [
                            Icon(
                              _hasLiked
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: _hasLiked ? Colors.red : Colors.grey,
                              size: 28,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$_likeCount',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${_comments.length} comments',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Comments list
                Expanded(
                  child: _comments.isEmpty
                      ? const Center(
                          child: Text('No comments yet — be the first.'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _comments.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            final c = _comments[i];
                            final createdAt = DateTime.tryParse(
                                    c['created_at'] as String? ?? '') ??
                                DateTime.now();
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const CircleAvatar(
                                  radius: 16,
                                  child: Icon(Icons.person, size: 16),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            c['profiles']?['username']
                                                    as String? ??
                                                'unknown',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            DateFormat('MMM d, h:mm a')
                                                .format(createdAt),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(c['content'] as String? ?? ''),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                // Comment input
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentCtrl,
                            decoration: const InputDecoration(
                              hintText: 'Add a comment...',
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            onSubmitted: (_) => _postComment(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _posting ? null : _postComment,
                          icon: _posting
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.send),
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

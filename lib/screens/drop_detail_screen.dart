import 'package:flutter/material.dart';
import '../models/drop.dart';
import '../services/supabase_service.dart';

class DropDetailScreen extends StatefulWidget {
  final Drop drop;
  final double currentLat;
  final double currentLng;

  const DropDetailScreen({
    super.key,
    required this.drop,
    required this.currentLat,
    required this.currentLng,
  });

  @override
  State<DropDetailScreen> createState() => _DropDetailScreenState();
}

class _DropDetailScreenState extends State<DropDetailScreen> {
  bool _unlocking = false;
  String? _error;
  late bool _unlocked;

  @override
  void initState() {
    super.initState();
    _unlocked = widget.drop.isUnlocked;
  }

  Future<void> _unlock() async {
    setState(() {
      _unlocking = true;
      _error = null;
    });
    try {
      final success = await SupabaseService.instance.attemptUnlock(
        dropId: widget.drop.id,
        lat: widget.currentLat,
        lng: widget.currentLng,
      );
      if (success) {
        setState(() => _unlocked = true);
      } else {
        setState(() => _error =
            'Still too far away — get within ${widget.drop.unlockRadiusM}m.');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drop = widget.drop;
    return Scaffold(
      appBar: AppBar(title: const Text('Drop')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_unlocked) ...[
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 16),
              Text(
                'This Drop is locked.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(drop.distanceLabel),
              const SizedBox(height: 24),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              FilledButton(
                onPressed: _unlocking ? null : _unlock,
                child: _unlocking
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Try to unlock'),
              ),
            ] else ...[
              if (drop.mediaUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(drop.mediaUrl!),
                ),
              const SizedBox(height: 16),
              Text(drop.caption ?? '', style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 8),
              Text('by ${drop.creatorUsername}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/drop.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import 'create_drop_screen.dart';
import 'profile_screen.dart';
import 'drop_detail_screen.dart';

/// The core-loop screen: shows Drops near the user, locked ones show
/// distance only, unlocked ones show full content. This is the entire
/// v1 product — no map/AR/marketplace tabs, just this loop.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<Drop> _drops = [];
  Position? _position;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final position = await LocationService.instance.getCurrentPosition();
      final drops = await SupabaseService.instance.fetchNearbyDrops(
        lat: position.latitude,
        lng: position.longitude,
      );
      setState(() {
        _position = position;
        _drops = drops;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDrop(Drop drop) async {
    if (_position == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DropDetailScreen(
          drop: drop,
          currentLat: _position!.latitude,
          currentLng: _position!.longitude,
        ),
      ),
    );
    _refresh(); // re-fetch in case this unlocked something
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Drops'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (_position == null) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CreateDropScreen(
                lat: _position!.latitude,
                lng: _position!.longitude,
              ),
            ),
          );
          _refresh();
        },
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Drop here'),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_drops.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No Drops nearby yet.\nBe the first to leave one.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _drops.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _DropCard(
        drop: _drops[index],
        onTap: () => _openDrop(_drops[index]),
      ),
    );
  }
}

class _DropCard extends StatelessWidget {
  final Drop drop;
  final VoidCallback onTap;

  const _DropCard({required this.drop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final locked = !drop.isUnlocked;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                locked ? Icons.lock_outline : Icons.lock_open,
                color: locked ? Colors.grey : Colors.greenAccent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      locked ? 'Locked Drop' : drop.caption ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: locked
                          ? const TextStyle(fontStyle: FontStyle.italic)
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      locked
                          ? drop.distanceLabel
                          : 'by ${drop.creatorUsername}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

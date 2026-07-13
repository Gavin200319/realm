import 'package:flutter/material.dart';
import '../models/profile_stats.dart';
import '../services/supabase_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ProfileStats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = SupabaseService.instance.currentUser;
    if (user == null) return;
    final stats = await SupabaseService.instance.fetchProfileStats(user.id);
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  List<_Badge> _getBadges(ProfileStats stats) {
    final badges = <_Badge>[];
    if (stats.dropsUnlocked >= 1) badges.add(const _Badge(icon: '🗺️', label: 'First Steps', description: 'Unlocked your first drop'));
    if (stats.dropsUnlocked >= 10) badges.add(const _Badge(icon: '🧭', label: 'Explorer', description: 'Unlocked 10 drops'));
    if (stats.dropsUnlocked >= 50) badges.add(const _Badge(icon: '🌍', label: 'World Walker', description: 'Unlocked 50 drops'));
    if (stats.dropsCreated >= 1) badges.add(const _Badge(icon: '📍', label: 'First Drop', description: 'Left your first drop'));
    if (stats.dropsCreated >= 5) badges.add(const _Badge(icon: '🎨', label: 'Creator', description: 'Left 5 drops in the world'));
    if (stats.dropsCreated >= 20) badges.add(const _Badge(icon: '⭐', label: 'Legend', description: 'Left 20 drops in the world'));
    return badges;
  }

  String _explorerTitle(int unlocked) {
    if (unlocked >= 50) return 'World Walker';
    if (unlocked >= 10) return 'Explorer';
    if (unlocked >= 1) return 'Wanderer';
    return 'Newcomer';
  }

  Widget _buildProgress(BuildContext context, int unlocked) {
    final milestones = [1, 10, 50];
    final next = milestones.firstWhere((m) => m > unlocked, orElse: () => milestones.last);
    final prevIdx = milestones.indexOf(next) - 1;
    final prev = prevIdx < 0 ? 0 : milestones[prevIdx];
    final progress = unlocked >= next ? 1.0 : (unlocked - prev) / (next - prev).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Explorer progress', style: Theme.of(context).textTheme.bodySmall),
            Text('$unlocked / $next unlocks', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: progress.clamp(0.0, 1.0), minHeight: 8),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => SupabaseService.instance.signOut(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Text((_stats?.username ?? '?')[0].toUpperCase(), style: const TextStyle(fontSize: 28)),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('@${_stats?.username ?? ''}', style: Theme.of(context).textTheme.titleLarge),
                          Text(_explorerTitle(_stats?.dropsUnlocked ?? 0),
                              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatBlock(icon: Icons.lock_open, label: 'Places visited', value: _stats?.dropsUnlocked ?? 0),
                      _StatBlock(icon: Icons.add_location_alt, label: 'Drops created', value: _stats?.dropsCreated ?? 0),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _buildProgress(context, _stats?.dropsUnlocked ?? 0),
                  const SizedBox(height: 28),
                  Text('Badges', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _stats == null || _getBadges(_stats!).isEmpty
                      ? const Text('No badges yet — start exploring to earn them.', style: TextStyle(color: Colors.grey))
                      : Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _getBadges(_stats!).map((b) => _BadgeChip(badge: b)).toList(),
                        ),
                ],
              ),
            ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  const _StatBlock({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text('$value', style: Theme.of(context).textTheme.headlineMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Badge {
  final String icon;
  final String label;
  final String description;
  const _Badge({required this.icon, required this.label, required this.description});
}

class _BadgeChip extends StatelessWidget {
  final _Badge badge;
  const _BadgeChip({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: badge.description,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(badge.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(badge.label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

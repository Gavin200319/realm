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
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@${_stats?.username ?? ''}',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatBlock(
                        label: 'Drops created',
                        value: _stats?.dropsCreated ?? 0,
                      ),
                      _StatBlock(
                        label: 'Places visited',
                        value: _stats?.dropsUnlocked ?? 0,
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String label;
  final int value;

  const _StatBlock({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$value', style: Theme.of(context).textTheme.headlineMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

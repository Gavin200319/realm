import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile_stats.dart';
import '../services/supabase_service.dart';
import '../theme/rm_theme.dart';
import '../widgets/location_autocomplete_field.dart';

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
    setState(() { _stats = stats; _loading = false; });
  }

  List<_Badge> _getBadges(ProfileStats stats) {
    final badges = <_Badge>[];
    if (stats.dropsUnlocked >= 1)
      badges.add(const _Badge(icon: Icons.flag_rounded, label: 'First Steps', color: RMColors.primary));
    if (stats.dropsUnlocked >= 10)
      badges.add(const _Badge(icon: Icons.explore_rounded, label: 'Explorer', color: Color(0xFF00BCD4)));
    if (stats.dropsUnlocked >= 50)
      badges.add(const _Badge(icon: Icons.public_rounded, label: 'World Walker', color: RMColors.success));
    if (stats.dropsCreated >= 1)
      badges.add(const _Badge(icon: Icons.add_location_rounded, label: 'First Drop', color: RMColors.accent));
    if (stats.dropsCreated >= 5)
      badges.add(const _Badge(icon: Icons.palette_rounded, label: 'Creator', color: Color(0xFFE040FB)));
    if (stats.dropsCreated >= 20)
      badges.add(const _Badge(icon: Icons.star_rounded, label: 'Legend', color: RMColors.accent));
    return badges;
  }

  String _explorerTitle(int unlocked) {
    if (unlocked >= 50) return 'World Walker';
    if (unlocked >= 10) return 'Explorer';
    if (unlocked >= 1) return 'Wanderer';
    return 'Newcomer';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RMColors.background,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: RMColors.background,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: RMColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Avatar + info
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [RMColors.primary, RMColors.primaryDim],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: RMColors.primary.withOpacity(0.3),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              (_stats?.username ?? '?')[0].toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '@${_stats?.username ?? ''}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: RMColors.primaryDim,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _explorerTitle(_stats?.dropsUnlocked ?? 0),
                            style: const TextStyle(
                                color: RMColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Stats row
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.lock_open_rounded,
                          label: 'Visited',
                          value: '${_stats?.dropsUnlocked ?? 0}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.add_location_alt_rounded,
                          label: 'Dropped',
                          value: '${_stats?.dropsCreated ?? 0}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Progress bar
                  _buildProgress(_stats?.dropsUnlocked ?? 0),
                  const SizedBox(height: 24),

                  // Badges
                  const Text('Badges',
                      style: TextStyle(
                          color: RMColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  const SizedBox(height: 12),
                  _stats == null || _getBadges(_stats!).isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: RMColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: RMColors.border),
                          ),
                          child: const Text(
                            'No badges yet — explore drops to earn them.',
                            style: TextStyle(color: RMColors.textSecondary),
                          ),
                        )
                      : Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _getBadges(_stats!)
                              .map((b) => _BadgeChip(badge: b))
                              .toList(),
                        ),
                  const SizedBox(height: 28),

                  // Settings section
                  const Text('Settings',
                      style: TextStyle(
                          color: RMColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  const SizedBox(height: 12),
                  _SettingsTile(
                    icon: Icons.person_outline_rounded,
                    label: 'Edit profile',
                    onTap: () => _showEditProfile(context),
                  ),
                  _SettingsTile(
                    icon: Icons.notifications_none_rounded,
                    label: 'Notifications',
                    onTap: () => _showNotificationSettings(context),
                  ),
                  _SettingsTile(
                    icon: Icons.lock_outline_rounded,
                    label: 'Privacy',
                    onTap: () => _showPrivacySettings(context),
                  ),
                  _SettingsTile(
                    icon: Icons.refresh_rounded,
                    label: 'Reset onboarding tutorials',
                    onTap: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.clear();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Tutorials reset — reopen the app.')),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 8),

                  // Account section
                  const Text('Account',
                      style: TextStyle(
                          color: RMColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  const SizedBox(height: 12),
                  _SettingsTile(
                    icon: Icons.logout_rounded,
                    label: 'Sign out',
                    onTap: () => _confirmSignOut(context),
                  ),
                  _SettingsTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete account',
                    destructive: true,
                    onTap: () => _confirmDeleteAccount(context),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildProgress(int unlocked) {
    final milestones = [1, 10, 50];
    final next = milestones.firstWhere(
        (m) => m > unlocked, orElse: () => milestones.last);
    final prevIdx = milestones.indexOf(next) - 1;
    final prev = prevIdx < 0 ? 0 : milestones[prevIdx];
    final progress = unlocked >= next
        ? 1.0
        : (unlocked - prev) / (next - prev).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Explorer progress',
                style: TextStyle(
                    color: RMColors.textSecondary, fontSize: 12)),
            Text('$unlocked / $next drops unlocked',
                style: const TextStyle(
                    color: RMColors.textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: RMColors.surfaceAlt,
            valueColor:
                const AlwaysStoppedAnimation<Color>(RMColors.primary),
          ),
        ),
      ],
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showEditProfile(BuildContext context) {
    final displayCtrl = TextEditingController();
    String homeCity = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: RMColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Edit Profile',
                style: TextStyle(
                    color: RMColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 18)),
            const SizedBox(height: 20),
            TextField(
              controller: displayCtrl,
              style: const TextStyle(color: RMColors.textPrimary),
              decoration:
                  const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: 14),
            LocationAutocompleteField(
              label: 'Home city',
              onSelected: (v) => homeCity = v,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                final user = SupabaseService.instance.currentUser;
                if (user == null) return;
                try {
                  await SupabaseService.instance.updateProfile(
                    userId: user.id,
                    displayName: displayCtrl.text.trim().isEmpty
                        ? null
                        : displayCtrl.text.trim(),
                    homeCity: homeCity.isEmpty ? null : homeCity,
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNotificationSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: RMColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => const _NotificationSettingsSheet(),
    );
  }

  void _showPrivacySettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: RMColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => const _PrivacySettingsSheet(),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RMColors.surface,
        title: const Text('Sign out',
            style: TextStyle(color: RMColors.textPrimary)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(color: RMColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: RMColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await SupabaseService.instance.signOut();
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RMColors.surface,
        title: const Text('Delete account',
            style: TextStyle(color: RMColors.danger)),
        content: const Text(
          'This will permanently delete your account, all your drops, and all your data. This cannot be undone.',
          style: TextStyle(color: RMColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: RMColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: RMColors.danger),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await SupabaseService.instance.deleteAccount();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              }
            },
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
  }
}

// ── Notification settings sheet ───────────────────────────────────────────────

class _NotificationSettingsSheet extends StatefulWidget {
  const _NotificationSettingsSheet();

  @override
  State<_NotificationSettingsSheet> createState() =>
      _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState
    extends State<_NotificationSettingsSheet> {
  bool _nearbyDrops = true;
  bool _reactions = true;
  bool _newFollowers = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Notifications',
              style: TextStyle(
                  color: RMColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
          const SizedBox(height: 16),
          _SwitchRow(
            label: 'Nearby drops',
            sub: 'Alert when a drop is within range',
            value: _nearbyDrops,
            onChanged: (v) => setState(() => _nearbyDrops = v),
          ),
          _SwitchRow(
            label: 'Reactions',
            sub: 'When someone reacts to your drop',
            value: _reactions,
            onChanged: (v) => setState(() => _reactions = v),
          ),
          _SwitchRow(
            label: 'New followers',
            sub: 'When someone starts following you',
            value: _newFollowers,
            onChanged: (v) => setState(() => _newFollowers = v),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Privacy settings sheet ───────────────────────────────────────────────────

class _PrivacySettingsSheet extends StatefulWidget {
  const _PrivacySettingsSheet();

  @override
  State<_PrivacySettingsSheet> createState() => _PrivacySettingsSheetState();
}

class _PrivacySettingsSheetState extends State<_PrivacySettingsSheet> {
  bool _showOnMap = true;
  bool _allowDiscovery = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Privacy',
              style: TextStyle(
                  color: RMColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
          const SizedBox(height: 16),
          _SwitchRow(
            label: 'Show on map',
            sub: 'Allow others to see your public drops on the map',
            value: _showOnMap,
            onChanged: (v) => setState(() => _showOnMap = v),
          ),
          _SwitchRow(
            label: 'Allow discovery',
            sub: 'Let other users find you by username search',
            value: _allowDiscovery,
            onChanged: (v) => setState(() => _allowDiscovery = v),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RMColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RMColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: RMColors.primary, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: RMColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(
                  color: RMColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _Badge {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge(
      {required this.icon, required this.label, required this.color});
}

class _BadgeChip extends StatelessWidget {
  final _Badge badge;
  const _BadgeChip({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: badge.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: badge.color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, color: badge.color, size: 14),
          const SizedBox(width: 6),
          Text(badge.label,
              style: TextStyle(
                  color: badge.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? RMColors.danger : RMColors.textPrimary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: RMColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: destructive
                  ? RMColors.danger.withOpacity(0.3)
                  : RMColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ),
            Icon(Icons.chevron_right_rounded,
                color: destructive
                    ? RMColors.danger.withOpacity(0.5)
                    : RMColors.textHint,
                size: 18),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: RMColors.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 14)),
                Text(sub,
                    style: const TextStyle(
                        color: RMColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: RMColors.primary,
          ),
        ],
      ),
    );
  }
}

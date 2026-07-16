import 'package:flutter/material.dart';
import '../services/device_capability_service.dart';
import '../theme/rm_theme.dart';
import 'feed_screen.dart';
import 'map_screen.dart';
import 'ar_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  // Checked once at startup in main.dart — devices below API 28 never
  // get the AR tab, so ARScreen (and ar_flutter_plugin_2) is never built.
  bool get _arAvailable => DeviceCapabilityService.instance.arSupported;

  @override
  Widget build(BuildContext context) {
    final screens = [
      const FeedScreen(),
      const MapScreen(),
      if (_arAvailable) const ARScreen(),
    ];

    // Guard against a stale index if AR was the selected tab and
    // somehow became unavailable (shouldn't happen since capability is
    // fixed for the process lifetime, but keeps IndexedStack safe).
    final safeIndex = _currentIndex < screens.length ? _currentIndex : 0;

    return Scaffold(
      backgroundColor: RMColors.background,
      body: IndexedStack(
        index: safeIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: RMColors.border, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: safeIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          backgroundColor: RMColors.surface,
          indicatorColor: RMColors.primaryDim,
          height: 64,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.explore_outlined, color: RMColors.textSecondary),
              selectedIcon: Icon(Icons.explore_rounded, color: RMColors.primary),
              label: 'Explore',
            ),
            const NavigationDestination(
              icon: Icon(Icons.map_outlined, color: RMColors.textSecondary),
              selectedIcon: Icon(Icons.map_rounded, color: RMColors.primary),
              label: 'Map',
            ),
            if (_arAvailable)
              const NavigationDestination(
                icon: Icon(Icons.view_in_ar_outlined,
                    color: RMColors.textSecondary),
                selectedIcon:
                    Icon(Icons.view_in_ar_rounded, color: RMColors.primary),
                label: 'AR',
              ),
          ],
        ),
      ),
    );
  }
}

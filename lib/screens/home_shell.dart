import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RMColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          FeedScreen(),
          MapScreen(),
          ARScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: RMColors.border, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          backgroundColor: RMColors.surface,
          indicatorColor: RMColors.primaryDim,
          height: 64,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.explore_outlined, color: RMColors.textSecondary),
              selectedIcon: Icon(Icons.explore_rounded, color: RMColors.primary),
              label: 'Explore',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined, color: RMColors.textSecondary),
              selectedIcon: Icon(Icons.map_rounded, color: RMColors.primary),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Icon(Icons.view_in_ar_outlined, color: RMColors.textSecondary),
              selectedIcon: Icon(Icons.view_in_ar_rounded, color: RMColors.primary),
              label: 'AR',
            ),
          ],
        ),
      ),
    );
  }
}

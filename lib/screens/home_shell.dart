import 'package:flutter/material.dart';
import '../theme/rm_theme.dart';
import 'feed_screen.dart';
import 'compass_screen.dart';
import 'chats_screen.dart';

class HomeShell extends StatefulWidget {
  HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      FeedScreen(),
      CompassScreen(),
      ChatsScreen(),
    ];

    return Scaffold(
      backgroundColor: RMColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: RMColors.border, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          backgroundColor: RMColors.surface,
          indicatorColor: RMColors.primaryDim,
          height: 64,
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.explore_outlined, color: RMColors.textSecondary),
              selectedIcon: Icon(Icons.explore_rounded, color: RMColors.primary),
              label: 'Explore',
            ),
            NavigationDestination(
              icon: Icon(Icons.navigation_outlined,
                  color: RMColors.textSecondary),
              selectedIcon:
                  Icon(Icons.navigation_rounded, color: RMColors.primary),
              label: 'Compass',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded,
                  color: RMColors.textSecondary),
              selectedIcon:
                  Icon(Icons.chat_bubble_rounded, color: RMColors.primary),
              label: 'Chats',
            ),
          ],
        ),
      ),
    );
  }
}

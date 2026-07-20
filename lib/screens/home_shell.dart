import 'package:flutter/material.dart';
import '../theme/rm_theme.dart';
import 'feed_screen.dart';
import 'compass_screen.dart';
import 'chats_screen.dart';
import 'flicks_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  // Keys give us a handle onto each tab's State so we can force a fresh
  // fetch every time that tab is (re)selected — see _onDestinationSelected.
  // An IndexedStack keeps every tab's widget alive in the background, but
  // "alive" isn't the same as "up to date": a tab whose first load raced
  // location/auth and lost, or whose data is just stale from sitting
  // untouched, would otherwise stay that way for the rest of the session
  // even after switching away and back.
  final _feedKey = GlobalKey<FeedScreenState>();
  final _compassKey = GlobalKey<CompassScreenState>();
  final _flicksKey = GlobalKey<FlicksScreenState>();

  void _onDestinationSelected(int index) {
    setState(() => _currentIndex = index);
    switch (index) {
      case 0:
        _feedKey.currentState?.refresh();
        break;
      case 1:
        _compassKey.currentState?.refresh();
        break;
      case 2:
        _flicksKey.currentState?.refresh();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RMColors.background,
      body: IndexedStack(
        index: _currentIndex,
        // IndexedStack builds and keeps ALL of these alive simultaneously,
        // not just the visible one — that's what makes the tab-preserving
        // navigation work, but it also means a naive child has no idea
        // whether it's the one currently on screen. FlicksScreen needs
        // that signal explicitly (see isActive) so it knows when it's
        // allowed to actually play video, rather than just going by its
        // own internal notion of "active page" within its feed.
        children: [
          FeedScreen(key: _feedKey),
          CompassScreen(key: _compassKey),
          FlicksScreen(key: _flicksKey, isActive: _currentIndex == 2),
          ChatsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: RMColors.border, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _onDestinationSelected,
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
              icon: Icon(Icons.movie_creation_outlined,
                  color: RMColors.textSecondary),
              selectedIcon:
                  Icon(Icons.movie_creation_rounded, color: RMColors.primary),
              label: 'Flicks',
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

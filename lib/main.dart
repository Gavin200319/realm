import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_gate.dart';
import 'screens/splash_screen.dart';
import 'services/data_saver_service.dart';
import 'services/privacy_settings_sync_service.dart';
import 'theme/rm_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Call runApp() immediately, before any of the async setup below —
  // that's what lets Flutter start painting our own branded splash
  // screen right away instead of leaving the plain native launch
  // screen up for the whole duration of that setup.
  runApp(RealityMergeApp());
}

class RealityMergeApp extends StatefulWidget {
  RealityMergeApp({super.key});

  @override
  State<RealityMergeApp> createState() => _RealityMergeAppState();
}

class _RealityMergeAppState extends State<RealityMergeApp> {
  late Future<void> _bootstrap = _boot();
  String? _bootstrapError;

  Future<void> _boot() async {
    final startedAt = DateTime.now();
    try {
      await dotenv.load(fileName: '.env');
      await ThemeController.instance.init();
      await DataSaverService.instance.init();
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL']!,
        anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      );
      // Not awaited on purpose: this starts the connectivity listener
      // and attempts an immediate flush of any privacy-setting change
      // left over from a previous offline session, but there's no
      // reason to make the splash screen wait on it — if it's slow or
      // fails, the toggle sheet already shows the locally-saved value
      // either way.
      unawaited(PrivacySettingsSyncService.instance.init());
    } catch (e) {
      _bootstrapError = e.toString();
    }

    // Keep the splash up for a minimum stretch so it reads as an
    // intentional loading moment rather than a single-frame flicker
    // on a warm start / fast connection.
    const minSplash = Duration(milliseconds: 900);
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < minSplash) {
      await Future.delayed(minSplash - elapsed);
    }

    // ThemeController.init() repoints RMColors/mode but doesn't itself
    // notify listeners (that's only done on an explicit user toggle
    // later) — this rebuild is what picks up a previously-saved
    // light/dark/system preference for the very first real frame.
    if (mounted) setState(() {});
  }

  void _retry() {
    setState(() {
      _bootstrapError = null;
      _bootstrap = _boot();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        final isDark = ThemeController.instance.isDark;
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ));

        return MaterialApp(
          title: 'Reality Merge',
          debugShowCheckedModeBanner: false,
          theme: RMTheme.light,
          darkTheme: RMTheme.dark,
          themeMode: ThemeController.instance.mode,
          home: FutureBuilder<void>(
            future: _bootstrap,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SplashScreen();
              }
              if (_bootstrapError != null) {
                return SplashErrorScreen(
                    message: _bootstrapError!, onRetry: _retry);
              }
              return AuthGate();
            },
          ),
        );
      },
    );
  }
}

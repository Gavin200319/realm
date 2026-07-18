import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';
import 'home_shell.dart';

class AuthGate extends StatelessWidget {
  AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: SupabaseService.instance.authStateChanges,
      builder: (context, snapshot) {
        final session = SupabaseService.instance.currentUser;
        if (session != null) {
          return HomeShell();
        }
        return LoginScreen();
      },
    );
  }
}

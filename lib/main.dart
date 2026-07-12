import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const RealityMergeApp());
}

class RealityMergeApp extends StatelessWidget {
  const RealityMergeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reality Merge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C4FF6),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

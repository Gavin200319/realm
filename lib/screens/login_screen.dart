import 'package:flutter/material.dart';
import '../services/account_manager_service.dart';
import '../services/supabase_service.dart';
import '../widgets/location_autocomplete_field.dart';
import 'home_shell.dart';

class LoginScreen extends StatefulWidget {
  /// True when this screen was pushed on top of an already-signed-in
  /// session specifically to add another account (from the account
  /// switcher), rather than being the app's initial auth screen. This
  /// only changes copy/navigation on success — the sign-in/sign-up
  /// calls themselves are identical either way.
  final bool isAddingAccount;

  LoginScreen({super.key, this.isAddingAccount = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isSignUp = false;
  bool _loading = false;
  String? _error;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  String _homeCity = ''; // set by autocomplete selection

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isSignUp) {
        await SupabaseService.instance.signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          username: _usernameCtrl.text.trim(),
          displayName: _displayNameCtrl.text.trim(),
          homeCity: _homeCity,
        );
      } else {
        await SupabaseService.instance.signIn(
          identifier: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      }

      // Snapshot this account's session + profile summary so it shows
      // up in the account switcher and can be switched back to later,
      // even offline.
      await AccountManagerService.instance.rememberCurrentSession();

      if (!mounted) return;
      if (widget.isAddingAccount) {
        // A second account just became active on top of an already-
        // running app. Rather than trust every open screen to notice
        // the swap on its own, drop the whole navigation stack and
        // rebuild fresh under the new account — the same thing that
        // happens when switching from the account switcher sheet.
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => HomeShell()),
          (route) => false,
        );
      }
      // Otherwise AuthGate's stream listener handles navigation.
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isAddingAccount
          ? AppBar(title: Text('Add account'))
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: widget.isAddingAccount ? 8 : 48),
              Text(
                'Reality Merge',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              Text(
                widget.isAddingAccount
                    ? 'Sign in or sign up with another account.'
                    : 'The world is no longer empty.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(height: 32),
              TextField(
                controller: _emailCtrl,
                decoration: InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              if (_isSignUp) ...[
                SizedBox(height: 12),
                TextField(
                  controller: _usernameCtrl,
                  decoration: InputDecoration(labelText: 'Username'),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: _displayNameCtrl,
                  decoration: InputDecoration(labelText: 'Display name'),
                ),
                SizedBox(height: 12),
                LocationAutocompleteField(
                  label: 'Home city',
                  onSelected: (value) => setState(() => _homeCity = value),
                ),
              ],
              SizedBox(height: 24),
              if (_error != null)
                Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: TextStyle(color: Colors.red)),
                ),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isSignUp ? 'Sign up' : 'Log in'),
              ),
              TextButton(
                onPressed: () => setState(() => _isSignUp = !_isSignUp),
                child: Text(_isSignUp
                    ? 'Already have an account? Log in'
                    : "Don't have an account? Sign up"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

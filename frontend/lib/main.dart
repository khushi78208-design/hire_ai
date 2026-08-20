import 'package:flutter/material.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';

void main() {
  runApp(const HireAIApp());
}

class HireAIApp extends StatefulWidget {
  const HireAIApp({super.key});

  /// Lets any screen re-theme the app when the signed-in role changes.
  static _HireAIAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_HireAIAppState>();

  @override
  State<HireAIApp> createState() => _HireAIAppState();
}

class _HireAIAppState extends State<HireAIApp> {
  String? _role;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final role = await TokenStorage.getRole();
    if (mounted) setState(() => _role = role);
  }

  void setRole(String? role) {
    if (_role != role) setState(() => _role = role);
  }

  @override
  Widget build(BuildContext context) {
    // Recruiters and candidates get visibly different palettes — one glance
    // tells you which side of the product you are on.
    final theme = switch (_role) {
      'hr' || 'admin' => AppTheme.hr(),
      'candidate' => AppTheme.candidate(),
      _ => AppTheme.neutral(),
    };

    return MaterialApp(
      title: 'HireAI',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const AuthGate(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const HomeScreen(),
      },
    );
  }
}

/// Decides where to land on cold start: if a token is already stored,
/// skip the login screen entirely.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _loggedIn;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final loggedIn = await TokenStorage.isLoggedIn();
    if (!mounted) return;
    setState(() => _loggedIn = loggedIn);
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedIn == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _loggedIn! ? const HomeScreen() : const LoginScreen();
  }
}
